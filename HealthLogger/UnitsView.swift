import SwiftUI

/// Per-metric unit choices, from Options.
struct UnitsView: View {
    @Environment(HealthStore.self) private var health

    /// Metrics with more than one unit to choose from.
    static var metrics: [Metric] {
        Metric.all.filter { $0.unitOptions.count > 1 }
    }

    var body: some View {
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
        }
        .navigationTitle("Units")
        .navigationBarTitleDisplayMode(.inline)
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

    private var hasOverrides: Bool {
        Self.metrics.contains { health.unitOverride(for: $0) != nil }
    }

    private func resetUnits() {
        for metric in Self.metrics where health.unitOverride(for: metric) != nil {
            health.setUnitOverride(nil, for: metric)
        }
    }
}
