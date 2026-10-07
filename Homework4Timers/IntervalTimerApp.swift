import SwiftUI
import SwiftData

@main
struct IntervalTimerApp: App {
    @AppStorage("appLanguage") private var appLanguage: String = "hu"

    init() {
        let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "hu"
        UserDefaults.standard.set([lang], forKey: "AppleLanguages")
    }

    var body: some Scene {
        WindowGroup {
            TimerContentView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .id(appLanguage)
        }
        .modelContainer(for: [TimerIntervalEntity.self, SavedIntervalList.self])
    }
}
