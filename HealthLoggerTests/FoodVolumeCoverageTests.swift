import Foundation
import SwiftData
import Testing
@testable import HealthLogger

@MainActor
struct FoodVolumeTests {
    private var milk: FoodPortion {
        FoodPortion(name: "Milk", servingSize: "100 mL",
                    nutrients: ["dietaryEnergyConsumed": 60, "dietaryProtein": 3.3, "dietarySodium": 0],
                    millilitersPerServing: 100)
    }

    @Test func oneHundredEightyMillilitersScalesEachKnownNutrient() {
        var portion = milk
        portion.enter(volumeUnit: .milliliters)
        portion.enteredAmount = 180
        #expect(abs(portion.servings - 1.8) < 1e-12)
        #expect(portion.amountText == "180 mL")
        #expect(portion.grams == nil)
        for (id, value) in milk.nutrients {
            #expect(abs(portion.amount(of: id) - value * 1.8) < 1e-12)
        }
        #expect(portion.knownAmount(of: "dietarySodium") == 0)
        #expect(portion.knownAmount(of: "dietaryFiber") == nil)
    }

    @Test(arguments: VolumeUnit.allCases)
    func everyVolumeUnitPreservesThePhysicalAmount(unit: VolumeUnit) {
        var portion = milk
        portion.servings = 1.8
        portion.enter(volumeUnit: unit)
        let entered = portion.enteredAmount
        portion.enteredAmount = entered
        #expect(abs(portion.milliliters! - 180) < 1e-10)
        #expect(abs(portion.calories - 108) < 1e-10)
        portion.enter(in: nil)
        #expect(abs(portion.enteredAmount - 1.8) < 1e-12)
        #expect(portion.enteredVolumeUnit == nil)
    }

    @Test func massUSAndImperialOuncesCannotBeConfused() {
        #expect(VolumeUnit.usFluidOunces.milliliters(from: 1) == 29.5735295625)
        #expect(VolumeUnit.imperialFluidOunces.milliliters(from: 1) == 28.4130625)
        #expect(WeightUnit.ounces.grams(from: 1) == 28.349523125)
        #expect(VolumeUnit.usFluidOunces.label != VolumeUnit.imperialFluidOunces.label)
        #expect(VolumeUnit.usFluidOunces.label != WeightUnit.ounces.label)
        var portion = milk
        portion.enter(in: .ounces)
        #expect(portion.enteredWeightUnit == nil)
        #expect(portion.gramsPerServing == nil)
    }

    @Test func separatelyKnownWeightAndVolumeCanBeUsedWithoutInferringDensity() {
        var portion = milk
        portion.gramsPerServing = 103
        portion.enter(volumeUnit: .milliliters)
        portion.enteredAmount = 180
        portion.enter(in: .grams)
        #expect(abs(portion.enteredAmount - 185.4) < 1e-10)
        #expect(portion.enteredVolumeUnit == nil)
        #expect(portion.volumeUnit == nil)
        portion.enter(volumeUnit: .imperialFluidOunces)
        #expect(portion.weightUnit == nil)
        #expect(abs(portion.milliliters! - 180) < 1e-10)
    }

    @Test func volumeReplacementKeepsVolumeOnlyWithACompatibleBasis() {
        var original = milk
        original.enter(volumeUnit: .usFluidOunces)
        original.enteredAmount = 6
        let replacement = original.replaced(by: FoodPortion(name: "Oat milk", nutrients: ["dietaryEnergyConsumed": 90],
                                                              millilitersPerServing: 200))
        #expect(replacement.enteredVolumeUnit == .usFluidOunces)
        #expect(abs(replacement.milliliters! - original.milliliters!) < 1e-10)
        let unmeasured = original.replaced(by: FoodPortion(name: "Soup", nutrients: ["dietaryEnergyConsumed": 60]))
        #expect(unmeasured.servings == 1)
        #expect(unmeasured.enteredVolumeUnit == nil)
        #expect(unmeasured.weightUnit == nil)
    }

    @Test func unknownOrInvalidVolumeStaysInServings() {
        for value: Double? in [nil, 0, -10, .infinity, .nan] {
            var portion = milk
            portion.millilitersPerServing = value
            portion.enter(volumeUnit: .milliliters)
            #expect(!portion.canMeasureVolume)
            #expect(portion.volumeUnit == nil)
            #expect(portion.enteredAmount == 1)
        }
    }

    @Test(arguments: [
        ("1 cup (240 mL)", 240.0), ("100 mL", 100), ("0.5 L", 500), ("1/2 liter", 500),
        ("33 cL", 330), ("2 decilitres", 200), ("1,000 mL", 1000), ("1,5 L", 1500),
        ("2 US fl oz", 59.147059125), ("2 U.S. fluid ounces", 59.147059125),
        ("2 Imperial fl oz", 56.826125), ("2 fl oz (UK)", 56.826125), ("8 fl oz (240 mL)", 240),
    ])
    func readsOnlyExplicitVolume(text: String, expected: Double) {
        #expect(abs((ServingVolume.milliliters(in: text) ?? -1) - expected) < 1e-9)
    }

    @Test(arguments: ["8 fl oz", "2 x 250 mL", "2 × (250 mL)", "250mL x2", "250 mL (x2)",
                      "100-200 mL", "100 to 200 mL", "0 mL", "-2 mL", "1/0 mL", "100 mL / 200 mL"])
    func ambiguousVolumesAreNeverAssumed(text: String) {
        #expect(ServingVolume.reading(of: text) == .ambiguous)
        #expect(ServingVolume.milliliters(in: text) == nil)
    }

    @Test(arguments: ["1 cup", "1 oz", "100 g", "1 bowl", ""])
    func countsAndMassDoNotImplyVolume(text: String) {
        #expect(ServingVolume.reading(of: text) == .unstated)
    }

    @Test func oldSavedFoodsOfferAReviewedVolumeWithoutAutomaticallyUsingIt() {
        let draft = FoodDraft(name: "Milk", servingSize: "100 mL", nutrients: ["dietaryEnergyConsumed": 60])
        #expect(draft.statedServingVolume == 100)
        #expect(Food(draft).millilitersPerServing == nil)
        #expect(Food(draft).portion.enteredVolumeUnit == nil)
        #expect(FoodDraft(servingSize: "8 fl oz").statedServingVolume == nil)
    }

    @Test func volumeAndZeroNutrientsSurviveLocalStorage() throws {
        let container = try ModelContainer(for: Food.self, Recipe.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        let context = ModelContext(container)
        let food = Food(FoodDraft(name: "Milk", servingSize: "100 mL", millilitersPerServing: 100,
                                 nutrients: ["dietaryEnergyConsumed": 60, "dietarySodium": 0]))
        context.insert(food)
        try context.save()
        let read = try #require(try context.fetch(FetchDescriptor<Food>()).first)
        #expect(read.millilitersPerServing == 100)
        #expect(read.draft.millilitersPerServing == 100)
        #expect(read.portion.enteredVolumeUnit == .milliliters)
        #expect(read.nutrients["dietarySodium"] == 0)
        #expect(read.nutrients["dietaryFiber"] == nil)
    }
}

@MainActor
struct FoodCoverageTests {
    private let sodium = "dietarySodium"

    @Test func explicitZeroIsValidButAnUnknownFoodIsNot() {
        let draft = FoodDraft(name: "Unsalted", nutrients: [sodium: 0])
        #expect(draft.isValid)
        #expect(Food(draft).draft == draft)
        #expect(!FoodDraft(name: "Unknown").isValid)
        #expect(!FoodDraft(name: "Invalid", nutrients: [sodium: -.infinity]).isValid)
        #expect(!FoodDraft(name: "Invalid", nutrients: [sodium: .nan]).isValid)
    }

    @Test func totalsDistinguishPartialZeroAndUnknownAndIgnoreExcludedIngredients() {
        let portions = [FoodPortion(name: "Broth", nutrients: [sodium: 200]),
                        FoodPortion(name: "Rice", nutrients: ["dietaryEnergyConsumed": 100]),
                        FoodPortion(name: "Vegetables", nutrients: ["dietaryEnergyConsumed": 40]),
                        FoodPortion(name: "Left out", nutrients: [:], servings: 0)]
        #expect(FoodNutrition.totals(portions)[sodium] == 200)
        #expect(FoodNutrition.coverage(of: sodium, in: portions) == NutrientCoverage(known: 1, missing: 2))
        #expect(FoodNutrition.coverage(of: sodium, in: portions).isPartial)
        #expect(FoodNutrition.coverage(of: "dietaryFiber", in: portions).isUnavailable)
        #expect(FoodNutrition.totals(portions)["dietaryFiber"] == nil)
        #expect(FoodNutrition.coverage(of: sodium, in: []).isUnavailable)
        let zero = [FoodPortion(name: "No sodium", nutrients: [sodium: 0])]
        #expect(FoodNutrition.totals(zero)[sodium] == 0)
        #expect(!FoodNutrition.coverage(of: sodium, in: zero).isUnavailable)
    }

    @Test func recipeCoverageSurvivesCollapseScalingAndAnotherRecipe() throws {
        let ingredients = [FoodPortion(name: "Broth", nutrients: [sodium: 300]),
                           FoodPortion(name: "Rice", nutrients: ["dietaryEnergyConsumed": 100]),
                           FoodPortion(name: "Vegetables", nutrients: ["dietaryEnergyConsumed": 40])]
        let recipe = Recipe(name: "Soup", servings: 3, ingredients: ingredients)
        #expect(recipe.portion.nutrients[sodium] == 100)
        #expect(recipe.portion.coverage(of: sodium) == NutrientCoverage(known: 1, missing: 2))
        #expect(recipe.portion.millilitersPerServing == nil)
        var restored = try JSONDecoder().decode(FoodPortion.self, from: JSONEncoder().encode(recipe.portion))
        restored.servings = 2
        #expect(restored.knownAmount(of: sodium) == 200)
        #expect(restored.coverage(of: sodium) == NutrientCoverage(known: 1, missing: 2))
        let next = Recipe(name: "Lunch", servings: 1,
                          ingredients: [restored, FoodPortion(name: "Bread", nutrients: [sodium: 0])])
        #expect(next.portion.coverage(of: sodium) == NutrientCoverage(known: 2, missing: 2))
        #expect(next.portion.nutrients[sodium] == 200)
    }

    @Test func aRecipeWithOnlyExcludedIngredientsDoesNotInventAMissingIngredient() {
        let recipe = Recipe(name: "Excluded", servings: 1,
                            ingredients: [FoodPortion(name: "Left out", nutrients: [:], servings: 0)])
        #expect(recipe.portion.coverage(of: sodium) == NutrientCoverage(known: 0, missing: 0))
        #expect(recipe.portion.nutrients[sodium] == nil)
    }

    @Test func recipesRetainVolumeIngredientsButDoNotInventFinishedVolume() throws {
        let ingredient = FoodPortion(name: "Milk", nutrients: [sodium: 0], servings: 1.8,
                                     millilitersPerServing: 100, volumeUnit: .milliliters)
        let recipe = Recipe(name: "Drink", servings: 2, ingredients: [ingredient])
        #expect(recipe.ingredients == [ingredient])
        #expect(recipe.ingredients.first?.amountText == "180 mL")
        #expect(recipe.portion.millilitersPerServing == nil)
        #expect(recipe.portion.nutrients[sodium] == 0)
        #expect(recipe.portion.nutrients["dietaryEnergyConsumed"] == nil)
        #expect(recipe.summary.contains("Calories unavailable"))
        let restored = try JSONDecoder().decode(FoodPortion.self, from: JSONEncoder().encode(ingredient))
        #expect(restored == ingredient)
    }

    @Test func legacySnapshotKeepsKnownValuesAndUnknownCoverage() throws {
        let data = Data("""
            {"id":"6F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Old soup","brand":"",
             "servingSize":"1 serving","nutrients":{"dietarySodium":150},"servings":2}
            """.utf8)
        let old = try JSONDecoder().decode(FoodPortion.self, from: data)
        #expect(old.knownAmount(of: sodium) == 300)
        #expect(old.knownAmount(of: "dietaryFiber") == nil)
        #expect(old.coverageIsUncertain)
        #expect(old.coverage(of: sodium).isUncertain)
        #expect(old.coverage(of: "dietaryFiber").missing == 0)
        #expect(old.coverage(of: "dietaryFiber").isUnavailable)
        #expect(old.millilitersPerServing == nil)
        let recipe = Recipe(name: "Leftovers", servings: 1, ingredients: [old])
        #expect(recipe.portion.coverage(of: sodium).isUncertain)
    }

    @Test func mixedVersionDroppedFieldsFallBackWithoutChangingNutrients() throws {
        let ingredient = FoodPortion(name: "Milk", nutrients: [sodium: 0], servings: 1.8,
                                     millilitersPerServing: 100, volumeUnit: .milliliters)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ingredient)) as? [String: Any])
        json.removeValue(forKey: "millilitersPerServing")
        json.removeValue(forKey: "volumeUnit")
        json.removeValue(forKey: "coverageIsUncertain")
        let restored = try JSONDecoder().decode(FoodPortion.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.nutrients == ingredient.nutrients)
        #expect(restored.servings == ingredient.servings)
        #expect(!restored.canMeasureVolume)
        #expect(restored.coverageIsUncertain)
    }

    @Test func unreadableOptionalMetadataDoesNotDiscardTheIngredient() throws {
        let data = Data("""
            {"id":"6F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Milk","brand":"",
             "servingSize":"100 mL","nutrients":{"dietarySodium":0},"servings":2,
             "millilitersPerServing":"unknown","volumeUnit":"future-unit","nutrientCoverage":"unreadable"}
            """.utf8)
        let restored = try JSONDecoder().decode(FoodPortion.self, from: data)
        #expect(restored.nutrients[sodium] == 0)
        #expect(restored.millilitersPerServing == nil)
        #expect(restored.volumeUnit == nil)
        #expect(restored.nutrientCoverage == nil)
        #expect(restored.coverageIsUncertain)
    }
}
