import SwiftUI

@main
struct HealthLoggerWatchApp: App {
    @State private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            WatchLogView()
                .environment(health)
                .task { try? await health.requestAuthorization() }
        }
    }
}
