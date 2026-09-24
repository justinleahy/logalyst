import AppIntents
import SwiftUI

@main
struct HealthLoggerWatchApp: App {
    @State private var health = HealthStore()
    private let complications = ComplicationRefresher()

    init() {
        // Lets Siri match phrases like "Log my weight" against the metric list.
        HealthLoggerShortcuts.updateAppShortcutParameters()
        complications.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchLogView()
                .environment(health)
                .task { try? await health.requestAuthorization() }
        }
    }
}
