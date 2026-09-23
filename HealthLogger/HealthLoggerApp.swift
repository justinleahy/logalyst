import SwiftUI

@main
struct HealthLoggerApp: App {
    @State private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
        }
    }
}
