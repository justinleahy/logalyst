import HealthKit
import Observation
import WidgetKit

/// A sample this app wrote, shaped for display in the history list.
struct LoggedEntry: Identifiable, Hashable {
    let sample: HKSample
    /// The metric it logs, or nil for a food.
    let metric: Metric?
    let title: String
    let systemImage: String
    let valueText: String
    /// For a food, what was eaten, so it can be logged again.
    var food: FoodPortion?
    /// For a food, the meal it was saved under, or the usual meal for its time if it was saved without one.
    var meal: Meal?

    var id: UUID { sample.uuid }
    var date: Date { sample.startDate }

    static func == (lhs: LoggedEntry, rhs: LoggedEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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

extension Error {
    /// True when Health refused because the device is locked. Health data is encrypted until the next unlock.
    var isHealthDataLocked: Bool {
        (self as? HKError)?.code == .errorDatabaseInaccessible
    }

    /// Text for an alert, replacing HealthKit's "Protected health data is inaccessible" with what to do about it.
    var healthMessage: String {
        guard isHealthDataLocked else { return localizedDescription }
        #if os(watchOS)
        return "Unlock your Apple Watch to use Health data, then try again."
        #else
        return "Unlock your iPhone to use Health data, then try again."
        #endif
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
    /// Extra details saved on food entries, so a past entry can be logged again as it was.
    private static let mealMetadataKey = "HealthLoggerMeal"
    private static let servingsMetadataKey = "HealthLoggerServings"
    private static let servingSizeMetadataKey = "HealthLoggerServingSize"
    private static let brandMetadataKey = "HealthLoggerBrand"

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

    /// Asks to read height, weight, age, sex and resting energy, only when the user opens Suggest Goals.
    func requestProfileAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: [
            HKQuantityType(.height), HKQuantityType(.bodyMass), HKQuantityType(.basalEnergyBurned),
            HKCharacteristicType(.dateOfBirth), HKCharacteristicType(.biologicalSex),
        ])
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

    /// Widgets pass false: they only read favorites and goals, and syncing is the app's job.
    init(syncs: Bool = true) {
        guard syncs else { return }
        sync = DeviceSync { [weak self] remote in self?.reconcile(with: remote) }
        sync?.activate()
    }

    /// A HealthStore for widgets and intents, which run outside the app's screens, with units loaded.
    static func standalone() async -> HealthStore {
        let health = HealthStore(syncs: false)
        await health.loadPreferredUnits()
        return health
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

    private func reconcile(with remote: RemoteState) {
        reconcileFavorites(with: remote.favorites)
        #if os(watchOS)
        if let goals = remote.goals { NutritionGoals.receive(goals) }
        if let presets = remote.presets { receivePresets(presets) }
        #else
        sendGoals()
        sendPresets()
        #endif
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

    // MARK: Goals

    /// Offers the Watch the goals set on this iPhone, so its complications can show progress toward them.
    /// Does nothing if the Watch already has them.
    func sendGoals() {
        sync?.send(goals: NutritionGoals.saved)
    }

    // MARK: Presets

    static let maxPresets = 6
    private static let presetsKey = "customPresets"
    /// Preset amounts the user edited, keyed by metric ID then unit label, in that unit. A missing entry means the
    /// unit's built-in presets; an empty list means the user removed them all. Set on the iPhone, synced to the Watch.
    private var customPresets = AppGroup.defaults.dictionary(forKey: presetsKey) as? [String: [String: [Double]]] ?? [:]

    /// Quick-entry amounts for a metric in a unit, smallest first: the user's own if they've edited them,
    /// otherwise the built-in ones.
    func presets(for metric: Metric, in option: UnitOption) -> [Double] {
        customPresets[metric.id]?[option.label] ?? option.presets
    }

    func hasCustomPresets(for metric: Metric, in option: UnitOption) -> Bool {
        customPresets[metric.id]?[option.label] != nil
    }

    /// Whether the amount could be added as a new preset: in range, not already one, and under the limit.
    func canAddPreset(_ value: Double, for metric: Metric, in option: UnitOption) -> Bool {
        let presets = presets(for: metric, in: option)
        return option.range.contains(value) && !presets.contains(option.rounded(value))
            && presets.count < Self.maxPresets
    }

    func addPreset(_ value: Double, for metric: Metric, in option: UnitOption) {
        guard canAddPreset(value, for: metric, in: option) else { return }
        setPresets((presets(for: metric, in: option) + [option.rounded(value)]).sorted(), for: metric, in: option)
    }

    func removePreset(_ value: Double, for metric: Metric, in option: UnitOption) {
        setPresets(presets(for: metric, in: option).filter { $0 != value }, for: metric, in: option)
    }

    /// Goes back to the unit's built-in presets.
    func resetPresets(for metric: Metric, in option: UnitOption) {
        setPresets(nil, for: metric, in: option)
    }

    private func setPresets(_ amounts: [Double]?, for metric: Metric, in option: UnitOption) {
        // A list matching the built-in one isn't stored, so the unit counts as unedited again.
        customPresets[metric.id, default: [:]][option.label] = amounts == option.presets ? nil : amounts
        if customPresets[metric.id]?.isEmpty == true { customPresets[metric.id] = nil }
        AppGroup.defaults.set(customPresets, forKey: Self.presetsKey)
        WidgetCenter.shared.reloadAllTimelines()
        sendPresets()
    }

    /// Offers the Watch the presets edited on this iPhone, so its Log Water control logs the same glass.
    func sendPresets() {
        sync?.send(presets: customPresets)
    }

    /// Stores the presets the iPhone sent.
    private func receivePresets(_ presets: [String: [String: [Double]]]) {
        guard presets != customPresets else { return }
        customPresets = presets
        AppGroup.defaults.set(presets, forKey: Self.presetsKey)
        WidgetCenter.shared.reloadAllTimelines()
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

    /// Saves an event that ended at `end` and lasted `duration` seconds.
    func saveTimedEvent(_ metric: Metric, duration: TimeInterval, end: Date) async throws {
        guard case .timedEvent(let id) = metric.kind else { return }
        let sample = HKCategorySample(type: HKCategoryType(id), value: HKCategoryValue.notApplicable.rawValue,
                                      start: end.addingTimeInterval(-duration), end: end, metadata: baseMetadata)
        try await save([sample])
    }

    func saveSexualActivity(protection: Protection, date: Date) async throws {
        var metadata = baseMetadata
        if let used = protection.healthKitValue {
            metadata[HKMetadataKeySexualActivityProtectionUsed] = used
        }
        let sample = HKCategorySample(type: HKCategoryType(.sexualActivity), value: HKCategoryValue.notApplicable.rawValue,
                                      start: date, end: date, metadata: metadata)
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

    /// Saves each food as one Health food entry, so Health shows it by name alongside its nutrients.
    /// Foods with nothing to log are skipped.
    func saveFoods(_ foods: [FoodPortion], meal: Meal, date: Date) async throws {
        let entries = foods.compactMap { foodEntry(for: $0, meal: meal, date: date) }
        guard !entries.isEmpty else { return }
        try await save(entries)
    }

    private func foodEntry(for food: FoodPortion, meal: Meal, date: Date) -> HKCorrelation? {
        // Only the food entry is tagged as ours, so history lists the food once rather than per nutrient.
        let nutrientMetadata: [String: Any] = [HKMetadataKeyWasUserEntered: true, HKMetadataKeyFoodType: food.name]
        let samples = food.nutrients.keys.sorted().compactMap { id -> HKSample? in
            let value = food.amount(of: id)
            guard value > 0, let metric = Metric.metric(id: id), case .quantity(let type, let options) = metric.kind,
                  let unit = options.first else { return nil }
            return HKQuantitySample(type: HKQuantityType(type), quantity: unit.quantity(fromDisplay: value),
                                    start: date, end: date, metadata: nutrientMetadata)
        }
        guard !samples.isEmpty else { return nil }
        var metadata = baseMetadata
        metadata[HKMetadataKeyFoodType] = food.name
        metadata[Self.mealMetadataKey] = meal.rawValue
        metadata[Self.servingsMetadataKey] = food.servings
        if !food.servingSize.isEmpty { metadata[Self.servingSizeMetadataKey] = food.servingSize }
        if !food.brand.isEmpty { metadata[Self.brandMetadataKey] = food.brand }
        return HKCorrelation(type: HKCorrelationType(.food), start: date, end: date,
                             objects: Set(samples), metadata: metadata)
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

    /// Most recent height in centimeters, from any source.
    func latestHeightCm() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.height))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1)
        return try? await descriptor.result(for: store).first?.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// Typical resting energy burned a day, in kcal: the median of the last two weeks' full days that have any,
    /// so days the Watch was off for a while don't drag it down. Nil with fewer than 3 days of data.
    func typicalRestingEnergy() async -> Double? {
        guard let totals = try? await dailyTotals(of: .basalEnergyBurned, days: 15) else { return nil }
        // Drop today, which isn't over yet.
        let days = totals.dropLast().compactMap { $0.sum?.doubleValue(for: .kilocalorie()) }.sorted()
        guard days.count >= 3 else { return nil }
        return days[days.count / 2]
    }

    /// The user's age from the birthday in their Health profile, or nil if it isn't set or can't be read.
    func age() -> Int? {
        guard let birthday = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: birthday) else {
            return nil
        }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
    }

    /// The sex in the user's Health profile, or nil if it isn't set or can't be read.
    func biologicalSex() -> HKBiologicalSex? {
        guard let sex = try? store.biologicalSex().biologicalSex, sex != .notSet else { return nil }
        return sex
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
        return try await dailyTotals(of: id, days: days)
    }

    private func dailyTotals(of id: HKQuantityTypeIdentifier, days: Int) async throws -> [DailyTotal] {
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
            text = metric.summary(of: category)
        default:
            return nil
        }
        return LoggedEntry(sample: sample, metric: metric, title: metric.name, systemImage: metric.systemImage, valueText: text)
    }

    private func foodEntry(_ food: HKCorrelation) -> LoggedEntry {
        let metadata = food.metadata ?? [:]
        let name = metadata[HKMetadataKeyFoodType] as? String ?? "Food"
        // Entries saved before servings were recorded count as one serving of what was eaten.
        let servings = (metadata[Self.servingsMetadataKey] as? NSNumber)?.doubleValue ?? 1
        var totals: [String: Double] = [:]
        for case let sample as HKQuantitySample in food.objects {
            guard let metric = Metric.metric(for: sample.quantityType),
                  case .quantity(_, let options) = metric.kind, let unit = options.first else { continue }
            totals[metric.id, default: 0] += unit.displayValue(from: sample.quantity)
        }
        let portion = FoodPortion(
            name: name, brand: metadata[Self.brandMetadataKey] as? String ?? "",
            servingSize: metadata[Self.servingSizeMetadataKey] as? String ?? "",
            nutrients: servings > 0 ? totals.mapValues { $0 / servings } : totals, servings: servings > 0 ? servings : 1)
        let meal = (metadata[Self.mealMetadataKey] as? String).flatMap(Meal.init(rawValue:)) ?? Meal(at: food.startDate)
        let text = totals["dietaryEnergyConsumed"].map { "\($0.formatted(.number.precision(.fractionLength(0)))) kcal" }
            ?? "Logged"
        return LoggedEntry(sample: food, metric: nil, title: name, systemImage: "fork.knife", valueText: text,
                           food: portion, meal: meal)
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
