import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import HealthLogger

/// Open Food Facts product responses, shaped like the ones it returned for these barcodes on October 3, 2026.
@MainActor
struct OpenFoodFactsTests {
    private func draft(_ product: String) throws -> FoodDraft {
        try #require(try FoodDatabase.draft(from: Data(#"{"product":\#(product),"status":1}"#.utf8), barcode: "123"))
    }

    @Test func aDrinkServedInMillilitersHasNoWeight() throws {
        // 5449000000996
        let draft = try draft("""
            {"product_name":"Coca-Cola Original","brands":"Coca-Cola","serving_size":"1 portion (330 ml)",
             "serving_quantity":330,"serving_quantity_unit":"ml","quantity":"330 ml","product_quantity_unit":"ml",
             "nutriments":{"energy-kcal_serving":139,"sugars_serving":35,"energy-kcal_100g":42,"sugars_100g":10.6}}
            """)
        #expect(draft.servingSize == "1 portion (330 ml)")
        #expect(draft.gramsPerServing == nil)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 139)
    }

    @Test func aGramServingGivesItsWeight() throws {
        // 0028400090896
        let draft = try draft("""
            {"product_name":"Nacho Cheese","brands":"Doritos","serving_size":"1 package (28 g)",
             "serving_quantity":28,"serving_quantity_unit":"g","quantity":"1 oz (28.3 g)","product_quantity_unit":"g",
             "nutriments":{"energy-kcal_serving":150,"fat_serving":8,"energy-kcal_100g":536,"fat_100g":28.6}}
            """)
        #expect(draft.servingSize == "1 package (28 g)")
        #expect(draft.gramsPerServing == 28)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 150)
    }

    @Test func theDatabasesOwnGramServingIsUsedWhenTheTextHasNone() throws {
        let draft = try draft("""
            {"product_name":"Protein Bar","serving_size":"1 bar","serving_quantity":45,"serving_quantity_unit":"g",
             "nutriments":{"energy-kcal_serving":190,"proteins_serving":20}}
            """)
        #expect(draft.gramsPerServing == 45)
    }

    /// A serving of several pieces isn't read as one piece's weight, and the database's total isn't taken without
    /// the printed one to confirm it, so 30 g of it can't log a whole 60 g serving's nutrition.
    @Test func aMultipleServingHasNoWeight() throws {
        let draft = try draft("""
            {"product_name":"Crackers","serving_size":"2 x 30 g","serving_quantity":60,"serving_quantity_unit":"g",
             "nutriments":{"energy-kcal_serving":240,"proteins_serving":6}}
            """)
        #expect(draft.servingSize == "2 x 30 g")
        #expect(draft.gramsPerServing == nil)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 240)
    }

    @Test func aPrintedWeightTheDatabaseDisagreesWithIsntUsed() throws {
        let draft = try draft("""
            {"product_name":"Bar","serving_size":"1 bar (30 g)","serving_quantity":45,"serving_quantity_unit":"g",
             "nutriments":{"energy-kcal_serving":190,"proteins_serving":20}}
            """)
        #expect(draft.gramsPerServing == nil)
    }

    @Test func aPrintedWeightTheDatabaseRoundsIsUsed() throws {
        let draft = try draft("""
            {"product_name":"Chips","serving_size":"1 oz (28.35 g)","serving_quantity":28.4,"serving_quantity_unit":"g",
             "nutriments":{"energy-kcal_serving":150,"fat_serving":10}}
            """)
        #expect(draft.gramsPerServing == 28.35)
    }

    /// Per 100 g for a product sold by weight, like Nutella (3017620422003), which lists no serving.
    @Test func per100GramsForAFoodSoldByWeight() throws {
        let draft = try draft("""
            {"product_name":"Nutella","brands":"Ferrero","quantity":"400 g e","product_quantity":400,
             "product_quantity_unit":"g","serving_quantity_unit":"g",
             "nutriments":{"energy-kcal_100g":539,"fat_100g":30.9,"sugars_100g":56.3}}
            """)
        #expect(draft.servingSize == "100 g")
        #expect(draft.gramsPerServing == 100)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 539)
    }

    /// Open Food Facts' per-100 values are per 100 mL for drinks, which mustn't gain a 100 g weight.
    @Test func per100MillilitersForADrink() throws {
        let draft = try draft("""
            {"product_name":"Orange Juice","quantity":"1 l","nutriments":{"energy-kcal_100g":45,"sugars_100g":9}}
            """)
        #expect(draft.servingSize == "100 mL")
        #expect(draft.gramsPerServing == nil)
    }

    @Test func per100OfAnUnknownUnitHasNoWeight() throws {
        let draft = try draft("""
            {"product_name":"Mystery","nutriments":{"energy-kcal_100g":120,"proteins_100g":3}}
            """)
        #expect(draft.servingSize == FoodDatabase.per100Serving)
        #expect(draft.gramsPerServing == nil)
        // And the food editor doesn't offer that "100 g" as a weight either.
        #expect(draft.statedServingWeight == nil)
    }

    @Test func noProductIsNil() throws {
        #expect(try FoodDatabase.draft(from: Data(#"{"status":0}"#.utf8), barcode: "123") == nil)
    }
}

@MainActor
struct NutritionLabelWeightTests {
    /// Lines a label photo might give, one per row, top to bottom.
    private func label(_ lines: [String]) -> NutritionLabel? {
        NutritionLabel(lines: lines.enumerated().map { index, text in
            NutritionLabel.TextLine(text: text, box: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.05, width: 0.8, height: 0.03))
        })
    }

    @Test func aUSLabelGivesTheGramsInItsServing() throws {
        let label = try #require(label(["Serving size 2/3 cup (55g)", "Calories 230", "Total Fat 8g", "Protein 3g"]))
        var draft = FoodDraft()
        draft.apply(label)
        #expect(draft.servingSize == "2/3 cup (55g)")
        #expect(draft.gramsPerServing == 55)
    }

    @Test func aServingInMillilitersHasNoWeight() throws {
        let label = try #require(label(["Serving size 1 cup (240mL)", "Calories 110", "Total Sugars 22g", "Protein 2g"]))
        var draft = FoodDraft(gramsPerServing: 30)
        draft.apply(label)
        #expect(draft.servingSize == "1 cup (240 mL)")
        // The new serving replaces the old one, and with it the old weight.
        #expect(draft.gramsPerServing == nil)
    }

    /// Rescanning a food's label for a different serving replaces all its nutrition: an amount the new scan missed
    /// isn't kept from the old serving.
    @Test func rescanningForADifferentServingClearsWhatItDoesntList() throws {
        let label = try #require(label(["Serving size 1 bar (50 g)", "Calories 200", "Protein 10g"]))
        var draft = FoodDraft(servingSize: "100 g", gramsPerServing: 100, nutrients: [
            "dietaryEnergyConsumed": 400, "dietaryProtein": 20, "dietaryFatTotal": 10,
        ])
        draft.apply(label)
        #expect(draft.gramsPerServing == 50)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 200)
        #expect(draft.nutrients["dietaryProtein"] == 10)
        #expect(draft.nutrients["dietaryFatTotal"] == nil)
    }

    /// For the same serving, an amount the scan missed is still right, so it stays.
    @Test func rescanningTheSameServingKeepsWhatItDoesntList() throws {
        let label = try #require(label(["Serving size 2/3 cup (55g)", "Calories 240", "Protein 4g"]))
        var draft = FoodDraft(servingSize: "2/3 cup (55g)", gramsPerServing: 55, nutrients: [
            "dietaryEnergyConsumed": 230, "dietaryProtein": 3, "dietaryFatTotal": 8,
        ])
        draft.apply(label)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 240)
        #expect(draft.nutrients["dietaryProtein"] == 4)
        #expect(draft.nutrients["dietaryFatTotal"] == 8)
    }

    @Test func aEuropeanLabelPer100GramsScaledToItsServing() throws {
        let label = try #require(label(["Nutrition per 100 g", "Serving size 1 bar (30 g)", "Energy 1046 kJ / 250 kcal",
                                        "Fat 10 g", "Protein 5 g"]))
        var draft = FoodDraft()
        draft.apply(label)
        #expect(draft.gramsPerServing == 30)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 75)
    }

    @Test func aEuropeanLabelWithoutAServingIsPer100Grams() throws {
        let label = try #require(label(["Typical values per 100g", "Energy 1046 kJ / 250 kcal", "Fat 10 g", "Protein 5 g"]))
        var draft = FoodDraft()
        draft.apply(label)
        #expect(draft.servingSize == "100 g")
        #expect(draft.gramsPerServing == 100)
    }

    @Test func aEuropeanDrinkPer100Milliliters() throws {
        let label = try #require(label(["Per 100 ml", "Energy 180 kJ / 42 kcal", "Sugars 10.6 g", "Salt 0 g"]))
        var draft = FoodDraft()
        draft.apply(label)
        #expect(draft.servingSize == "100 mL")
        #expect(draft.gramsPerServing == nil)
    }
}

@MainActor
struct SavedFoodWeightTests {
    private let context = ModelContext(try! ModelContainer(
        for: Food.self, Recipe.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))

    @Test func aFoodSavesItsWeight() {
        let food = Food(FoodDraft(name: "Granola", servingSize: "100 g", gramsPerServing: 100,
                                  nutrients: ["dietaryEnergyConsumed": 400]))
        context.insert(food)
        #expect(food.gramsPerServing == 100)
        #expect(food.portion.gramsPerServing == 100)
        // A serving that's just a weight starts out entered in grams.
        #expect(food.portion.weightUnit == .grams)
        #expect(food.draft.gramsPerServing == 100)
    }

    @Test func aServingWithAWeightStartsInServings() {
        let food = Food(FoodDraft(name: "Bar", servingSize: "1 bar (30 g)", gramsPerServing: 30,
                                  nutrients: ["dietaryEnergyConsumed": 120]))
        #expect(food.portion.weightUnit == nil)
        #expect(food.portion.canWeigh)
    }

    @Test func aZeroWeightIsNoWeight() {
        let food = Food(FoodDraft(name: "Bar", gramsPerServing: 0, nutrients: ["dietaryEnergyConsumed": 120]))
        #expect(food.gramsPerServing == nil)
        #expect(!food.portion.canWeigh)
    }

    /// Foods saved before 1.1 have no weight until edited; the editor offers one only when the text states it.
    @Test func theEditorOffersAStatedWeight() {
        #expect(FoodDraft(servingSize: "1 bar (30 g)").statedServingWeight == 30)
        #expect(FoodDraft(servingSize: "1 cup").statedServingWeight == nil)
        #expect(FoodDraft(servingSize: "1 bar (30 g)", gramsPerServing: 30).statedServingWeight == nil)
        // The barcode lookup's old fallback, which may have been per 100 mL.
        #expect(FoodDraft(servingSize: "100 g", barcode: "5000112637922").statedServingWeight == nil)
        #expect(FoodDraft(servingSize: "100 g").statedServingWeight == 100)
    }

    /// A food logged before 1.1 picks up the weight of the saved food it was logged from, only on the same basis.
    @Test func aRecentFromBefore11PicksUpAMatchingWeight() {
        let food = Food(FoodDraft(name: "Granola", brand: "Bear", servingSize: "1/2 cup (45 g)", gramsPerServing: 45,
                                  nutrients: ["dietaryEnergyConsumed": 200, "dietaryProtein": 5]))
        // As read back from Health: totals over servings, a little off in the last digits.
        let logged = FoodPortion(name: "granola", brand: "Bear", servingSize: "1/2 cup (45 g)",
                                 nutrients: ["dietaryEnergyConsumed": 600.0000000001 / 3, "dietaryProtein": 15.0 / 3],
                                 servings: 3)
        let weighed = logged.withServingWeight(from: [food])
        #expect(weighed.gramsPerServing == 45)
        #expect(weighed.servings == 3)
        #expect(weighed.weightUnit == nil)

        var changed = logged
        changed.nutrients["dietaryEnergyConsumed"] = 190
        #expect(changed.withServingWeight(from: [food]).gramsPerServing == nil)
        var otherServing = logged
        otherServing.servingSize = "1 cup"
        #expect(otherServing.withServingWeight(from: [food]).gramsPerServing == nil)
        var otherBrand = logged
        otherBrand.brand = "Kind"
        #expect(otherBrand.withServingWeight(from: [food]).gramsPerServing == nil)
    }
}

@MainActor
struct RecipeWeightTests {
    private let context = ModelContext(try! ModelContainer(
        for: Food.self, Recipe.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))

    /// Ready when: recipes created before the upgrade show unchanged per-serving nutrition.
    @Test func aRecipeFromBuild25IsUnchanged() throws {
        let build25 = try JSONDecoder().decode([FoodPortion].self, from: Data("""
            [{"id":"6F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Oats","brand":"","servingSize":"1/2 cup",
              "nutrients":{"dietaryEnergyConsumed":150,"dietaryProtein":5},"servings":2},
             {"id":"7F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Milk","brand":"","servingSize":"1 cup",
              "nutrients":{"dietaryEnergyConsumed":100,"dietaryProtein":8},"servings":1}]
            """.utf8))
        let recipe = Recipe(name: "Porridge", servings: 2, ingredients: build25)
        context.insert(recipe)
        #expect(recipe.ingredients.count == 2)
        #expect(recipe.portion.nutrients["dietaryEnergyConsumed"] == 200)
        #expect(recipe.portion.nutrients["dietaryProtein"] == 9)
        #expect(recipe.portion.servingSize == "1/2 recipe")
        #expect(recipe.portion.gramsPerServing == nil)
    }

    /// Ready when: a recipe with weighed ingredients totals its ingredients' scaled nutrients.
    @Test func weighedIngredientsTotalTheirScaledNutrients() {
        var oats = FoodPortion(name: "Oats", servingSize: "40 g", nutrients: ["dietaryEnergyConsumed": 150,
                                                                              "dietaryProtein": 5], gramsPerServing: 40)
        oats.enter(in: .grams)
        oats.enteredAmount = 60
        var berries = FoodPortion(name: "Blueberries", servingSize: "1 cup (148 g)",
                                  nutrients: ["dietaryEnergyConsumed": 85], gramsPerServing: 148)
        berries.enter(in: .ounces)
        berries.enteredAmount = 2
        let recipe = Recipe(name: "Bowl", servings: 1, ingredients: [oats, berries])
        context.insert(recipe)
        // Stored and read back with their weights.
        #expect(recipe.ingredients.map(\.weightUnit) == [.grams, .ounces])
        #expect(recipe.ingredients[0].amountText == "60 g")
        let calories = 150 * 60 / 40 + 85 * (2 * WeightUnit.gramsPerOunce) / 148
        #expect(abs(recipe.portion.calories - calories) < 1e-9)
        #expect(abs(recipe.portion.nutrients["dietaryProtein"]! - 7.5) < 1e-9)
    }
}
