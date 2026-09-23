import SwiftUI

/// Sheet for editing daily goals.
struct GoalsView: View {
    @Environment(HealthStore.self) private var health
    @Environment(NutritionGoals.self) private var goals
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(metrics) { metric in
                        if let option = health.unitOption(for: metric) {
                            goalField(metric, option: option)
                        }
                    }
                } footer: {
                    Text("Defaults are general guidelines for a 2,000-calorie diet. Adjust them to suit you.")
                }
                Section {
                    Button("Reset to Defaults", role: .destructive) { goals.resetToDefaults() }
                }
            }
            .navigationTitle("Daily Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Same order as the Nutrition screen.
    private var metrics: [Metric] {
        ([NutritionView.water] + NutritionView.food + NutritionView.drinks).filter { $0.dailyGoal != nil }
    }

    private func goalField(_ metric: Metric, option: UnitOption) -> some View {
        let binding = Binding<Double?> {
            goals.goal(for: metric, in: option)
        } set: { value in
            if let value { goals.setGoal(value, for: metric, in: option) }
        }
        return HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(metric.name)
                    if metric.dailyGoal?.isLimit == true {
                        Text("Limit").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: metric.systemImage)
            }
            Spacer()
            TextField(metric.name, value: binding,
                      format: .number.precision(.fractionLength(0...option.fractionDigits)))
                .keyboardType(option.fractionDigits > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
            Text(option.label).foregroundStyle(.secondary)
        }
    }
}
