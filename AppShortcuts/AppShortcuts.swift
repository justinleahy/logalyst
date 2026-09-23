import AppIntents

/// Siri phrases, plus the tiles Shortcuts and Spotlight show for the app. Every phrase must name the app.
/// Compiled into the iPhone and Watch apps, but not the widget extensions.
struct HealthLoggerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)",
            "Log a glass of water in \(.applicationName)",
            "Add water in \(.applicationName)",
            "Log water with \(.applicationName)",
        ], shortTitle: "Log Water", systemImageName: "drop.fill")

        AppShortcut(intent: LogWaterServingIntent(), phrases: [
            "Log \(\.$serving) of water in \(.applicationName)",
            "Add \(\.$serving) of water in \(.applicationName)",
            "Log \(\.$serving) of water with \(.applicationName)",
        ], shortTitle: "Log Water Serving", systemImageName: "waterbottle")

        AppShortcut(intent: LogMetricIntent(), phrases: [
            "Log \(\.$metric) in \(.applicationName)",
            "Log my \(\.$metric) in \(.applicationName)",
            "Record \(\.$metric) in \(.applicationName)",
            "Log \(\.$metric) with \(.applicationName)",
            "Log a metric in \(.applicationName)",
        ], shortTitle: "Log Metric", systemImageName: "plus.circle")
    }
}
