import AppIntents
import HealthKit
import SwiftUI
import WidgetKit

/// Shows one metric's latest reading (or today's total for intake) and opens its log screen when tapped.
struct MetricWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Metric", intent: MetricWidgetIntent.self, provider: MetricProvider()) { entry in
            MetricWidgetView(entry: entry)
                .widgetURL(DeepLink.log(entry.metric).url)
                .widgetTint()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Metric")
        .description("See your latest reading or today's total, and tap to log another.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

// MARK: - Configuration

struct MetricWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Metric"
    static let description = IntentDescription("Choose what the widget shows.")

    @Parameter(title: "Metric")
    var metric: MetricEntity?

    init() {}

    init(metric: Metric) {
        self.metric = MetricEntity(metric)
    }
}

struct MetricEntity: AppEntity {
    let id: String
    let name: String
    let systemImage: String

    init(_ metric: Metric) {
        id = metric.id
        name = metric.name
        systemImage = metric.systemImage
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let defaultQuery = MetricEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: systemImage))
    }
}

struct MetricEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MetricEntity] {
        identifiers.compactMap { Metric.metric(id: $0) }.map { MetricEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MetricEntity] {
        Self.available.map { MetricEntity($0) }
    }

    @MainActor
    func defaultResult() async -> MetricEntity? {
        MetricEntity(.water)
    }

    @MainActor
    static var available: [Metric] {
        #if os(watchOS)
        Metric.all.filter(\.onWatch)
        #else
        Metric.all
        #endif
    }
}

// MARK: - Timeline

struct MetricEntry: TimelineEntry {
    var date = Date.now
    let metric: Metric
    /// Nil when nothing has been logged.
    var reading: MetricReading?
    /// Progress toward the metric's daily goal, if it has one.
    var progress: Double?
}

struct MetricReading: Codable, Hashable {
    /// The number alone ("1,250", "120/80"), or a word for symptoms ("Mild").
    var value: String
    /// The value with its unit ("1,250 mL").
    var text: String
    /// When the reading was taken, or nil for today's total.
    var date: Date?
}

struct MetricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MetricEntry {
        MetricEntry(metric: .water, reading: MetricReading(value: "1,250", text: "1,250 mL"), progress: 0.6)
    }

    func snapshot(for configuration: MetricWidgetIntent, in context: Context) async -> MetricEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: MetricWidgetIntent, in context: Context) async -> Timeline<MetricEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(.nextWidgetRefresh))
    }

    /// On watchOS the complication picker lists these instead of offering an edit screen.
    func recommendations() -> [AppIntentRecommendation<MetricWidgetIntent>] {
        #if os(watchOS)
        MetricEntityQuery.available.map {
            AppIntentRecommendation(intent: MetricWidgetIntent(metric: $0), description: $0.name)
        }
        #else
        []
        #endif
    }

    private func entry(for configuration: MetricWidgetIntent) async -> MetricEntry {
        let metric = configuration.metric.flatMap { Metric.metric(id: $0.id) } ?? .water
        let health = await HealthStore.forWidget()
        if metric.category == .intake, let option = health.unitOption(for: metric) {
            return await totalEntry(for: metric, option: option, health: health)
        }
        return await latestEntry(for: metric, health: health)
    }

    private func totalEntry(for metric: Metric, option: UnitOption, health: HealthStore) async -> MetricEntry {
        let total = await health.todayTotal(of: metric, in: option)
        var entry = MetricEntry(metric: metric,
                                reading: MetricReading(value: option.formatNumber(total), text: option.format(total)))
        #if os(iOS)
        // Goals are set on iPhone, so the watch shows totals without progress.
        if let goal = NutritionGoals().goal(for: metric, in: option), goal > 0 {
            entry.progress = total / goal
        }
        #endif
        return entry
    }

    private func latestEntry(for metric: Metric, health: HealthStore) async -> MetricEntry {
        let key = "latest.\(metric.id)"
        do {
            let reading = try await health.latestSample(of: metric).flatMap { reading(from: $0, of: metric, health: health) }
            WidgetCache.save(reading, key: key)
            return MetricEntry(metric: metric, reading: reading)
        } catch {
            return MetricEntry(metric: metric, reading: WidgetCache.load(MetricReading.self, key: key))
        }
    }

    private func reading(from sample: HKSample, of metric: Metric, health: HealthStore) -> MetricReading? {
        switch sample {
        case let quantity as HKQuantitySample:
            guard let option = health.unitOption(for: metric) else { return nil }
            let value = option.displayValue(from: quantity.quantity)
            return MetricReading(value: option.formatNumber(value), text: option.format(value), date: sample.startDate)
        case let correlation as HKCorrelation:
            guard let values = health.bloodPressureValues(correlation) else { return nil }
            let value = "\(Int(values.systolic))/\(Int(values.diastolic))"
            return MetricReading(value: value, text: "\(value) mmHg", date: sample.startDate)
        case let category as HKCategorySample:
            let title = Severity(healthKitValue: category.value)?.title ?? "Logged"
            return MetricReading(value: title, text: title, date: sample.startDate)
        default:
            return nil
        }
    }
}

// MARK: - Views

struct MetricWidgetView: View {
    let entry: MetricEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        #if os(watchOS)
        case .accessoryCorner: corner
        #endif
        default: small
        }
    }

    private var metric: Metric { entry.metric }
    private var value: String { entry.reading?.value ?? "–" }

    @ViewBuilder
    private var circular: some View {
        if let progress = entry.progress {
            Gauge(value: min(progress, 1)) {
                Image(systemName: metric.systemImage)
            } currentValueLabel: {
                Text(value).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: metric.systemImage).font(.caption)
                    Text(value)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                .padding(4)
            }
        }
    }

    #if os(watchOS)
    private var corner: some View {
        Image(systemName: metric.systemImage)
            .font(.title2)
            .widgetLabel {
                if let progress = entry.progress {
                    Gauge(value: min(progress, 1)) { Text(value) }
                } else {
                    Text(entry.reading?.text ?? metric.name)
                }
            }
    }
    #endif

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(metric.name, systemImage: metric.systemImage)
                .font(.headline)
                .widgetAccentable()
            Text(entry.reading?.text ?? "Nothing logged")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
            if let progress = entry.progress {
                ProgressView(value: min(progress, 1))
            } else {
                ReadingTime(reading: entry.reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label(entry.reading.map { "\(metric.name) \($0.text)" } ?? metric.name, systemImage: metric.systemImage)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: metric.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            Spacer()
            Text(metric.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.reading?.text ?? "Nothing logged")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let progress = entry.progress {
                ProgressView(value: min(progress, 1))
            } else {
                ReadingTime(reading: entry.reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// "Today", a time for readings taken today, or a date for older ones.
private struct ReadingTime: View {
    let reading: MetricReading?

    var body: some View {
        if let reading {
            if let date = reading.date {
                if Calendar.current.isDateInToday(date) {
                    Text(date, style: .time)
                } else {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                }
            } else {
                Text("Today")
            }
        }
    }
}
