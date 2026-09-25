import SwiftUI

struct OptionsView: View {
    @Environment(HealthStore.self) private var health
    @Environment(LogReminders.self) private var reminders

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        LogRemindersView()
                    } label: {
                        LabeledContent {
                            Text(reminderCount == 0 ? "Off" : "\(reminderCount) On")
                        } label: {
                            Label("Log Reminders", systemImage: "bell")
                        }
                    }
                } footer: {
                    Text("Get reminded to log water, blood pressure, weight or any other metric, on a schedule you choose.")
                }
                Section {
                    NavigationLink {
                        UnitsView()
                    } label: {
                        LabeledContent {
                            Text(customUnitCount == 0 ? "Automatic" : "\(customUnitCount) Custom")
                        } label: {
                            Label("Units", systemImage: "ruler")
                        }
                    }
                } footer: {
                    Text("Choose how values are shown and entered, like kilograms or pounds.")
                }
                Section {
                    NavigationLink {
                        TipJarView()
                    } label: {
                        Label("Tip Jar", systemImage: "heart")
                    }
                } footer: {
                    Text("Enjoying Logalyst? Leave a tip to support its development.")
                }
                Section("About") {
                    LabeledContent("Version", value: bundleValue("CFBundleShortVersionString"))
                    LabeledContent("Build", value: bundleValue("CFBundleVersion"))
                }
            }
            .navigationTitle("Options")
        }
    }

    private var reminderCount: Int {
        reminders.reminders.filter(\.isEnabled).count
    }

    private var customUnitCount: Int {
        UnitsView.metrics.filter { health.unitOverride(for: $0) != nil }.count
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }
}
