import SwiftUI

import Foundation
import Combine
import UserNotifications
import CoreHaptics
import AudioToolbox

struct ExecutionStep {
    let item: TimerIntervalEntity
    let originalIndex: Int
}

final class TimerSequenceViewModel: ObservableObject {
    @Published var items: [TimerIntervalEntity] = []
    @Published var currentLabel: String? = nil
    @Published var isRunning: Bool = false
    @Published var progressIndex: Int? = nil
    @Published var currentStepIndex: Int? = nil
    @Published var totalStepsCount: Int? = nil
    @Published var remainingSeconds: Int = 0
    
    private var runner: Task<Void, Never>? = nil
    private var tickCancellable: AnyCancellable?
    private var hapticEngine: CHHapticEngine?
    
    init() {
        prepareHaptics()
        requestNotificationPermission()
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
        let plan = buildExecutionPlan(items: items)
        guard !isRunning, !plan.isEmpty else { return }
        isRunning = true
        currentLabel = nil
        progressIndex = nil
        currentStepIndex = nil
        totalStepsCount = plan.count
        startTicking()
        
        runner = Task { [weak self] in
            guard let self = self else { return }
            for (stepIdx, step) in plan.enumerated() {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.currentLabel = step.item.label
                    self.progressIndex = step.originalIndex
                    self.currentStepIndex = stepIdx
                    self.totalStepsCount = plan.count
                    self.remainingSeconds = max(0, step.item.minutes * 60)
                }
                self.notifyAndHaptic(title: step.item.label)
                
                while self.remainingSeconds > 0 {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { self.remainingSeconds -= 1 }
                }
                if Task.isCancelled { break }
                self.notifyExpiration(title: step.item.label)
            }
            await MainActor.run {
                self.isRunning = false
                self.progressIndex = nil
                self.currentStepIndex = nil
                self.totalStepsCount = nil
                self.currentLabel = nil
                self.remainingSeconds = 0
                self.stopTicking()
            }
        }
    }
    
    func stop() {
        runner?.cancel()
        runner = nil
        stopTicking()
        isRunning = false
        progressIndex = nil
        currentStepIndex = nil
        totalStepsCount = nil
        currentLabel = nil
        remainingSeconds = 0
    }
    
    // MARK: - Countdown ticks
    private func startTicking() {
        tickCancellable?.cancel()
        tickCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isRunning {
                    self.objectWillChange.send()
                }
            }
    }
    private func stopTicking() {
        tickCancellable?.cancel()
        tickCancellable = nil
    }
    
    // MARK: - Notifications, Sound & Haptics
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    private func notifyAndHaptic(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Új szakasz kezdődik"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        playSound()
        playHaptic()
    }
    
    private func notifyExpiration(title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
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
