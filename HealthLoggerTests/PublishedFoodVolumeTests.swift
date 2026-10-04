import Foundation
import Testing
@testable import HealthLogger

@MainActor
struct PublishedFoodVolumeTests {
    private let url = URL(string: "https://example.org/nutrition")!
    private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

    private func foods(_ rows: [String]) -> [PublishedFood] {
        NutritionTable.foods(in: NutritionDocument(url: url, title: "Nutrition", lines: rows),
                             brand: "Example", retrieved: fetched)
    }

    @Test func numericMilliliterColumnsCarryVolumeAndKnownZero() throws {
        let food = try #require(foods(["Serving size (mL)", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Tea 240 0 0 N/A 0"]).first)
        #expect(food.servingBasis == "240 mL")
        #expect(food.millilitersPerServing == 240)
        #expect(food.gramsPerServing == nil)
        #expect(food.nutrients["dietaryEnergyConsumed"] == 0)
        #expect(food.nutrients["dietarySodium"] == nil)
        #expect(food.portion.millilitersPerServing == 240)
        #expect(food.portion.nutrients["dietaryFatTotal"] == 0)
    }

    @Test func numericFluidOunceColumnsKeepTheirSystem() throws {
        let us = try #require(foods(["Serving size (U.S. fl oz)", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Tea 8 0 0 0 0"]).first)
        let imperial = try #require(foods(["Serving size (Imperial fl oz)", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Tea 8 0 0 0 0"]).first)
        #expect(abs(try #require(us.millilitersPerServing) - 236.5882365) < 1e-6)
        #expect(abs(try #require(imperial.millilitersPerServing) - 227.3045) < 1e-6)
        #expect(us.gramsPerServing == nil)
        #expect(imperial.gramsPerServing == nil)
    }

    @Test func ambiguousNumericVolumeKeepsNutritionWithoutInventingMilliliters() throws {
        let food = try #require(foods(["Serving size (fl oz)", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Tea 8 0 0 0 0"]).first)
        #expect(food.servingBasis == "8 fl oz")
        #expect(food.millilitersPerServing == nil)
        #expect(food.gramsPerServing == nil)
        #expect(food.nutrients.count == 4)
    }

    @Test func tableTextServingCarriesExplicitVolume() throws {
        let food = try #require(foods(["Serving", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Milk 100 mL 50 2 0 3"]).first)
        #expect(food.millilitersPerServing == 100)
        var portion = food.portion
        portion.enter(volumeUnit: .milliliters)
        portion.enteredAmount = 180
        #expect(portion.knownAmount(of: "dietaryEnergyConsumed") == 90)
        #expect(portion.knownAmount(of: "dietarySodium") == 0)
        #expect(portion.knownAmount(of: "dietaryFiber") == nil)
    }

    @Test func separatelyPublishedWeightAndVolumeBothSurvive() throws {
        let food = try #require(foods(["Serving size (mL)", "Weight (g)", "Calories", "Fat (g)",
            "Sodium (mg)", "Protein (g)", "Oil 15 14 120 14 0 0"]).first)
        #expect(food.millilitersPerServing == 15)
        #expect(food.gramsPerServing == 14)
        #expect(food.portion.millilitersPerServing == 15)
        #expect(food.portion.gramsPerServing == 14)
    }

    @Test func verifiedTextKeepsVolumeAndOnlyPublishedValues() throws {
        let document = NutritionDocument(url: url, title: "Nutrition", lines: [])
        let line = ModelRowExtractor.Line(number: 0, text: "Milk 100 mL; Calories 50; Protein 3 g; Sodium 0 mg",
                                          document: document)
        let extracted = ModelRowExtractor.Extracted(name: "Milk", serving: "100 mL", nutrients: [
            "dietaryEnergyConsumed": 50, "dietaryProtein": 3, "dietarySodium": 0, "dietaryFatTotal": 0,
        ])
        let food = try #require(ModelRowExtractor.verified(extracted, line: line, brand: "Example", retrieved: fetched))
        #expect(food.millilitersPerServing == 100)
        #expect(food.gramsPerServing == nil)
        #expect(food.nutrients["dietarySodium"] == 0)
        #expect(food.nutrients["dietaryFatTotal"] == nil)
    }

    @Test func sourceCacheRoundTripPreservesZeroAndVolumeAndReadsOlderRecords() throws {
        let food = try #require(foods(["Serving", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Milk 100 mL 50 2 0 3"]).first)
        let data = try JSONEncoder().encode(food)
        let decoded = try JSONDecoder().decode(PublishedFood.self, from: data)
        #expect(decoded == food)
        #expect(decoded.portion.nutrients["dietarySodium"] == 0)
        var oldJSON = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        oldJSON.removeValue(forKey: "millilitersPerServing")
        let old = try JSONDecoder().decode(PublishedFood.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        #expect(old.millilitersPerServing == nil)
        #expect(old.nutrients["dietarySodium"] == 0)
    }

    @Test func brandedMealMatchesPublishedVolumeWithoutEstimatingItFromThePhoto() throws {
        let food = try #require(foods(["Serving", "Calories", "Fat (g)", "Sodium (mg)",
            "Protein (g)", "Milk 100 mL 50 2 N/A 3"]).first)
        let estimate = FoodPortion(name: "Milk", servingSize: "1 cup", nutrients: ["dietaryEnergyConsumed": 120],
                                   servings: 2, isEstimate: true)
        let item = MealPhoto.BrandedItem(name: "Milk", searchTerm: "milk", portions: 2, origin: .photo,
                                         estimate: estimate)
        let meal = BrandedMeal.assemble(items: [item], brand: "Example",
            lookup: .success(LookupResult(foods: ["milk": [food]])), known: [])
        let portion = try #require(meal.portions.first)
        #expect(portion.millilitersPerServing == 100)
        #expect(portion.servings == 2)
        #expect(portion.nutrients["dietarySodium"] == nil)
        #expect(portion.source?.url == url)
        #expect(!portion.isEstimate)
    }
}
