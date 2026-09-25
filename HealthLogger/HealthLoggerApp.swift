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
    private let container: ModelContainer
    private let cloudSettings: CloudSettings
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let health = HealthStore()
        let reminders = LogReminders(health: health)
        _health = State(initialValue: health)
        _reminders = State(initialValue: reminders)
        let goals = NutritionGoals {
            health.sendGoals()
            reminders.reschedule()
        }
        _goals = State(initialValue: goals)
        container = Self.makeContainer()
        cloudSettings = CloudSettings(container: container) {
            health.reloadSettings()
            goals.reload()
            reminders.reload()
        }
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
                .modelContainer(container)
        }
        // Reminders are scheduled days ahead, so top them up and refresh today's progress whenever the app opens.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reminders.reschedule()
                cloudSettings.sync()
            }
        }
    }

    static let cloudContainerID = "iCloud.com.justinleahy.HealthLogger"

    /// Saved foods, recipes and settings, synced to the user's private iCloud database with every field
    /// end-to-end encrypted. If iCloud can't be set up, they're kept on this device only.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Food.self, Recipe.self, SyncedSetting.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(
                schema: schema, cloudKitDatabase: .private(cloudContainerID)))
        } catch {
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(
                    schema: schema, cloudKitDatabase: .none))
            } catch {
                fatalError("Couldn't open saved foods: \(error)")
            }
        }
    }
}
