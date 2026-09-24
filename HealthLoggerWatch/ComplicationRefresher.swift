import HealthKit
import WidgetKit

/// Reloads complications when Health gains or loses samples they can show, including ones logged on the iPhone or by
/// other apps, which would otherwise wait for the next scheduled refresh. Background delivery wakes the app for these
/// even when it isn't running, though watchOS limits how often.
final class ComplicationRefresher {
    private let store = HKHealthStore()

    /// Must run on every launch, including background ones, so HealthKit has a query to deliver pending updates to.
    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = Set(MetricEntityQuery.available.flatMap(\.sampleTypes))
        let descriptors = types.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }
        // HealthKit calls this on its own queue; being @Sendable, it isn't tied to the main actor.
        store.execute(HKObserverQuery(queryDescriptors: descriptors) { _, _, completion, error in
            if error == nil {
                WidgetCenter.shared.reloadAllTimelines()
            }
            completion()
        })
        Task { [store] in
            for type in types {
                try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
            }
        }
    }
}
