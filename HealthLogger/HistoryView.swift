import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(HealthStore.self) private var health
    @State private var entries: [LoggedEntry] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByDay, id: \.day) { group in
                    Section(group.day.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.entries) { entry in
                            // Foods aren't editable here; they're logged by the serving from My Foods.
                            if entry.metric != nil {
                                NavigationLink(value: entry) { row(for: entry) }
                            } else {
                                row(for: entry).logAgainActions(entry, in: health) { self.error = $0 }
                            }
                        }
                        .onDelete { offsets in delete(offsets.map { group.entries[$0] }) }
                    }
                }
            }
            .overlay {
                if loaded && entries.isEmpty {
                    ContentUnavailableView("No Entries Yet", systemImage: "list.bullet.clipboard",
                                           description: Text("Things you log here or on Apple Watch show up in this list."))
                }
            }
            .navigationTitle("History")
            // Tied to the value rather than the row, so the list reloading after the edit saves doesn't pop it early.
            .navigationDestination(for: LoggedEntry.self) { entry in
                if let metric = entry.metric { EntryView(metric: metric, editing: entry) }
            }
            .toolbar { EditButton() }
            .refreshable { await reload() }
            .task(id: health.changeCount) { await reload() }
            // Loads that ran while the phone was locked (such as when iOS prewarms the app) failed, so retry on unlock.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                Task { await reload() }
            }
            .alert("Something Went Wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func row(for entry: LoggedEntry) -> some View {
        HStack {
            Label(entry.title, systemImage: entry.systemImage)
            Spacer()
            VStack(alignment: .trailing) {
                Text(entry.valueText).monospacedDigit()
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var groupedByDay: [(day: Date, entries: [LoggedEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    private func reload() async {
        do {
            entries = try await health.recentEntries()
        } catch where error.isHealthDataLocked {
            // Keep what's showing; this reloads once the phone is unlocked.
        } catch {
            self.error = error.healthMessage
        }
        loaded = true
    }

    private func delete(_ toDelete: [LoggedEntry]) {
        Task {
            do {
                for entry in toDelete { try await health.delete(entry) }
            } catch {
                self.error = error.healthMessage
            }
        }
    }
}
