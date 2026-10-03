import AppIntents
import SwiftUI
import WidgetKit

// Compiled into both widget extensions. Controls came to Apple Watch in watchOS 26, so the Watch widgets only
// offer them there.

/// A Control Center and Lock Screen button that logs one glass of water in the user's unit.
@available(iOS 18.0, watchOS 26.0, *)
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

@available(iOS 18.0, watchOS 26.0, *)
struct LogMetricControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Log Metric"

    @Parameter(title: "Metric")
    var metric: MetricEntity?
}

/// A Lock Screen and Control Center button that opens the entry screen for a metric the user picks.
@available(iOS 18.0, watchOS 26.0, *)
struct LogMetricControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "LogMetricControl", intent: LogMetricControlIntent.self) { configuration in
            ControlWidgetButton(action: OpenMetricIntent(target: configuration.metric ?? MetricEntity(.water))) {
                if let metric = configuration.metric {
                    Label("Log \(metric.name)", systemImage: metric.systemImage)
                } else {
                    Label("Log Metric", systemImage: "plus.circle")
                }
            }
        }
        .displayName("Log Metric")
        .description("Open Logalyst to log the metric you choose.")
        .promptsForUserConfiguration()
    }
}
