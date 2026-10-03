import Foundation
import HealthKit
import Testing
@testable import HealthLogger

/// Edits and weighed foods against the simulator's real Health store. Needs Health access: open the app once in the
/// simulator and allow it. Each test logs foods with a unique name and deletes what it logged.
@MainActor
@Suite(.serialized)
final class FoodEditTests {
    private let raw = HKHealthStore()
    private let defaults: UserDefaults
    private let suiteName = "FoodEditTests-\(UUID().uuidString)"
    private var health: HealthStore
    private let name = "Test Food \(UUID().uuidString.prefix(8))"
    private let start = Date.now.addingTimeInterval(-3 * 3600)

    init() throws {
        defaults = UserDefaults(suiteName: suiteName)!
        health = HealthStore(syncs: false, editDefaults: defaults)
        let status = raw.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed))
        try #require(status == .sharingAuthorized, "Open Logalyst in this simulator and allow Health access first.")
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// One serving: 200 kcal and 10 g protein in 50 g.
    private var granola: FoodPortion {
        FoodPortion(name: name, brand: "Test", servingSize: "1/2 cup (50 g)",
                    nutrients: ["dietaryEnergyConsumed": 200, "dietaryProtein": 10], gramsPerServing: 50)
    }

    /// This test's food entries, newest first.
    private func entries(using store: HealthStore? = nil) async throws -> [LoggedEntry] {
        try await (store ?? health).recentEntries(of: [], since: start).filter { $0.title == name }
    }

    private func cleanUp() async throws {
        for entry in try await entries() { try await health.delete(entry) }
        #expect(try await entries().isEmpty)
    }

    private func logGranola(servings: Double = 1, at date: Date? = nil) async throws -> LoggedEntry {
        var portion = granola
        portion.servings = servings
        try await health.saveFoods([portion], meal: .breakfast, date: date ?? start.addingTimeInterval(60))
        return try #require(try await entries().first)
    }

    // MARK: Assumptions

    /// The edit journal records the correction's ID before saving it, which relies on Health keeping it.
    @Test func healthKeepsTheIDAnEntryIsCreatedWith() async throws {
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryWater),
                                      quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: 123),
                                      start: start, end: start)
        let id = sample.uuid
        try await raw.save(sample)
        let found = try await health.sample(of: HKQuantityType(.dietaryWater), id: id)
        #expect(found?.uuid == id)
        try await raw.delete(sample)
        #expect(try await health.sample(of: HKQuantityType(.dietaryWater), id: id) == nil)
    }

    // MARK: Weighed foods

    @Test func aWeighedFoodIsSavedAndReadBackByWeight() async throws {
        var portion = granola
        portion.enter(in: .grams)
        portion.enteredAmount = 35
        try await health.saveFoods([portion], meal: .snack, date: start)
        let entry = try #require(try await entries().first)
        let food = try #require(entry.food)
        #expect(food.gramsPerServing == 50)
        #expect(food.weightUnit == .grams)
        #expect(abs(food.servings - 0.7) < 1e-9)
        #expect(abs(food.calories - 140) < 1e-9)
        #expect(abs(food.amount(of: "dietaryProtein") - 7) < 1e-9)
        #expect(food.summary == "Test · 35 g · 140 kcal")
        #expect(entry.valueText == "140 kcal")
        try await cleanUp()
    }

    /// Entries logged before 1.1 have no weight metadata, and stay loggable and editable by the serving.
    @Test func anEntryFromBuild25StaysInServings() async throws {
        // Build 25's food entry: no weight keys.
        let samples = [
            HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 400),
                             start: start, end: start, metadata: [HKMetadataKeyFoodType: name]),
        ]
        let correlation = HKCorrelation(type: HKCorrelationType(.food), start: start, end: start, objects: Set(samples),
                                        metadata: [HKMetadataKeyWasUserEntered: true, HealthStore.entryMetadataKey: true,
                                                   HKMetadataKeyFoodType: name, "HealthLoggerMeal": "lunch",
                                                   "HealthLoggerServings": 2.0, "HealthLoggerServingSize": "1 bowl"])
        try await raw.save(correlation)
        let entry = try #require(try await entries().first)
        var food = try #require(entry.food)
        #expect(!food.canWeigh)
        #expect(food.servings == 2)
        #expect(food.nutrients["dietaryEnergyConsumed"] == 200)
        #expect(entry.meal == .lunch)

        food.servings = 3
        try await health.saveFoods([food], meal: .lunch, date: entry.date, replacing: entry)
        let edited = try await entries()
        #expect(edited.count == 1)
        #expect(edited.first?.food?.calories == 600)
        try await cleanUp()
    }

    // MARK: Editing

    /// Ready when: successful edits leave one corrected food entry and the expected nutrient totals.
    @Test func anEditLeavesOneCorrectedEntry() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2.5
        let later = start.addingTimeInterval(1800)
        try await health.saveFoods([food], meal: .dinner, date: later, replacing: original)

        let after = try await entries()
        #expect(after.count == 1)
        let edited = try #require(after.first)
        #expect(edited.id != original.id)
        #expect(edited.meal == .dinner)
        #expect(abs(edited.date.timeIntervalSince(later)) < 1)
        #expect(edited.food?.calories == 500)
        #expect(edited.food?.amount(of: "dietaryProtein") == 25)
        #expect(edited.food?.brand == "Test")
        #expect(edited.food?.servingSize == "1/2 cup (50 g)")
        #expect(try await health.sample(of: HKCorrelationType(.food), id: original.id) == nil)
        #expect(health.pendingEdits.isEmpty)
        try await cleanUp()
    }

    /// Ready when: changing the weight of an entry with weight metadata recalculates its nutrients.
    @Test func changingTheWeightRecalculates() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        #expect(food.canWeigh)
        food.enter(in: .grams)
        food.enteredAmount = 80
        try await health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        let edited = try #require(try await entries().first)
        #expect(abs(edited.food!.calories - 320) < 1e-9)
        #expect(edited.food?.amountText == "80 g")
        try await cleanUp()
    }

    /// Ready when: an injected save failure leaves the original entry unchanged.
    @Test func aFailedSaveLeavesTheOriginal() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 4
        health.editFault = .save
        await #expect(throws: InjectedFault.self) {
            try await self.health.saveFoods([food], meal: .dinner, date: .now, replacing: original)
        }
        let after = try await entries()
        #expect(after.map(\.id) == [original.id])
        #expect(after.first?.food?.calories == 200)
        #expect(after.first?.meal == .breakfast)
        #expect(health.pendingEdits.isEmpty)
        try await cleanUp()
    }

    /// Ready when: an injected delete failure shows the incomplete state, and a retry removes only the original
    /// without saving another replacement.
    @Test func aFailedDeleteCanBeRetried() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2
        health.editFault = .delete
        var incomplete: PendingEdit?
        do {
            try await health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
            Issue.record("The edit should have reported that the original remains.")
        } catch EditError.originalRemains(let edit, _) {
            incomplete = edit
        }
        let edit = try #require(incomplete)
        #expect(health.unfinishedEdits == [edit])
        let both = try await entries()
        #expect(Set(both.map(\.id)) == [original.id, edit.replacement])

        try await health.finishEdit(edit)
        let after = try await entries()
        #expect(after.map(\.id) == [edit.replacement])
        #expect(after.first?.food?.calories == 400)
        #expect(health.pendingEdits.isEmpty)
        try await cleanUp()
    }

    /// History's Keep Both leaves both entries and stops offering to finish.
    @Test func keepingBothLeavesBoth() async throws {
        let original = try await logGranola()
        health.editFault = .delete
        var food = try #require(original.food)
        food.servings = 3
        await #expect(throws: EditError.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        let edit = try #require(health.unfinishedEdits.first)
        health.keepBoth(edit)
        #expect(health.pendingEdits.isEmpty)
        #expect(try await entries().count == 2)
        try await cleanUp()
    }

    /// Ready when: an edit interrupted by app termination is reconciled after relaunch. Stopped right after the
    /// correction saved, before the journal says so: the hardest point to recover from.
    @Test func anEditInterruptedAfterSavingIsFinishedOnRelaunch() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 3
        struct Terminated: Error {}
        health.stopForFault = { throw Terminated() }
        health.editFault = .stop
        await #expect(throws: Terminated.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        #expect(try await entries().count == 2)
        #expect(health.pendingEdits.first?.replacementSaved == false)

        // Relaunch: a new store reading the same journal.
        let relaunched = HealthStore(syncs: false, editDefaults: defaults)
        #expect(relaunched.pendingEdits.count == 1)
        await relaunched.finishPendingEdits()
        #expect(relaunched.pendingEdits.isEmpty)
        let after = try await entries(using: relaunched)
        #expect(after.count == 1)
        #expect(after.first?.id != original.id)
        #expect(after.first?.food?.calories == 600)
        try await cleanUp()
    }

    /// An edit cut short before its correction was saved leaves just the original, so it's dropped on relaunch.
    @Test func anEditInterruptedBeforeSavingIsDroppedOnRelaunch() async throws {
        let original = try await logGranola()
        let edit = PendingEdit(original: original.id, metricID: nil, replacement: UUID(), title: name, started: .now)
        defaults.set(try JSONEncoder().encode([edit]), forKey: "pendingEntryEdits")

        let relaunched = HealthStore(syncs: false, editDefaults: defaults)
        #expect(relaunched.pendingEdits == [edit])
        #expect(relaunched.unfinishedEdits.isEmpty)
        await relaunched.finishPendingEdits()
        #expect(relaunched.pendingEdits.isEmpty)
        #expect(try await entries().map(\.id) == [original.id])
        try await cleanUp()
    }

    /// Other entries are edited the same way, with the same recovery.
    @Test func aWaterEditUsesTheSameRecovery() async throws {
        let water = Metric.water
        let option = try #require(water.unitOptions.first { $0.label == "mL" })
        let date = start.addingTimeInterval(120)
        try await health.saveQuantity(water, value: 321, option: option, date: date)
        func waterEntries(_ store: HealthStore) async throws -> [LoggedEntry] {
            try await store.recentEntries(of: [water], includingFoods: false, since: start)
                .filter { abs($0.date.timeIntervalSince(date)) < 1 }
        }
        let original = try #require(try await waterEntries(health).first)
        health.editFault = .delete
        await #expect(throws: EditError.self) {
            try await self.health.saveQuantity(water, value: 654, option: option, date: date, replacing: original)
        }
        #expect(try await waterEntries(health).count == 2)
        let edit = try #require(health.unfinishedEdits.first)
        #expect(edit.metricID == water.id)
        try await health.finishEdit(edit)
        let after = try await waterEntries(health)
        #expect(after.count == 1)
        #expect(after.first.map { option.displayValue(from: ($0.sample as! HKQuantitySample).quantity) } == 654)
        for entry in after { try await health.delete(entry) }
    }
}
