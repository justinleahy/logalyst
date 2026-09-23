import SwiftUI
import WidgetKit

/// Today's calories and nutrients against their daily goals.
struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Nutrition", provider: NutritionProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .widgetURL(DeepLink.nutrition.url)
                .widgetTint()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nutrition")
        .description("See today's calories and nutrients against your goals.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NutrientTotal: Identifiable {
    let metric: Metric
    let option: UnitOption
    let total: Double
    let goal: Double

    var id: String { metric.id }

    var progress: Double { goal > 0 ? total / goal : 0 }
}

struct NutritionEntry: TimelineEntry {
    var date = Date.now
    /// Every nutrient with a goal, in Nutrition screen order; smaller widgets show the first few.
    let nutrients: [NutrientTotal]
}

struct NutritionProvider: TimelineProvider {
    /// Nutrients with goals, food first and caffeine last as on the Nutrition screen. Water has its own widget.
    private static let metrics: [Metric] = {
        let withGoals = Metric.metrics(in: .intake).filter { $0.dailyGoal != nil && $0 != .water }
        let isCaffeine = { (metric: Metric) in metric.id == "dietaryCaffeine" }
        return withGoals.filter { !isCaffeine($0) } + withGoals.filter(isCaffeine)
    }()

    func placeholder(in context: Context) -> NutritionEntry {
        NutritionEntry(nutrients: Self.metrics.compactMap { metric in
            guard let option = metric.unitOptions.first, let goal = metric.dailyGoal?.defaultAmount else { return nil }
            return NutrientTotal(metric: metric, option: option, total: goal * 0.6, goal: goal)
        })
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NutritionEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NutritionEntry>) -> Void) {
        Task { completion(Timeline(entries: [await entry()], policy: .after(.nextWidgetRefresh))) }
    }

    private func entry() async -> NutritionEntry {
        let health = await HealthStore.standalone()
        let goals = NutritionGoals()
        var nutrients: [NutrientTotal] = []
        for metric in Self.metrics {
            guard let option = health.unitOption(for: metric), let goal = goals.goal(for: metric, in: option) else {
                continue
            }
            nutrients.append(NutrientTotal(metric: metric, option: option,
                                           total: await health.todayTotal(of: metric, in: option), goal: goal))
        }
        return NutritionEntry(nutrients: nutrients)
    }
}

struct NutritionWidgetView: View {
    let entry: NutritionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: list
        }
    }

    private var list: some View {
        let isLarge = family == .systemLarge
        return VStack(alignment: .leading, spacing: 6) {
            Label("Nutrition Today", systemImage: "fork.knife")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entry.nutrients.prefix(isLarge ? entry.nutrients.count : 4)) { nutrient in
                NutrientBar(nutrient: nutrient)
                    // Spread the rows over the whole widget.
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: Lock Screen

    private var calories: NutrientTotal? {
        entry.nutrients.first { $0.metric.id == "dietaryEnergyConsumed" }
    }

    /// The usual macro shorthand, e.g. "P 30g · C 120g · F 40g".
    private static let macroLetters = ["dietaryProtein": "P", "dietaryCarbohydrates": "C", "dietaryFatTotal": "F"]

    /// Protein, carbs and fat, which follow calories in the list.
    private var macros: [NutrientTotal] {
        Array(entry.nutrients.drop { $0.metric.id == "dietaryEnergyConsumed" }.prefix(3))
    }

    @ViewBuilder
    private var circular: some View {
        if let calories {
            Gauge(value: min(calories.progress, 1)) {
                Image(systemName: calories.metric.systemImage)
            } currentValueLabel: {
                Text(calories.option.formatNumber(calories.total)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let calories {
                Label(caloriesText(calories), systemImage: calories.metric.systemImage)
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                ProgressView(value: min(calories.progress, 1))
            }
            Text(macros.map { "\(Self.macroLetters[$0.metric.id] ?? "") \($0.option.formatNumber($0.total))\($0.option.label)" }
                .joined(separator: " · "))
                .font(.caption)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .accessibilityLabel(macros.map { "\($0.metric.name) \($0.option.format($0.total))" }
                    .joined(separator: ", "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let calories {
            Label(caloriesText(calories), systemImage: calories.metric.systemImage)
        }
    }

    /// "1,420 of 2,000 kcal"
    private func caloriesText(_ calories: NutrientTotal) -> String {
        "\(calories.option.formatNumber(calories.total)) of \(calories.option.format(calories.goal))"
    }
}

private struct NutrientBar: View {
    let nutrient: NutrientTotal

    var body: some View {
        let option = nutrient.option
        let fraction = nutrient.goal > 0 ? nutrient.total / nutrient.goal : 0
        VStack(spacing: 3) {
            HStack {
                Label {
                    Text(nutrient.metric.name)
                } icon: {
                    // A fixed width keeps the names lined up whatever the symbol's shape.
                    Image(systemName: nutrient.metric.systemImage).frame(width: 18)
                }
                Spacer()
                Text("\(option.formatNumber(nutrient.total)) / \(option.format(nutrient.goal))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            ProgressView(value: min(fraction, 1))
                .tint(nutrient.metric.dailyGoal?.tint(forProgress: fraction))
        }
    }
}
