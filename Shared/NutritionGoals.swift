import Observation
import SwiftUI
import WidgetKit

/// The user's daily intake goals, persisted on this device.
@Observable
final class NutritionGoals {
    private static let defaultsKey = "nutritionGoals"

    /// Overrides of each metric's default goal, keyed by metric ID, in the metric's first unit option
    /// so a goal keeps its meaning when the display unit changes (e.g. mL vs fl oz).
    private var amounts = AppGroup.defaults.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]

    /// The metric's daily goal in the given display unit, or nil if it has no goal.
    func goal(for metric: Metric, in option: UnitOption) -> Double? {
        guard let dailyGoal = metric.dailyGoal, let canonical = metric.unitOptions.first else { return nil }
        return option.displayValue(amounts[metric.id] ?? dailyGoal.defaultAmount, from: canonical)
    }

    func setGoal(_ value: Double, for metric: Metric, in option: UnitOption) {
        guard value > 0, let canonical = metric.unitOptions.first else { return }
        amounts[metric.id] = canonical.displayValue(value, from: option)
        save()
    }

    func resetToDefaults() {
        amounts = [:]
        save()
    }

    private func save() {
        AppGroup.defaults.set(amounts, forKey: Self.defaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension DailyGoal {
    /// Progress color for a fraction of the goal: green once a target is met; orange near a limit, red over it.
    /// Nil means the usual tint.
    func tint(forProgress fraction: Double) -> Color? {
        guard isLimit else { return fraction >= 1 ? .green : nil }
        return fraction > 1 ? .red : fraction >= 0.8 ? .orange : nil
    }
}
