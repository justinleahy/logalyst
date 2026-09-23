import SwiftUI
import SwiftData

@main
struct HealthLoggerApp: App {
    @State private var health = HealthStore()
    @State private var goals = NutritionGoals()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(goals)
                .modelContainer(for: Food.self)
        }
    }
}
