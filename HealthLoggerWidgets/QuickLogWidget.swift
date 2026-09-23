import HealthKit
import SwiftUI
import WidgetKit

/// Shortcuts to the entry screens of your favorite metrics.
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLog", provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
                .widgetTint()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Log")
        .description("Jump straight to logging your favorites.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogEntry: TimelineEntry {
    var date = Date.now
    let metrics: [Metric]
}

struct QuickLogProvider: TimelineProvider {
    /// Shown until the user stars some favorites.
    private static let suggested = ["dietaryWater", "bloodPressure", "bodyMass", HKCategoryTypeIdentifier.headache.rawValue]
        .compactMap { Metric.metric(id: $0) }

    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(metrics: Self.suggested)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (QuickLogEntry) -> Void) {
        Task { completion(await entry()) }
    }

    /// Favorites only change in the app, which reloads widgets when they do.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<QuickLogEntry>) -> Void) {
        Task { completion(Timeline(entries: [await entry()], policy: .never)) }
    }

    private func entry() async -> QuickLogEntry {
        let favorites = HealthStore(syncs: false).favorites
        return QuickLogEntry(metrics: favorites.isEmpty ? Self.suggested : favorites)
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let columns = family == .systemMedium ? 4 : 2
        VStack(spacing: 6) {
            ForEach(Array(rows(columns: columns).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { tile(for: $0) }
                    // Keep a short last row's tiles the same width as the others.
                    ForEach(row.count..<columns, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    /// Up to two rows of metrics.
    private func rows(columns: Int) -> [[Metric]] {
        let shown = Array(entry.metrics.prefix(columns * 2))
        return stride(from: 0, to: shown.count, by: columns).map { Array(shown[$0..<min($0 + columns, shown.count)]) }
    }

    private func tile(for metric: Metric) -> some View {
        Link(destination: DeepLink.log(metric).url) {
            VStack(spacing: 4) {
                Image(systemName: metric.systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(metric.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.fill.secondary, in: ContainerRelativeShape())
        }
        .accessibilityLabel("Log \(metric.name)")
    }
}
