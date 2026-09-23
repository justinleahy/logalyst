import SwiftUI
import WidgetKit

@main
struct HealthLoggerWidgets: WidgetBundle {
    var body: some Widget {
        WaterWidget()
        NutritionWidget()
        QuickLogWidget()
        MetricWidget()
        LogWaterControl()
        LogMetricControl()
    }
}
