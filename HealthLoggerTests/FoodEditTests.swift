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

    /// Interrupted after the correction saved, then the cleanup on relaunch fails too: the edit is noted as saved,
    /// so History still offers to finish it, and a later try does.
    @Test func anInterruptedEditWhoseCleanupFailsStaysListed() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 3
        struct Terminated: Error {}
        health.stopForFault = { throw Terminated() }
        health.editFault = .stop
        await #expect(throws: Terminated.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }

        let relaunched = HealthStore(syncs: false, editDefaults: defaults)
        relaunched.editFault = .delete
        await relaunched.finishPendingEdits()
        let edit = try #require(relaunched.unfinishedEdits.first)
        #expect(edit.replacementSaved)
        #expect(try await entries(using: relaunched).count == 2)

        // And again after another relaunch, from the journal alone.
        let again = HealthStore(syncs: false, editDefaults: defaults)
        #expect(again.unfinishedEdits.map(\.id) == [edit.id])
        try await again.finishEdit(edit)
        #expect(again.pendingEdits.isEmpty)
        #expect(try await entries(using: again).map(\.id) == [edit.replacement])
        try await cleanUp()
    }

    /// Deleting the correction of an unfinished edit from History drops the edit, so the original can't then be
    /// removed too.
    @Test func deletingTheCorrectionKeepsTheOriginal() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2
        health.editFault = .delete
        await #expect(throws: EditError.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        let edit = try #require(health.unfinishedEdits.first)
        let correction = try #require(try await entries().first { $0.id == edit.replacement })
        try await health.delete(correction)
        #expect(health.pendingEdits.isEmpty)

        // Remove Original, from a History that hadn't refreshed yet.
        await #expect(throws: EditError.self) { try await self.health.finishEdit(edit) }
        #expect(try await entries().map(\.id) == [original.id])
        try await cleanUp()
    }

    /// The same when the correction is deleted outside the app, such as in the Health app.
    @Test func finishingAfterTheCorrectionIsDeletedElsewhereKeepsTheOriginal() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2
        health.editFault = .delete
        await #expect(throws: EditError.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        let edit = try #require(health.unfinishedEdits.first)
        let correction = try #require(try await health.sample(of: HKCorrelationType(.food), id: edit.replacement))
        try await raw.delete([correction] + Array((correction as! HKCorrelation).objects))
        #expect(health.unfinishedEdits == [edit])

        do {
            try await health.finishEdit(edit)
            Issue.record("Finishing should have reported that the correction is gone.")
        } catch EditError.correctionMissing {}
        #expect(health.pendingEdits.isEmpty)
        #expect(try await entries().map(\.id) == [original.id])
        try await cleanUp()
    }

    /// Deleting the original of an unfinished edit from History finishes it by hand: the correction stays.
    @Test func deletingTheOriginalDropsTheEdit() async throws {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2
        health.editFault = .delete
        await #expect(throws: EditError.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        let edit = try #require(health.unfinishedEdits.first)
        try await health.delete(original)
        #expect(health.pendingEdits.isEmpty)
        #expect(try await entries().map(\.id) == [edit.replacement])
        try await cleanUp()
    }

    /// An edit whose original couldn't be removed, left for later: A was corrected to B, and both are in Health.
    private func unfinishedEdit() async throws -> (original: LoggedEntry, correction: LoggedEntry, edit: PendingEdit) {
        let original = try await logGranola()
        var food = try #require(original.food)
        food.servings = 2
        health.editFault = .delete
        await #expect(throws: EditError.self) {
            try await self.health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
        }
        let edit = try #require(health.unfinishedEdits.first)
        let correction = try #require(try await entries().first { $0.id == edit.replacement })
        return (original, correction, edit)
    }

    /// Editing the correction of an unfinished edit removes that edit's original first, so the new correction is the
    /// only entry left, now and after a relaunch. It once left the first original too: 200 + 600 kcal for 600.
    @Test func editingAnUnfinishedCorrectionRemovesItsOriginal() async throws {
        let (_, correction, _) = try await unfinishedEdit()
        var food = try #require(correction.food)
        food.servings = 3
        try await health.saveFoods([food], meal: .breakfast, date: correction.date, replacing: correction)
        #expect(health.pendingEdits.isEmpty)
        #expect(try await entries().map { $0.food?.calories } == [600])

        let relaunched = HealthStore(syncs: false, editDefaults: defaults)
        await relaunched.finishPendingEdits()
        #expect(try await entries(using: relaunched).map { $0.food?.calories } == [600])
        try await cleanUp()
    }

    /// If that original still can't be removed, the correction isn't edited, and the earlier edit is still offered.
    @Test func anUnfinishedCorrectionIsntEditedWhileItsOriginalRemains() async throws {
        let (original, correction, edit) = try await unfinishedEdit()
        var food = try #require(correction.food)
        food.servings = 3
        health.editFault = .delete
        do {
            try await health.saveFoods([food], meal: .breakfast, date: correction.date, replacing: correction)
            Issue.record("The edit should have reported the earlier one.")
        } catch EditError.earlierEditUnfinished {}
        #expect(Set(try await entries().map(\.id)) == [original.id, correction.id])
        #expect(health.unfinishedEdits == [edit])

        try await health.finishEdit(edit)
        #expect(try await entries().map(\.id) == [correction.id])
        try await cleanUp()
    }

    /// The original of an unfinished edit has a correction already, so editing it too is refused.
    @Test func theOriginalOfAnUnfinishedEditIsntEdited() async throws {
        let (original, correction, edit) = try await unfinishedEdit()
        var food = try #require(original.food)
        food.servings = 3
        do {
            try await health.saveFoods([food], meal: .breakfast, date: original.date, replacing: original)
            Issue.record("The edit should have reported the correction.")
        } catch EditError.alreadyCorrected {}
        #expect(Set(try await entries().map(\.id)) == [original.id, correction.id])
        #expect(health.unfinishedEdits == [edit])
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

/// C5's source and estimate context in Health, against the simulator's real Health store. Needs Health access, as
/// for `FoodEditTests`.
@MainActor
@Suite(.serialized)
final class PublishedFoodHealthTests {
    private let raw = HKHealthStore()
    private let defaults: UserDefaults
    private let suiteName = "PublishedFoodHealthTests-\(UUID().uuidString)"
    private var health: HealthStore
    private let name = "Test Chicken \(UUID().uuidString.prefix(8))"
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

    /// Chipotle's published chicken, per 4 oz.
    private var chicken: FoodPortion {
        FoodPortion(name: name, brand: "Chipotle", servingSize: "4 oz",
                    nutrients: ["dietaryEnergyConsumed": 180, "dietaryFatTotal": 7, "dietaryFatSaturated": 3,
                                "dietaryCholesterol": 125, "dietarySodium": 310, "dietaryProtein": 32],
                    gramsPerServing: 113,
                    source: NutritionSource(title: "Full Nutrition Facts",
                                            url: URL(string: "https://www.chipotle.com/content/dam/chipotle/menu/nutrition/US-Nutrition-Facts-Paper-Menu-3-2025.pdf")!,
                                            retrieved: Date(timeIntervalSince1970: 1_791_000_000), market: "US",
                                            servingBasis: "4 oz", provider: "chipotle.com"))
    }

    private func entries() async throws -> [LoggedEntry] {
        try await health.recentEntries(of: [], since: start).filter { $0.title == name }
    }

    private func cleanUp() async throws {
        for entry in try await entries() { try await health.delete(entry) }
    }

    /// Ready when: a confirmed double portion scales each published nutrient exactly twice, and re-logged meals
    /// retain their reviewed values and source context.
    @Test func aDoublePublishedPortionKeepsItsSourceInHealth() async throws {
        var double = chicken
        double.servings = 2
        try await health.saveFoods([double], meal: .lunch, date: start)
        let food = try #require(try await entries().first?.food)
        #expect(food.servings == 2)
        #expect(food.source == chicken.source)
        #expect(!food.isEstimate)
        for (id, value) in chicken.nutrients {
            #expect(abs(food.amount(of: id) - value * 2) < 1e-9, "\(id)")
        }

        // Logged again, as Recents and Log Again do, it keeps the same values and source.
        try await health.saveFoods([food], meal: .lunch, date: start.addingTimeInterval(60))
        let again = try await entries()
        #expect(again.count == 2)
        #expect(again.allSatisfy { $0.food?.source == chicken.source && $0.food?.nutrients == food.nutrients })
        try await cleanUp()
    }

    @Test func anEstimateIsMarkedAsOne() async throws {
        let estimate = FoodPortion(name: name, servingSize: "1 serving", nutrients: ["dietaryEnergyConsumed": 250],
                                   isEstimate: true)
        try await health.saveFoods([estimate], meal: .dinner, date: start)
        let food = try #require(try await entries().first?.food)
        #expect(food.isEstimate)
        #expect(food.source == nil)
        try await cleanUp()
    }

    /// Editing a looked-up food (C3) keeps its source.
    @Test func editingKeepsTheSource() async throws {
        try await health.saveFoods([chicken], meal: .lunch, date: start)
        let entry = try #require(try await entries().first)
        var corrected = try #require(entry.food)
        corrected.servings = 1.5
        try await health.saveFoods([corrected], meal: .lunch, date: entry.date, replacing: entry)
        let edited = try await entries()
        #expect(edited.count == 1)
        #expect(edited.first?.food?.servings == 1.5)
        #expect(edited.first?.food?.source == chicken.source)
        try await cleanUp()
    }
}
