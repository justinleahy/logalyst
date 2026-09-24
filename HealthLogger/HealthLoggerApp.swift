import AppIntents
import SwiftUI
import SwiftData

@main
struct HealthLoggerApp: App {
    @State private var health: HealthStore
    @State private var goals: NutritionGoals
    @State private var reminders: LogReminders
    // Created at launch so it can finish tips that complete while the app is closed.
    @State private var tipJar = TipJar()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let health = HealthStore()
        let reminders = LogReminders(health: health)
        _health = State(initialValue: health)
        _reminders = State(initialValue: reminders)
        _goals = State(initialValue: NutritionGoals {
            health.sendGoals()
            reminders.reschedule()
        })
        // Lets Siri match phrases like "Log my weight" against the metric list.
        HealthLoggerShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(goals)
                .environment(reminders)
                .environment(tipJar)
                .modelContainer(for: Food.self)
        }
        // Reminders are scheduled days ahead, so top them up and refresh today's progress whenever the app opens.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reminders.reschedule() }
        }
    }
}
