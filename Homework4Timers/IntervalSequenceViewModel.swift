import SwiftUI
import Foundation
import Combine
import UserNotifications
import CoreHaptics
import AudioToolbox
import AVFoundation
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
    @Published var progressIndex: Int? = nil
    @Published var currentStepIndex: Int? = nil
    @Published var totalStepsCount: Int? = nil
    @Published var remainingSeconds: Int = 0
    
    private var runner: Task<Void, Never>? = nil
    private var tickCancellable: AnyCancellable?
    private var hapticEngine: CHHapticEngine?
    private var stepEndDate: Date? = nil
    private var notificationCancellables = Set<AnyCancellable>()
    
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        prepareHaptics()
        requestNotificationPermission()
        setupNotificationObservers()
    }
    
    deinit {
        stopTicking()
        endBackgroundTask()
        deactivateAudioSession()
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
        let plan = buildExecutionPlan(items: items)
        guard !isRunning, !plan.isEmpty else { return }
        
        isRunning = true
        isPaused = false
        currentLabel = nil
        progressIndex = nil
        currentStepIndex = nil
        totalStepsCount = plan.count
        
        setupAudioSession()
        startBackgroundTask()
        startTicking()
        
        runner = Task { [weak self] in
            guard let self = self else { return }
            
            for (stepIdx, step) in plan.enumerated() {
                if Task.isCancelled { break }
                let stepDuration = max(0, step.item.minutes * 60)
                
                await MainActor.run {
                    self.currentLabel = step.item.label
                    self.progressIndex = step.originalIndex
                    self.currentStepIndex = stepIdx
                    self.totalStepsCount = plan.count
                    self.remainingSeconds = stepDuration
                    self.stepEndDate = Date().addingTimeInterval(TimeInterval(stepDuration))
                    self.scheduleNotifications(fromStepIndex: stepIdx, plan: plan)
                }
                
                self.notifyAndHaptic(title: step.item.label)
                
                while self.isRunning {
                    if Task.isCancelled { break }
                    
                    if self.isPaused {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    
                    await MainActor.run {
                        self.refreshRemainingTime()
                    }
                    
                    if self.remainingSeconds <= 0 {
                        break
                    }
                    
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                
                if Task.isCancelled { break }
                self.notifyExpiration(title: step.item.label)
            }
            
            await MainActor.run {
                self.stopInternal()
            }
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        refreshRemainingTime()
        stepEndDate = nil
        cancelPendingNotifications()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        stepEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        let plan = buildExecutionPlan(items: items)
        if let currentStepIdx = currentStepIndex {
            scheduleNotifications(fromStepIndex: currentStepIdx, plan: plan)
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        stopInternal()
    }

    private func stopInternal() {
        stopTicking()
        cancelPendingNotifications()
        endBackgroundTask()
        deactivateAudioSession()
        
        isRunning = false
        isPaused = false
        progressIndex = nil
        currentStepIndex = nil
        totalStepsCount = nil
        currentLabel = nil
        remainingSeconds = 0
        stepEndDate = nil
    }

    func refreshRemainingTime() {
        guard isRunning, !isPaused, let endDate = stepEndDate else { return }
        let diff = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remainingSeconds != diff {
            remainingSeconds = diff
        }
    }

    // MARK: - Notifications Scheduling for Lock Screen & Background
    private func scheduleNotifications(fromStepIndex: Int, plan: [ExecutionStep]) {
        cancelPendingNotifications()
        
        guard fromStepIndex < plan.count else { return }
        
        var accumulatedTime: TimeInterval = TimeInterval(remainingSeconds)
        
        if accumulatedTime > 0 {
            let currentStep = plan[fromStepIndex]
            let titleText = currentStep.item.label.isEmpty ? "Intervallum" : currentStep.item.label
            let content = UNMutableNotificationContent()
            content.title = titleText
            content.body = "Időzítés lejárt!"
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: accumulatedTime, repeats: false)
            let request = UNNotificationRequest(identifier: "timer_step_\(fromStepIndex)_end", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
        
        for idx in (fromStepIndex + 1)..<plan.count {
            let step = plan[idx]
            let duration = TimeInterval(max(0, step.item.minutes * 60))
            let titleText = step.item.label.isEmpty ? "Intervallum" : step.item.label
            
            let startContent = UNMutableNotificationContent()
            startContent.title = titleText
            startContent.body = "Új szakasz kezdődik"
            startContent.sound = .default
            
            let startTrigger = UNTimeIntervalNotificationTrigger(timeInterval: accumulatedTime, repeats: false)
            let startReq = UNNotificationRequest(identifier: "timer_step_\(idx)_start", content: startContent, trigger: startTrigger)
            UNUserNotificationCenter.current().add(startReq, withCompletionHandler: nil)
            
            accumulatedTime += duration
            
            let endContent = UNMutableNotificationContent()
            endContent.title = titleText
            endContent.body = "Időzítés lejárt!"
            endContent.sound = .default
            
            let endTrigger = UNTimeIntervalNotificationTrigger(timeInterval: accumulatedTime, repeats: false)
            let endReq = UNNotificationRequest(identifier: "timer_step_\(idx)_end", content: endContent, trigger: endTrigger)
            UNUserNotificationCenter.current().add(endReq, withCompletionHandler: nil)
        }
    }

    private func cancelPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Audio Session & Background Task
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
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
                    self.objectWillChange.send()
                }
            }
    }

    private func stopTicking() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Notifications, Sound & Haptics
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyAndHaptic(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Intervallum" : title
        content.body = "Új szakasz kezdődik"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        playSound()
        playHaptic()
    }

    private func notifyExpiration(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Intervallum" : title
        content.body = "Időzítés lejárt!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        playSound()
        playHaptic()
    }

    private func playSound() {
        AudioServicesPlaySystemSound(1005)
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
