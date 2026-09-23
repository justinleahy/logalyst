import AppIntents
import SwiftUI
import SwiftData

@main
struct HealthLoggerApp: App {
    @State private var health: HealthStore
    @State private var goals: NutritionGoals

    init() {
        let health = HealthStore()
        _health = State(initialValue: health)
        _goals = State(initialValue: NutritionGoals(onChange: health.sendGoals))
        // Lets Siri match phrases like "Log my weight" against the metric list.
        HealthLoggerShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(goals)
                .modelContainer(for: Food.self)
        }
    }
}
