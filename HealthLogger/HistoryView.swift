import SwiftUI

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
            .toolbar { EditButton() }
            .refreshable { await reload() }
            .task(id: health.changeCount) { await reload() }
            .alert("Something Went Wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
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
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func delete(_ toDelete: [LoggedEntry]) {
        Task {
            do {
                for entry in toDelete { try await health.delete(entry) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
