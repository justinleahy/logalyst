import AppIntents
import SwiftUI
import WidgetKit

/// Saves a glass of water to Health from a widget button or Control Center.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Saves water to Apple Health.")
    /// Health data can't be written while the phone is locked, and a locked phone shouldn't log on your behalf.
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Amount")
    var amount: Double?

    /// The unit label the amount is in (e.g. "mL"). The user's water unit is used when missing.
    @Parameter(title: "Unit")
    var unit: String?

    init() {}

    init(amount: Double, option: UnitOption) {
        self.amount = amount
        unit = option.label
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let water = Metric.water
        let health = await HealthStore.forWidget()
        guard let option = water.unitOptions.first(where: { $0.label == unit }) ?? health.unitOption(for: water) else {
            return .result()
        }
        let value = amount ?? option.presets.first ?? option.defaultValue
        try await health.saveQuantity(water, value: value, option: option, date: .now)
        return .result()
    }
}

/// A Control Center and Lock Screen button that logs one glass of water in the user's unit.
struct LogWaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogWaterControl") {
            ControlWidgetButton(action: LogWaterIntent()) {
                Label("Log Water", systemImage: "drop.fill")
            }
        }
        .displayName("Log Water")
        .description("Log a glass of water to Apple Health.")
    }
}

/// Opens the app to a metric's entry screen.
struct OpenMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Metric"
    static let description = IntentDescription("Opens Health Logger to log a metric.")

    @Parameter(title: "Metric")
    var metric: MetricEntity?

    init() {}

    init(metric: MetricEntity?) {
        self.metric = metric
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let metric = metric.flatMap { Metric.metric(id: $0.id) } ?? .water
        return .result(opensIntent: OpenURLIntent(DeepLink.log(metric).url))
    }
}

struct LogMetricControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Log Metric"

    @Parameter(title: "Metric")
    var metric: MetricEntity?
}

/// A Lock Screen and Control Center button that opens the entry screen for a metric the user picks.
struct LogMetricControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LogMetricControl", intent: LogMetricControlIntent.self) { configuration in
            ControlWidgetButton(action: OpenMetricIntent(metric: configuration.metric)) {
                if let metric = configuration.metric {
                    Label("Log \(metric.name)", systemImage: metric.systemImage)
                } else {
                    Label("Log Metric", systemImage: "plus.circle")
                }
            }
        }
        .displayName("Log Metric")
        .description("Open Health Logger to log the metric you choose.")
        .promptsForUserConfiguration()
    }
}
