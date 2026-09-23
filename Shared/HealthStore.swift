import HealthKit
import Observation
import WidgetKit

/// A sample this app wrote, shaped for display in the history list.
struct LoggedEntry: Identifiable {
    let sample: HKSample
    let title: String
    let systemImage: String
    let valueText: String

    var id: UUID { sample.uuid }
    var date: Date { sample.startDate }
}

/// One day's summed intake of a metric.
struct DailyTotal: Identifiable {
    let day: Date
    let sum: HKQuantity?

    var id: Date { day }

    func value(in option: UnitOption) -> Double {
        sum.map(option.displayValue(from:)) ?? 0
    }
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
    /// Incremented after every save, delete or unit change so views can refresh.
    private(set) var changeCount = 0

    private static let unitOverridesKey = "unitOverrides"
    /// Units the user picked in Options, as unit labels keyed by metric ID. Missing means automatic.
    private var unitOverrides = AppGroup.defaults.dictionary(forKey: unitOverridesKey) as? [String: String] ?? [:]

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

    func loadPreferredUnits() async {
        let types = Set(Metric.all.flatMap(\.sampleTypes).compactMap { $0 as? HKQuantityType })
        if let units = try? await store.preferredUnits(for: types) {
            preferredUnits = units
        }
    }

    /// The unit to show for a metric: the user's choice in Options, otherwise the automatic one.
    func unitOption(for metric: Metric) -> UnitOption? {
        unitOverride(for: metric) ?? automaticUnitOption(for: metric)
    }

    /// Picks the unit that matches the user's Health app preference, falling back to their region.
    func automaticUnitOption(for metric: Metric) -> UnitOption? {
        let options = metric.unitOptions
        guard case .quantity(let id, _) = metric.kind else { return nil }
        if let preferred = preferredUnits[HKQuantityType(id)],
           let match = options.first(where: { $0.unit == preferred }) {
            return match
        }
        let isUS = Locale.current.measurementSystem == .us
        return options.first { $0.system == .both || $0.system == (isUS ? .us : .metric) } ?? options.first
    }

    func unitOverride(for metric: Metric) -> UnitOption? {
        guard let label = unitOverrides[metric.id] else { return nil }
        return metric.unitOptions.first { $0.label == label }
    }

    /// Pass nil to go back to the automatic unit.
    func setUnitOverride(_ option: UnitOption?, for metric: Metric) {
        unitOverrides[metric.id] = option?.label
        AppGroup.defaults.set(unitOverrides, forKey: Self.unitOverridesKey)
        didChange()
    }

    // MARK: Favorites

    private static let favoritesKey = "favoriteMetrics"
    private static let favoritesUpdatedKey = "favoriteMetricsUpdated"
    /// Metric IDs the user starred, synced between iPhone and Watch.
    private var favoriteIDs = Set(AppGroup.defaults.stringArray(forKey: favoritesKey) ?? [])
    /// When favorites last changed on either device; nil until they're first edited.
    private var favoritesUpdated = AppGroup.defaults.object(forKey: favoritesUpdatedKey) as? Date
    private var sync: DeviceSync?

    /// Widgets pass false: they only read favorites, and syncing is the app's job.
    init(syncsFavorites: Bool = true) {
        guard syncsFavorites else { return }
        sync = DeviceSync { [weak self] remote in self?.reconcileFavorites(with: remote) }
        sync?.activate()
    }

    /// Starred metrics in catalog order.
    var favorites: [Metric] {
        Metric.all.filter { favoriteIDs.contains($0.id) }
    }

    func isFavorite(_ metric: Metric) -> Bool {
        favoriteIDs.contains(metric.id)
    }

    func toggleFavorite(_ metric: Metric) {
        if favoriteIDs.remove(metric.id) == nil { favoriteIDs.insert(metric.id) }
        saveFavorites(updated: .now)
        if let state = favoritesState { sync?.send(state) }
    }

    private var favoritesState: FavoritesState? {
        favoritesUpdated.map { FavoritesState(ids: favoriteIDs.sorted(), updated: $0) }
    }

    private func saveFavorites(updated: Date) {
        favoritesUpdated = updated
        AppGroup.defaults.set(favoriteIDs.sorted(), forKey: Self.favoritesKey)
        AppGroup.defaults.set(updated, forKey: Self.favoritesUpdatedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Takes the other device's favorites if they're newer, otherwise sends ours so it catches up.
    private func reconcileFavorites(with remote: FavoritesState?) {
        if let remote, remote.updated > favoritesUpdated ?? .distantPast {
            favoriteIDs = Set(remote.ids)
            saveFavorites(updated: remote.updated)
        } else if let local = favoritesState, local.updated != remote?.updated {
            sync?.send(local)
        }
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

    private func didChange() {
        changeCount += 1
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func save(_ objects: [HKObject]) async throws {
        try await store.save(objects)
        didChange()
    }

    /// Saves a food as one Health food entry, so Health shows it by name alongside its nutrients.
    /// Amounts are in each metric's first unit option; zero amounts are skipped.
    func saveFood(named name: String, amounts: [(metric: Metric, value: Double)], date: Date) async throws {
        // Only the food entry is tagged as ours, so history lists the food once rather than per nutrient.
        let nutrientMetadata: [String: Any] = [HKMetadataKeyWasUserEntered: true, HKMetadataKeyFoodType: name]
        let samples = amounts.compactMap { metric, value -> HKSample? in
            guard value > 0, case .quantity(let id, let options) = metric.kind, let unit = options.first else { return nil }
            return HKQuantitySample(type: HKQuantityType(id), quantity: unit.quantity(fromDisplay: value),
                                    start: date, end: date, metadata: nutrientMetadata)
        }
        guard !samples.isEmpty else { return }
        var metadata = baseMetadata
        metadata[HKMetadataKeyFoodType] = name
        let food = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date,
                                 objects: Set(samples), metadata: metadata)
        try await save([food])
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

    /// Newest sample of a metric from any source, or nil if there is none. Unlike `latestValue`, this throws
    /// when Health can't be read, such as while the device is locked.
    func latestSample(of metric: Metric) async throws -> HKSample? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: metric.historyType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1)
        return try await descriptor.result(for: store).first
    }

    /// Entries logged by this app on iPhone or Apple Watch, newest first.
    func recentEntries(of metrics: [Metric] = Metric.all, includingFoods: Bool = true, since start: Date? = nil,
                       limit: Int = 200) async throws -> [LoggedEntry] {
        var ours = HKQuery.predicateForObjects(withMetadataKey: Self.entryMetadataKey)
        if let start {
            ours = NSCompoundPredicate(andPredicateWithSubpredicates: [
                ours, HKQuery.predicateForSamples(withStart: start, end: nil),
            ])
        }
        var types = Set(metrics.map(\.historyType))
        if includingFoods { types.insert(HKCorrelationType(.food)) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: types.map { HKSamplePredicate.sample(type: $0, predicate: ours) },
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit)
        return try await descriptor.result(for: store).compactMap(entry(for:))
    }

    /// Per-day sums of a quantity metric from every source in Health (not just this app),
    /// oldest first and ending today. Days with nothing logged have a nil sum.
    func dailyTotals(for metric: Metric, days: Int) async throws -> [DailyTotal] {
        guard case .quantity(let id, _) = metric.kind else { return [] }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let start = calendar.date(byAdding: .day, value: -days, to: end)!
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var totals: [DailyTotal] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard statistics.startDate < end else { return }
            totals.append(DailyTotal(day: statistics.startDate, sum: statistics.sumQuantity()))
        }
        return totals
    }

    private func entry(for sample: HKSample) -> LoggedEntry? {
        if let food = sample as? HKCorrelation, food.correlationType == HKCorrelationType(.food) {
            return foodEntry(food)
        }
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
        return LoggedEntry(sample: sample, title: metric.name, systemImage: metric.systemImage, valueText: text)
    }

    private func foodEntry(_ food: HKCorrelation) -> LoggedEntry {
        let name = food.metadata?[HKMetadataKeyFoodType] as? String ?? "Food"
        let calories = (food.objects(for: HKQuantityType(.dietaryEnergyConsumed)).first as? HKQuantitySample)?
            .quantity.doubleValue(for: .kilocalorie())
        let text = calories.map { "\($0.formatted(.number.precision(.fractionLength(0)))) kcal" } ?? "Logged"
        return LoggedEntry(sample: food, title: name, systemImage: "fork.knife", valueText: text)
    }

    func bloodPressureValues(_ correlation: HKCorrelation) -> (systolic: Double, diastolic: Double)? {
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
        didChange()
    }
}
