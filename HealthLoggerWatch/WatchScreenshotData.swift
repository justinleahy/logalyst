#if DEBUG
import Foundation

/// Launched with `-SeedScreenshotData YES` in a fresh Watch simulator, stars a few favorites and saves recent
/// readings so the entry screens prefill, for App Store screenshots. The Watch simulator has no paired iPhone to
/// sync favorites from, and its own Health store. Runs once per install.
enum WatchScreenshotData {
    private static let seededKey = "didSeedScreenshotData"

    @MainActor
    static func seed(health: HealthStore) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "SeedScreenshotData"), !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)

        for id in ["dietaryWater", "bloodPressure", "bodyMass", "bloodGlucose", "dietaryCaffeine"] {
            if let metric = Metric.metric(id: id), !health.isFavorite(metric) { health.toggleFavorite(metric) }
        }
        let earlier = Date.now.addingTimeInterval(-3 * 3600)
        func quantity(_ id: String, _ value: Double, _ label: String) async {
            guard let metric = Metric.metric(id: id), let option = metric.unitOptions.first(where: { $0.label == label })
            else { return }
            try? await health.saveQuantity(metric, value: value, option: option, date: earlier)
        }
        await quantity("bodyMass", 175.2, "lb")
        await quantity("bloodGlucose", 92, "mg/dL")
        try? await health.saveBloodPressure(systolic: 117, diastolic: 76, date: earlier)
        if let flOz = Metric.water.unitOptions.first(where: { $0.label == "fl oz" }) {
            health.setUnitOverride(flOz, for: Metric.water)
        }
    }
}
#endif
