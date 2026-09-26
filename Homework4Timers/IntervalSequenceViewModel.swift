import SwiftUI
import Foundation
import Combine
import UserNotifications
import CoreHaptics
import AudioToolbox
import AVFoundation
import AVFAudio
#if canImport(UIKit)
import UIKit
#endif

struct ExecutionStep {
    let item: TimerIntervalEntity
    let originalIndex: Int
}

final class TimerSequenceViewModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var items: [TimerIntervalEntity] = []
    @Published var currentLabel: String? = nil
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var isWaitingForAcknowledgment: Bool = false
    @Published var progressIndex: Int? = nil
    @Published var currentStepIndex: Int? = nil
    @Published var totalStepsCount: Int? = nil
    @Published var remainingSeconds: Int = 0
    
    var autoContinue: Bool {
        get {
            UserDefaults.standard.bool(forKey: "autoContinueNextInterval")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoContinueNextInterval")
            objectWillChange.send()
        }
    }
    
    private var executionPlan: [ExecutionStep] = []
    private var sequenceStartDate: Date? = nil
    private var currentStepStartDate: Date? = nil
    private var pausedRemainingSeconds: Int? = nil
    private var lastNotifiedStepIndex: Int? = nil
    
    private var tickCancellable: AnyCancellable?
    private var hapticEngine: CHHapticEngine?
    private var notificationCancellables = Set<AnyCancellable>()
    
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        setupNotificationCategories()
        prepareHaptics()
        requestNotificationPermission()
        setupNotificationObservers()
    }
    
    deinit {
        stopTicking()
        endBackgroundTask()
        deactivateAudioSession()
    }

    func updateAutoContinue() {
        objectWillChange.send()
    }

    func bind(items: [TimerIntervalEntity]) {
        self.items = items
    }

    func addItem(minutes: Int, label: String, itemType: IntervalItemType = .interval, repeatCount: Int = 1) {
        let new = TimerIntervalEntity(minutes: minutes, label: label, itemType: itemType, repeatCount: repeatCount)
        items.append(new)
    }

    func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func buildExecutionPlan(items: [TimerIntervalEntity]) -> [ExecutionStep] {
        var steps: [ExecutionStep] = []
        
        func expand(range: Range<Int>) {
            var i = range.lowerBound
            while i < range.upperBound {
                let item = items[i]
                switch item.itemType {
                case .interval:
                    if item.minutes > 0 {
                        steps.append(ExecutionStep(item: item, originalIndex: i))
                    }
                    i += 1
                case .openBracket:
                    var depth = 1
                    var j = i + 1
                    while j < range.upperBound {
                        if items[j].itemType == .openBracket {
                            depth += 1
                        } else if items[j].itemType == .closeBracket {
                            depth -= 1
                            if depth == 0 {
                                break
                            }
                        }
                        j += 1
                    }
                    
                    if j < range.upperBound && items[j].itemType == .closeBracket {
                        let count = max(1, items[j].repeatCount)
                        let subRange = (i + 1)..<j
                        for _ in 0..<count {
                            expand(range: subRange)
                        }
                        i = j + 1
                    } else {
                        i += 1
                    }
                case .closeBracket:
                    i += 1
                }
            }
        }
        
        expand(range: 0..<items.count)
        return steps
    }

    func start() {
        if isRunning && isPaused {
            resume()
            return
        }
        if isRunning && isWaitingForAcknowledgment {
            acknowledgeNextStep()
            return
        }
        let plan = buildExecutionPlan(items: items)
        guard !isRunning, !plan.isEmpty else { return }
        
        executionPlan = plan
        isRunning = true
        isPaused = false
        isWaitingForAcknowledgment = false
        lastNotifiedStepIndex = nil
        totalStepsCount = plan.count
        
        let now = Date()
        sequenceStartDate = now
        currentStepStartDate = now
        pausedRemainingSeconds = nil
        
        setupAudioSession()
        startBackgroundTask()
        startTicking()
        
        updateUIForStep(0)
        
        if autoContinue {
            scheduleAllNotificationsForSequence(fromStepIndex: 0)
        } else {
            scheduleNotificationForSingleStep(stepIndex: 0)
        }
        
        notifyAndHaptic(title: plan[0].item.label)
        lastNotifiedStepIndex = 0
        refreshRemainingTime()
    }

    func acknowledgeNextStep() {
        guard isRunning, isWaitingForAcknowledgment, let current = currentStepIndex else { return }
        let nextIndex = current + 1
        if nextIndex < executionPlan.count {
            isWaitingForAcknowledgment = false
            currentStepIndex = nextIndex
            currentStepStartDate = Date()
            pausedRemainingSeconds = nil
            updateUIForStep(nextIndex)
            scheduleNotificationForSingleStep(stepIndex: nextIndex)
            notifyAndHaptic(title: executionPlan[nextIndex].item.label)
            lastNotifiedStepIndex = nextIndex
            refreshRemainingTime()
        } else {
            stopInternal()
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        refreshRemainingTime()
        isPaused = true
        isWaitingForAcknowledgment = false
        pausedRemainingSeconds = remainingSeconds
        cancelPendingNotifications()
    }

    func resume() {
        guard isRunning, isPaused, let currentIdx = currentStepIndex else { return }
        isPaused = false
        let now = Date()
        let currentRem = pausedRemainingSeconds ?? remainingSeconds
        let stepDuration = Double(max(0, executionPlan[currentIdx].item.minutes * 60))
        let elapsedInStep = max(0, stepDuration - Double(currentRem))
        
        currentStepStartDate = now.addingTimeInterval(-elapsedInStep)
        
        if autoContinue {
            var cumulativeBefore: Double = 0
            for idx in 0..<currentIdx {
                cumulativeBefore += Double(max(0, executionPlan[idx].item.minutes * 60))
            }
            sequenceStartDate = now.addingTimeInterval(-(cumulativeBefore + elapsedInStep))
            scheduleAllNotificationsForSequence(fromStepIndex: currentIdx)
        } else {
            scheduleNotificationForSingleStep(stepIndex: currentIdx)
        }
        
        pausedRemainingSeconds = nil
        refreshRemainingTime()
    }

    func stop() {
        stopInternal()
    }

    private func stopInternal() {
        stopTicking()
        cancelPendingNotifications()
        endBackgroundTask()
        deactivateAudioSession()
        
        isRunning = false
        isPaused = false
        isWaitingForAcknowledgment = false
        progressIndex = nil
        currentStepIndex = nil
        totalStepsCount = nil
        currentLabel = nil
        remainingSeconds = 0
        sequenceStartDate = nil
        currentStepStartDate = nil
        pausedRemainingSeconds = nil
        lastNotifiedStepIndex = nil
        executionPlan = []
    }

    private func updateUIForStep(_ index: Int) {
        guard index < executionPlan.count else { return }
        let step = executionPlan[index]
        currentStepIndex = index
        progressIndex = step.originalIndex
        currentLabel = step.item.label
        remainingSeconds = max(0, step.item.minutes * 60)
    }

    func refreshRemainingTime() {
        guard isRunning, !isPaused else { return }
        
        let now = Date()
        let plan = executionPlan
        guard !plan.isEmpty else {
            stopInternal()
            return
        }
        
        if autoContinue {
            guard let startSeq = sequenceStartDate else { return }
            let totalElapsed = now.timeIntervalSince(startSeq)
            
            var cumulative: Double = 0
            var activeIdx: Int? = nil
            var activeRem: Int = 0
            
            for (idx, step) in plan.enumerated() {
                let duration = Double(max(0, step.item.minutes * 60))
                let stepStart = cumulative
                let stepEnd = cumulative + duration
                
                if totalElapsed < stepEnd {
                    activeIdx = idx
                    activeRem = max(0, Int(ceil(stepEnd - totalElapsed)))
                    break
                }
                cumulative = stepEnd
            }
            
            if let idx = activeIdx {
                if currentStepIndex != idx {
                    currentStepIndex = idx
                    updateUIForStep(idx)
                    if lastNotifiedStepIndex != idx {
                        lastNotifiedStepIndex = idx
                        notifyAndHaptic(title: plan[idx].item.label)
                    }
                }
                remainingSeconds = activeRem
            } else {
                // Sequence finished
                if let lastStep = plan.last {
                    notifyExpiration(title: lastStep.item.label, isSequenceEnd: true)
                }
                stopInternal()
            }
        } else {
            if isWaitingForAcknowledgment { return }
            guard let currentIdx = currentStepIndex, currentIdx < plan.count, let stepStart = currentStepStartDate else { return }
            let stepDuration = Double(max(0, plan[currentIdx].item.minutes * 60))
            let elapsed = now.timeIntervalSince(stepStart)
            let rem = max(0, Int(ceil(stepDuration - elapsed)))
            
            remainingSeconds = rem
            if rem <= 0 {
                remainingSeconds = 0
                isWaitingForAcknowledgment = true
                notifyExpiration(title: plan[currentIdx].item.label, isSequenceEnd: currentIdx == plan.count - 1)
            }
        }
    }

    // MARK: - Notifications Scheduling for Lock Screen & Background
    private func scheduleAllNotificationsForSequence(fromStepIndex: Int) {
        cancelPendingNotifications()
        guard autoContinue, let startSeq = sequenceStartDate else { return }
        
        let now = Date()
        var cumulative: Double = 0
        
        for (idx, step) in executionPlan.enumerated() {
            let duration = Double(max(0, step.item.minutes * 60))
            cumulative += duration
            
            if idx >= fromStepIndex {
                let stepEndDate = startSeq.addingTimeInterval(cumulative)
                let timeInterval = stepEndDate.timeIntervalSince(now)
                
                if timeInterval > 0 {
                    let titleText = step.item.label.isEmpty ? "Intervallum" : step.item.label
                    let content = UNMutableNotificationContent()
                    content.title = titleText
                    content.body = (idx == executionPlan.count - 1) ? "Az összes időzítés lejárt!" : "Időzítés lejárt!"
                    content.sound = .defaultRingtone
                    content.interruptionLevel = .timeSensitive
                    content.categoryIdentifier = "TIMER_EXPIRED"
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
                    let request = UNNotificationRequest(identifier: "timer_step_\(idx)_end", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
                }
            }
        }
    }

    func triggerSpeechInBackground(text: String) {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

        // Időt kérünk az iOS-től a háttérbeni feladat elindítására
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TextToSpeechTask") {
            // Ha lejár az idő, lezárjuk a taskot
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        // Elindítjuk a felolvasást
        SpeechManager.shared.speak(text: text)

        // Hagyunk 3 másodpercet a szintetizátornak, hogy elindítsa az audio streamet, majd visszaadjuk a task-ot
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
    }
    
    private func scheduleNotificationForSingleStep(stepIndex: Int) {
        cancelPendingNotifications()
        guard stepIndex < executionPlan.count, let stepStart = currentStepStartDate else { return }
        
        let now = Date()
        let step = executionPlan[stepIndex]
        let duration = Double(max(0, step.item.minutes * 60))
        let endDate = stepStart.addingTimeInterval(duration)
        let timeInterval = endDate.timeIntervalSince(now)
        
        if timeInterval > 0 {
            let titleText = step.item.label.isEmpty ? "Intervallum" : step.item.label
            let content = UNMutableNotificationContent()
            content.title = titleText
            content.body = (stepIndex == executionPlan.count - 1) ? "Az összes időzítés lejárt!" : "Időzítés lejárt!"
            content.sound = .defaultRingtone
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = "TIMER_EXPIRED"
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: "timer_step_\(stepIndex)_end", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Audio Session & Background Task
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("AudioSession configuration failed: \(error)")
        }
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch { }
    }

    private func startBackgroundTask() {
        #if canImport(UIKit)
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "IntervalTimerTask") { [weak self] in
            self?.endBackgroundTask()
        }
        #endif
    }

    private func endBackgroundTask() {
        #if canImport(UIKit)
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
    }

    private func setupNotificationObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshRemainingTime()
            }
            .store(in: &notificationCancellables)
        #endif
    }

    // MARK: - Countdown ticks
    private func startTicking() {
        tickCancellable?.cancel()
        tickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isRunning && !self.isPaused {
                    self.refreshRemainingTime()
                }
            }
    }

    private func stopTicking() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }

    // MARK: - UNUserNotificationCenterDelegate
    private func setupNotificationCategories() {
        let acknowledgeAction = UNNotificationAction(
            identifier: "ACKNOWLEDGE_ACTION",
            title: "Következő szakasz indítása",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "TIMER_EXPIRED",
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.acknowledgeNextStep()
        }
        completionHandler()
    }

    // MARK: - Notifications, Sound & Haptics
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyAndHaptic(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Intervallum" : title
        content.body = "Új szakasz kezdődik"
        content.sound = .defaultRingtone
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        //playSound()
        triggerSpeechInBackground(text: title + " " + String(localized: "szakasz kezdődik"))
        playHaptic()
    }

    private func notifyExpiration(title: String, isSequenceEnd: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Intervallum" : title
        content.body = isSequenceEnd ? "Az összes időzítés lejárt!" : "Időzítés lejárt!"
        content.sound = .defaultRingtone
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "TIMER_EXPIRED"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        //playSound()
        triggerSpeechInBackground(text: title + " " + String(localized: "szakasz lejárt"))
        playHaptic()
    }

    private func playSound() {
        AudioServicesPlayAlertSound(1005)
    }

    private func prepareHaptics() {
        do {
            self.hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch { }
    }

    private func playHaptic() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            
            let continuousEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [sharpness, intensity],
                relativeTime: 0,
                duration: 1.5
            )
            let pulse1 = CHHapticEvent(eventType: .hapticTransient, parameters: [sharpness, intensity], relativeTime: 0)
            let pulse2 = CHHapticEvent(eventType: .hapticTransient, parameters: [sharpness, intensity], relativeTime: 0.5)
            let pulse3 = CHHapticEvent(eventType: .hapticTransient, parameters: [sharpness, intensity], relativeTime: 1.0)
            
            do {
                let pattern = try CHHapticPattern(events: [continuousEvent, pulse1, pulse2, pulse3], parameters: [])
                let player = try hapticEngine?.makePlayer(with: pattern)
                try player?.start(atTime: 0)
            } catch { }
        }
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}
