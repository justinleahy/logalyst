import AppIntents

/// Any metric, for widget and control settings.
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

/// A metric logged as a single number, like weight, blood glucose or caffeine, for Siri and Shortcuts.
/// Water is left out because it has its own intents, so "Log water" can't mean two things to Siri.
struct QuantityMetricEntity: AppEntity {
    let id: String
    let name: String
    let systemImage: String
    let keywords: [String]

    init(_ metric: Metric) {
        id = metric.id
        name = metric.name
        systemImage = metric.systemImage
        keywords = metric.keywords
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let defaultQuery = QuantityMetricEntityQuery()

    /// Keywords double as synonyms, so "log my blood sugar" finds Blood Glucose.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: systemImage),
                              synonyms: keywords.map { "\($0)" })
    }
}

struct QuantityMetricEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [QuantityMetricEntity] {
        Self.available.filter { identifiers.contains($0.id) }.map { QuantityMetricEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [QuantityMetricEntity] {
        Self.available.map { QuantityMetricEntity($0) }
    }

    @MainActor
    static var available: [Metric] {
        MetricEntityQuery.available.filter { !$0.unitOptions.isEmpty && $0 != .water }
    }
}
