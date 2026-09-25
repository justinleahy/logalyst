import AppIntents
import SwiftUI
import SwiftData
#if DEBUG
import CoreData
import OSLog
#endif

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
        #if DEBUG
        Self.initializeCloudKitSchemaIfAsked()
        #endif
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
    private static let models: [any PersistentModel.Type] = [Food.self, Recipe.self, SyncedSetting.self]

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
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

    #if DEBUG
    /// Launched with `-InitializeCloudKitSchema YES` while signed in to iCloud, creates every record type and field
    /// in the CloudKit development environment, ready to deploy to production. Syncing alone only creates fields
    /// that have had a value, so a field that's still empty (like a food's barcode) would be missing. Uses a
    /// throwaway store, so the real one isn't touched.
    private static func initializeCloudKitSchemaIfAsked() {
        guard UserDefaults.standard.bool(forKey: "InitializeCloudKitSchema") else { return }
        let log = Logger(subsystem: "com.justinleahy.HealthLogger", category: "CloudKitSchema")
        let url = URL.temporaryDirectory.appending(path: "CloudKitSchema.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        description.shouldAddStoreAsynchronously = false
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: models) else {
            log.error("CloudKit schema: couldn't build the model")
            return
        }
        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { log.error("CloudKit schema: couldn't load the store: \(error, privacy: .public)") }
        }
        do {
            try container.initializeCloudKitSchema()
            log.notice("CloudKit schema: initialized")
        } catch {
            log.error("CloudKit schema: failed: \(error, privacy: .public)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: url)
    }
    #endif
}
