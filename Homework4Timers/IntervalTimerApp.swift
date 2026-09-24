import SwiftUI
import SwiftData

@main
struct IntervalTimerApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "hu"

    var body: some Scene {
        WindowGroup {
            TimerContentView()
                .environment(\.locale, Locale(identifier: appLanguage))
        }
        .modelContainer(for: [TimerIntervalEntity.self, SavedIntervalList.self])
    }
}
