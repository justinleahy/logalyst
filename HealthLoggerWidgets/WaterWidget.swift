import AppIntents
import SwiftUI
import WidgetKit

/// Today's water against the daily goal, with buttons to log a glass without opening the app.
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Water", provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .widgetURL(DeepLink.nutrition.url)
                .widgetTint()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Track today's water and log a glass with a tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WaterEntry: TimelineEntry {
    var date = Date.now
    let option: UnitOption
    /// The user's water presets in this unit, for the quick-add buttons.
    let presets: [Double]
    let total: Double
    let goal: Double

    var progress: Double { goal > 0 ? total / goal : 0 }
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        let option = Metric.water.unitOptions[0]
        return WaterEntry(option: option, presets: option.presets, total: 1250, goal: 2000)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WaterEntry) -> Void) {
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<WaterEntry>) -> Void) {
        Task { completion(Timeline(entries: [await entry()], policy: .after(.nextWidgetRefresh))) }
    }

    private func entry() async -> WaterEntry {
        let water = Metric.water
        let health = await HealthStore.standalone()
        let option = health.unitOption(for: water) ?? water.unitOptions[0]
        return WaterEntry(option: option, presets: health.presets(for: water, in: option),
                          total: await health.todayTotal(of: water, in: option),
                          goal: NutritionGoals().goal(for: water, in: option) ?? 0)
    }
}

struct WaterWidgetView: View {
    let entry: WaterEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: inline
        }
    }

    private var option: UnitOption { entry.option }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                WaterRing(progress: entry.progress, lineWidth: 6)
                    .frame(width: 44, height: 44)
                amounts(font: .title3)
            }
            Spacer(minLength: 0)
            buttons
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            WaterRing(progress: entry.progress, lineWidth: 10)
                .overlay {
                    Text(entry.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                }
                .padding(4)
            VStack(alignment: .leading, spacing: 8) {
                amounts(font: .title2)
                Spacer(minLength: 0)
                buttons
            }
        }
    }

    private func amounts(font: Font) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(option.formatNumber(entry.total))
                .font(font.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("of \(option.format(entry.goal))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Quick-add buttons for the first few preset amounts (e.g. 250 and 500 mL), as many as fit.
    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(entry.presets.prefix(family == .systemSmall ? 2 : 3), id: \.self) { amount in
                Button(intent: LogWaterIntent(amount: amount, option: option)) {
                    Text("+\(option.formatNumber(amount))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .tint(.cyan)
                .accessibilityLabel("Log \(option.format(amount))")
            }
        }
    }

    private var circular: some View {
        Gauge(value: min(entry.progress, 1)) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text(option.formatNumber(entry.total)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Water", systemImage: "drop.fill")
                .font(.headline)
                .widgetAccentable()
            Text("\(option.formatNumber(entry.total)) of \(option.format(entry.goal))")
                .minimumScaleFactor(0.7)
            ProgressView(value: min(entry.progress, 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label("\(option.formatNumber(entry.total)) of \(option.format(entry.goal))", systemImage: "drop.fill")
    }
}

private struct WaterRing: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.cyan.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(.cyan, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress toward goal")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}
