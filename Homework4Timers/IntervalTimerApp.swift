import SwiftUI
import SwiftData

@main
struct IntervalTimerApp: App {
    var body: some Scene {
        WindowGroup {
            TimerContentView()
        }
        .modelContainer(for: [TimerIntervalEntity.self, SavedIntervalList.self])
    }
}
