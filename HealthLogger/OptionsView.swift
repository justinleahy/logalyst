import SwiftUI

struct OptionsView: View {
    @Environment(HealthStore.self) private var health

    var body: some View {
        NavigationStack {
            Form {
                ForEach(MetricCategory.allCases) { category in
                    let metrics = Metric.metrics(in: category).filter { $0.unitOptions.count > 1 }
                    if !metrics.isEmpty {
                        Section {
                            ForEach(metrics) { unitPicker(for: $0) }
                        } header: {
                            Label(category.title, systemImage: category.systemImage)
                        }
                    }
                }
                Section {
                    Button("Use Automatic Units", action: resetUnits)
                        .disabled(!hasOverrides)
                } footer: {
                    Text("Auto follows your unit preferences in the Health app, or your region if none are set. "
                         + "Changing a unit here only affects how values are shown and entered on this iPhone.")
                }
                Section("About") {
                    LabeledContent("Version", value: bundleValue("CFBundleShortVersionString"))
                    LabeledContent("Build", value: bundleValue("CFBundleVersion"))
                }
            }
            .navigationTitle("Options")
        }
    }

    private func unitPicker(for metric: Metric) -> some View {
        let selection = Binding<UnitOption?> {
            health.unitOverride(for: metric)
        } set: {
            health.setUnitOverride($0, for: metric)
        }
        return Picker(selection: selection) {
            Text(automaticTitle(for: metric)).tag(UnitOption?.none)
            ForEach(metric.unitOptions, id: \.self) { Text($0.label).tag(Optional($0)) }
        } label: {
            Label(metric.name, systemImage: metric.systemImage)
        }
    }

    private func automaticTitle(for metric: Metric) -> String {
        guard let option = health.automaticUnitOption(for: metric) else { return "Auto" }
        return "Auto (\(option.label))"
    }

    private func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    private var unitMetrics: [Metric] {
        Metric.all.filter { $0.unitOptions.count > 1 }
    }

    private var hasOverrides: Bool {
        unitMetrics.contains { health.unitOverride(for: $0) != nil }
    }

    private func resetUnits() {
        for metric in unitMetrics where health.unitOverride(for: metric) != nil {
            health.setUnitOverride(nil, for: metric)
        }
    }
}
