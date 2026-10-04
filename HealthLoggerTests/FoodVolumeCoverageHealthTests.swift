import Foundation
import HealthKit
import Testing
@testable import HealthLogger

@MainActor
@Suite(.serialized)
struct FoodVolumeCoverageHealthTests {
    private let health = HealthStore(syncs: false)
    private let raw = HKHealthStore()
    private let name = "Volume coverage \(UUID().uuidString)"
    private let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(600)

    private func entries() async throws -> [LoggedEntry] {
        try await health.recentEntries(of: [], since: date, limit: nil).filter { $0.title == name }
    }

    private func cleanUp() async throws {
        for entry in try await entries() { try await health.delete(entry) }
    }

    @Test func volumeAndKnownZeroSurviveLoggingEditingAndRelogging() async throws {
        var milk = FoodPortion(name: name, servingSize: "100 mL",
            nutrients: ["dietaryEnergyConsumed": 50, "dietaryProtein": 3.5, "dietarySugar": 0],
            millilitersPerServing: 100)
        milk.enter(volumeUnit: .milliliters)
        milk.enteredAmount = 180
        try await health.saveFoods([milk], meal: .breakfast, date: date)
        let original = try #require(try await entries().first)
        var stored = try #require(original.food)
        #expect(stored.amountText == "180 mL")
        #expect(stored.millilitersPerServing == 100)
        #expect(stored.amount(of: "dietaryEnergyConsumed") == 90)
        #expect(stored.nutrients["dietarySugar"] == 0)
        #expect(stored.nutrients["dietarySodium"] == nil)
        let correlation = try #require(original.sample as? HKCorrelation)
        #expect(correlation.objects(for: HKQuantityType(.dietarySugar)).count == 1)
        #expect(correlation.objects(for: HKQuantityType(.dietarySodium)).isEmpty)
        stored.enter(volumeUnit: .usFluidOunces)
        stored.enteredAmount = 8
        try await health.saveFoods([stored], meal: .lunch, date: date, replacing: original)
        let edited = try #require(try await entries().first?.food)
        #expect(edited.enteredVolumeUnit == .usFluidOunces)
        #expect(abs(edited.enteredAmount - 8) < 1e-9)
        #expect(edited.nutrients["dietarySugar"] == 0)
        try await health.saveFoods([edited], meal: .dinner, date: date.addingTimeInterval(60))
        #expect(try await entries().count == 2)
        #expect(try await entries().allSatisfy { $0.food?.enteredVolumeUnit == .usFluidOunces })
        try await cleanUp()
    }

    @Test func collapsedRecipeRetainsMissingIngredientCountsAfterAnEdit() async throws {
        let ingredients = [
            FoodPortion(name: "Known", nutrients: ["dietaryEnergyConsumed": 10, "dietarySodium": 120]),
            FoodPortion(name: "Unknown A", nutrients: ["dietaryEnergyConsumed": 20]),
            FoodPortion(name: "Unknown B", nutrients: ["dietaryEnergyConsumed": 30]),
            FoodPortion(name: "Excluded", nutrients: ["dietaryEnergyConsumed": 50], servings: 0)
        ]
        let recipe = Recipe(name: name, servings: 2, ingredients: ingredients)
        try await health.saveFoods([recipe.portion], meal: .lunch, date: date)
        let original = try #require(try await entries().first)
        var portion = try #require(original.food)
        #expect(portion.nutrients["dietarySodium"] == 60)
        #expect(portion.coverage(of: "dietarySodium") == NutrientCoverage(known: 1, missing: 2))
        #expect(portion.coverage(of: "dietarySugar") == NutrientCoverage(known: 0, missing: 3))
        portion.servings = 2
        try await health.saveFoods([portion], meal: .dinner, date: date, replacing: original)
        let edited = try #require(try await entries().first?.food)
        #expect(edited.amount(of: "dietarySodium") == 120)
        #expect(edited.coverage(of: "dietarySodium").missing == 2)
        let sodium = try #require(Metric.metric(id: "dietarySodium"))
        let day = try #require(try await health.dailyTotals(for: sodium, days: 1).last)
        #expect(day.hasRecordedData)
        #expect(day.missingIngredientCount >= 2)
        try await cleanUp()
    }

    @Test func explicitZeroCanBeTheOnlyKnownNutrient() async throws {
        try await health.saveFoods([FoodPortion(name: name, nutrients: ["dietaryEnergyConsumed": 0])],
                                   meal: .snack, date: date)
        let food = try #require(try await entries().first?.food)
        #expect(food.nutrients["dietaryEnergyConsumed"] == 0)
        #expect(food.nutrients["dietaryProtein"] == nil)
        try await cleanUp()
    }

    @Test func legacyCorrelationKeepsCoverageUncertainWhenLoggedAgain() async throws {
        let sample = HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 20), start: date, end: date)
        let old = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: [sample],
            metadata: [HealthStore.entryMetadataKey: true, HKMetadataKeyFoodType: name])
        try await raw.save(old)
        let food = try #require(try await entries().first?.food)
        #expect(food.coverage(of: "dietaryEnergyConsumed").isUncertain)
        #expect(food.millilitersPerServing == nil)
        try await health.saveFoods([food], meal: .lunch, date: date.addingTimeInterval(60))
        let again = try #require(try await entries().first?.food)
        #expect(again.coverage(of: "dietaryEnergyConsumed").isUncertain)
        try await cleanUp()
    }

    @Test func entirelyUnknownIngredientsRequireARecipeAndNeverCreateFakeSamples() async throws {
        let known = FoodPortion(name: name, nutrients: ["dietaryEnergyConsumed": 50])
        let unknown = FoodPortion(name: "Unknown ingredient", nutrients: [:])
        await #expect(throws: FoodLoggingError.self) {
            try await health.saveFoods([known, unknown], meal: .snack, date: date)
        }
        #expect(try await entries().isEmpty)
        let recipe = Recipe(name: name, servings: 1, ingredients: [known, unknown])
        try await health.saveFoods([recipe.portion], meal: .snack, date: date)
        let entry = try #require(try await entries().first)
        let correlation = try #require(entry.sample as? HKCorrelation)
        #expect(correlation.objects.count == 1)
        #expect(correlation.objects(for: HKQuantityType(.dietarySodium)).isEmpty)
        #expect(entry.food?.coverage(of: "dietarySodium").missing == 2)
        #expect(entry.food?.coverage(of: "dietaryEnergyConsumed").missing == 1)
        try await cleanUp()
    }

    @Test func emptyDailyTotalIsNotMeasuredZero() {
        let empty = DailyTotal(day: date, sum: nil)
        let zero = DailyTotal(day: date, sum: HKQuantity(unit: .gram(), doubleValue: 0))
        #expect(!empty.hasRecordedData)
        #expect(empty.coverageText == "No recorded data available")
        #expect(zero.hasRecordedData)
        #expect(zero.coverageText.contains("coverage may be incomplete"))
    }
}
