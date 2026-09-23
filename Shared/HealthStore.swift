import HealthKit
import Observation

/// A sample this app wrote, shaped for display in the history list.
struct LoggedEntry: Identifiable {
    let sample: HKSample
    let metric: Metric
    let valueText: String

    var id: UUID { sample.uuid }
    var date: Date { sample.startDate }
}

enum BloodGlucoseMealTime: Int, CaseIterable, Identifiable {
    case unspecified, beforeMeal, afterMeal

    var id: Self { self }

    var title: String {
        switch self {
        case .unspecified: "Not Set"
        case .beforeMeal: "Before Meal"
        case .afterMeal: "After Meal"
        }
    }

    var healthKitValue: HKBloodGlucoseMealTime? {
        switch self {
        case .unspecified: nil
        case .beforeMeal: .preprandial
        case .afterMeal: .postprandial
        }
    }
}

@Observable
final class HealthStore {
    /// Tags every sample this app (phone or watch) writes, so history can find entries from both.
    static let entryMetadataKey = "HealthLoggerEntry"

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private(set) var preferredUnits: [HKQuantityType: HKUnit] = [:]
    /// Incremented after every save or delete so views can refresh.
    private(set) var changeCount = 0

    private let store = HKHealthStore()

    private var writeTypes: Set<HKSampleType> {
        Set(Metric.all.flatMap(\.sampleTypes))
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        // Read access to the same types lets us show history and prefill the last value.
        try await store.requestAuthorization(toShare: writeTypes, read: writeTypes)
        await loadPreferredUnits()
    }

    private func loadPreferredUnits() async {
        let types = Set(Metric.all.flatMap(\.sampleTypes).compactMap { $0 as? HKQuantityType })
        if let units = try? await store.preferredUnits(for: types) {
            preferredUnits = units
        }
    }

    /// Picks the unit that matches the user's Health app preference, falling back to their region.
    func unitOption(for metric: Metric) -> UnitOption? {
        let options = metric.unitOptions
        guard case .quantity(let id, _) = metric.kind else { return nil }
        if let preferred = preferredUnits[HKQuantityType(id)],
           let match = options.first(where: { $0.unit == preferred }) {
            return match
        }
        let isUS = Locale.current.measurementSystem == .us
        return options.first { $0.system == .both || $0.system == (isUS ? .us : .metric) } ?? options.first
    }

    // MARK: Saving

    func saveQuantity(_ metric: Metric, value: Double, option: UnitOption, date: Date,
                      mealTime: BloodGlucoseMealTime = .unspecified) async throws {
        guard case .quantity(let id, _) = metric.kind else { return }
        var metadata = baseMetadata
        if let mealTime = mealTime.healthKitValue {
            metadata[HKMetadataKeyBloodGlucoseMealTime] = mealTime.rawValue
        }
        let sample = HKQuantitySample(type: HKQuantityType(id), quantity: option.quantity(fromDisplay: value),
                                      start: date, end: date, metadata: metadata)
        try await save([sample])
    }

    func saveBloodPressure(systolic: Double, diastolic: Double, date: Date) async throws {
        let metadata = baseMetadata
        let systolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureSystolic),
            quantity: HKQuantity(unit: BloodPressure.unit, doubleValue: systolic),
            start: date, end: date, metadata: metadata)
        let diastolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureDiastolic),
            quantity: HKQuantity(unit: BloodPressure.unit, doubleValue: diastolic),
            start: date, end: date, metadata: metadata)
        let correlation = HKCorrelation(type: HKCorrelationType(.bloodPressure), start: date, end: date,
                                        objects: [systolicSample, diastolicSample], metadata: metadata)
        try await save([correlation])
    }

    func saveSymptom(_ metric: Metric, severity: Severity, start: Date, end: Date) async throws {
        guard case .symptom(let id) = metric.kind else { return }
        let sample = HKCategorySample(type: HKCategoryType(id), value: severity.healthKitValue.rawValue,
                                      start: start, end: max(start, end), metadata: baseMetadata)
        try await save([sample])
    }

    private var baseMetadata: [String: Any] {
        [HKMetadataKeyWasUserEntered: true, Self.entryMetadataKey: true]
    }

    private func save(_ objects: [HKObject]) async throws {
        try await store.save(objects)
        changeCount += 1
    }

    // MARK: Reading

    /// Most recent value of a quantity metric (from any source), used to prefill entry screens.
    func latestValue(for metric: Metric, option: UnitOption) async -> Double? {
        guard case .quantity(let id, _) = metric.kind else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1)
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return option.displayValue(from: sample.quantity)
    }

    func latestBloodPressure() async -> (systolic: Double, diastolic: Double)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.bloodPressure))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1)
        guard let correlation = try? await descriptor.result(for: store).first else { return nil }
        return bloodPressureValues(correlation)
    }

    /// Entries logged by this app on iPhone or Apple Watch, newest first.
    func recentEntries(limit: Int = 200) async throws -> [LoggedEntry] {
        let ours = HKQuery.predicateForObjects(withMetadataKey: Self.entryMetadataKey)
        let types = Set(Metric.all.map(\.historyType))
        let descriptor = HKSampleQueryDescriptor(
            predicates: types.map { HKSamplePredicate.sample(type: $0, predicate: ours) },
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit)
        return try await descriptor.result(for: store).compactMap(entry(for:))
    }

    private func entry(for sample: HKSample) -> LoggedEntry? {
        guard let metric = Metric.metric(for: sample.sampleType) else { return nil }
        let text: String
        switch sample {
        case let quantity as HKQuantitySample:
            guard let option = unitOption(for: metric) else { return nil }
            text = option.format(option.displayValue(from: quantity.quantity))
        case let correlation as HKCorrelation:
            guard let values = bloodPressureValues(correlation) else { return nil }
            text = "\(Int(values.systolic))/\(Int(values.diastolic)) mmHg"
        case let category as HKCategorySample:
            text = Severity(healthKitValue: category.value)?.title ?? "Logged"
        default:
            return nil
        }
        return LoggedEntry(sample: sample, metric: metric, valueText: text)
    }

    private func bloodPressureValues(_ correlation: HKCorrelation) -> (systolic: Double, diastolic: Double)? {
        let value = { (id: HKQuantityTypeIdentifier) in
            (correlation.objects(for: HKQuantityType(id)).first as? HKQuantitySample)?
                .quantity.doubleValue(for: BloodPressure.unit)
        }
        guard let systolic = value(.bloodPressureSystolic), let diastolic = value(.bloodPressureDiastolic) else { return nil }
        return (systolic, diastolic)
    }

    // MARK: Deleting

    func delete(_ entry: LoggedEntry) async throws {
        var objects: [HKObject] = [entry.sample]
        if let correlation = entry.sample as? HKCorrelation {
            objects += Array(correlation.objects)
        }
        try await store.delete(objects)
        changeCount += 1
    }
}
