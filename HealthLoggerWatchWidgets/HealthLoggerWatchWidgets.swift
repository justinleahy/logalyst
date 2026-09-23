import SwiftUI
import WidgetKit

@main
struct HealthLoggerWatchWidgets: WidgetBundle {
    var body: some Widget {
        MetricWidget()
        if #available(watchOS 26.0, *) {
            LogWaterControl()
            LogMetricControl()
        }
    }
}
