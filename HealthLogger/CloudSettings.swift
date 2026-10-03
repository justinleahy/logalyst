import Foundation
import SwiftData
import CoreData

/// One setting as stored in iCloud, end-to-end encrypted like saved foods.
@Model
final class SyncedSetting {
    @Attribute(.allowsCloudEncryption) var key = ""
    /// The value as a property list, or empty when the setting was cleared.
    @Attribute(.allowsCloudEncryption) var value = Data()
    @Attribute(.allowsCloudEncryption) var updated = Date.distantPast

    init(key: String) {
        self.key = key
    }
}

/// Keeps settings (goals, units, favorites, presets, reminders and Suggest Goals answers) in step with iCloud,
/// so they follow the user to their other iPhones. The stores that use them keep reading this device's defaults:
/// edits there are uploaded, and newer values from iCloud are written back and reloaded through `onRemoteChange`.
/// The Watch still gets its settings from the iPhone.
@MainActor
final class CloudSettings {
    private struct Setting {
        let key: String
        let defaults: UserDefaults
    }

    private static let settings: [Setting] = {
        let group = ["unitOverrides", "favoriteMetrics", "favoriteMetricsUpdated", "customPresets", "nutritionGoals"]
        let standard = ["logReminders", "suggestGoalsActivity", "suggestGoalsAim", "suggestGoalsUsesRestingEnergy"]
        return group.map { Setting(key: $0, defaults: AppGroup.defaults) }
            + standard.map { Setting(key: $0, defaults: .standard) }
    }()

    /// When each setting here last matched iCloud (the record's `updated`), kept on this device only.
    private static let syncedKey = "cloudSettingsSynced"
    /// When each setting was changed here since the last sync. Kept until the sync, even across launches, so a
    /// record from iCloud that's older than the edit doesn't replace it.
    private static let editedKey = "cloudSettingsEdited"

    private let context: ModelContext
    private let onRemoteChange: () -> Void
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// Each setting's value when last checked, to tell which ones a change notification was for.
    private var lastSeen: [String: Any] = [:]

    init(container: ModelContainer, onRemoteChange: @escaping () -> Void) {
        context = container.mainContext
        self.onRemoteChange = onRemoteChange
        for setting in Self.settings {
            lastSeen[setting.key] = setting.defaults.object(forKey: setting.key)
        }
        let center = NotificationCenter.default
        // Local edits, and records arriving from the user's other devices.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.noteLocalEdits()
                self?.scheduleSync()
            }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        })
        sync()
    }

    /// Notes when each setting changed here. Runs as soon as defaults change rather than after the sync's wait,
    /// since a record that arrives from iCloud during the wait can be older than the edit.
    private func noteLocalEdits() {
        let wasEdited = UserDefaults.standard.dictionary(forKey: Self.editedKey) as? [String: Date] ?? [:]
        var edited = wasEdited
        for setting in Self.settings {
            let value = setting.defaults.object(forKey: setting.key)
            if !Self.equal(value, lastSeen[setting.key]) {
                lastSeen[setting.key] = value
                edited[setting.key] = .now
            }
        }
        if edited != wasEdited { UserDefaults.standard.set(edited, forKey: Self.editedKey) }
    }

    /// Waits for a burst of changes to settle, since one edit can touch several keys.
    private func scheduleSync() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    /// For each setting, takes iCloud's value if it changed since this device last saw it and after any edit
    /// here, otherwise uploads this device's value if it differs. So the most recent edit wins, and a new device
    /// takes what's in iCloud.
    func sync() {
        noteLocalEdits()
        guard let records = try? context.fetch(FetchDescriptor<SyncedSetting>()) else { return }
        let newest = removingDuplicates(records)
        let wasSynced = UserDefaults.standard.dictionary(forKey: Self.syncedKey) as? [String: Date] ?? [:]
        let edited = UserDefaults.standard.dictionary(forKey: Self.editedKey) as? [String: Date] ?? [:]
        var synced = wasSynced
        var changedHere = false

        for setting in Self.settings {
            let local = setting.defaults.object(forKey: setting.key)
            let record = newest[setting.key]
            let remote = record.flatMap { Self.decode($0.value) }
            if let record, record.updated > synced[setting.key] ?? .distantPast,
               record.updated > edited[setting.key] ?? .distantPast {
                if !Self.equal(local, remote) {
                    // Seen before it's set, so the change notification isn't taken for an edit here.
                    lastSeen[setting.key] = remote
                    setting.defaults.set(remote, forKey: setting.key)
                    changedHere = true
                }
                synced[setting.key] = record.updated
            } else if !Self.equal(local, remote) {
                let record = record ?? insertRecord(key: setting.key)
                record.value = Self.encode(local)
                record.updated = .now
                synced[setting.key] = record.updated
            }
        }

        // Writes only what changed: saving and setting defaults post the notifications that schedule a sync,
        // so an unconditional write would sync again every second forever.
        if context.hasChanges { try? context.save() }
        if synced != wasSynced { UserDefaults.standard.set(synced, forKey: Self.syncedKey) }
        if !edited.isEmpty { UserDefaults.standard.removeObject(forKey: Self.editedKey) }
        if changedHere { onRemoteChange() }
    }

    /// Two devices can each create a record for the same setting before they sync. Keeps the newest.
    private func removingDuplicates(_ records: [SyncedSetting]) -> [String: SyncedSetting] {
        var newest: [String: SyncedSetting] = [:]
        for record in records.sorted(by: { $0.updated > $1.updated }) {
            if newest[record.key] == nil {
                newest[record.key] = record
            } else {
                context.delete(record)
            }
        }
        return newest
    }

    private func insertRecord(key: String) -> SyncedSetting {
        let record = SyncedSetting(key: key)
        context.insert(record)
        return record
    }

    // MARK: Values

    private static func encode(_ value: Any?) -> Data {
        guard let value else { return Data() }
        return (try? PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0))
            ?? Data()
    }

    private static func decode(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["value"]
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as AnyObject).isEqual(b)
        default: false
        }
    }
}
