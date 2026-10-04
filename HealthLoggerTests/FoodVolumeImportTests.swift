import CoreGraphics
import Foundation
import Testing
@testable import HealthLogger

@MainActor
struct FoodVolumeImportTests {
    private func product(_ json: String) throws -> FoodDraft {
        try #require(try FoodDatabase.draft(from: Data("{\"product\":\(json)}".utf8), barcode: "123"))
    }

    private func label(_ rows: [String]) throws -> NutritionLabel {
        try #require(NutritionLabel(lines: rows.enumerated().map { index, text in
            NutritionLabel.TextLine(text: text,
                box: CGRect(x: 0.1, y: 0.9 - Double(index) * 0.05, width: 0.8, height: 0.03))
        }))
    }

    @Test func barcodeMillilitersKeepTheirServingAndKnownZero() throws {
        let draft = try product("""
            {"product_name":"Juice","serving_size":"1 bottle (180 mL)","serving_quantity":180,
             "serving_quantity_unit":"ml","nutriments":{"energy-kcal_serving":80,"fat_serving":0}}
            """)
        #expect(draft.millilitersPerServing == 180)
        #expect(draft.gramsPerServing == nil)
        #expect(draft.nutrients["dietaryFatTotal"] == 0)
        #expect(draft.nutrients["dietarySodium"] == nil)
        #expect(Food(draft).draft.nutrients["dietaryFatTotal"] == 0)
    }

    @Test func barcodeVolumeCanComeFromTheExplicitDatabaseServingUnit() throws {
        let draft = try product("""
            {"product_name":"Milk","serving_size":"1 bottle","serving_quantity":0.25,
             "serving_quantity_unit":"l","nutriments":{"energy-kcal_serving":110}}
            """)
        #expect(draft.millilitersPerServing == 250)
        #expect(draft.gramsPerServing == nil)
    }

    @Test func barcodeConflictingAmountsRemainServingBased() throws {
        let draft = try product("""
            {"product_name":"Milk","serving_size":"180 mL","serving_quantity":240,
             "serving_quantity_unit":"ml","nutriments":{"energy-kcal_serving":110}}
            """)
        #expect(draft.millilitersPerServing == nil)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 110)
    }

    @Test func barcodeAmbiguousFluidOuncesAreNotResolvedByGuessing() throws {
        let draft = try product("""
            {"product_name":"Milk","serving_size":"8 fl oz","serving_quantity":240,
             "serving_quantity_unit":"ml","nutriments":{"energy-kcal_serving":110}}
            """)
        #expect(draft.millilitersPerServing == nil)
        #expect(draft.gramsPerServing == nil)
    }

    @Test func barcodeExplicitFluidOunceSystemsStayDistinct() throws {
        let us = try product("""
            {"product_name":"Milk","serving_size":"8 US fl oz","nutriments":{"energy-kcal_serving":110}}
            """)
        let imperial = try product("""
            {"product_name":"Milk","serving_size":"8 Imperial fl oz","nutriments":{"energy-kcal_serving":110}}
            """)
        #expect(abs(try #require(us.millilitersPerServing) - 236.5882365) < 1e-6)
        #expect(abs(try #require(imperial.millilitersPerServing) - 227.3045) < 1e-6)
        #expect(us.gramsPerServing == nil)
        #expect(imperial.gramsPerServing == nil)
    }

    @Test func barcodePer100MillilitersScaleWithoutAssumingDensity() throws {
        let draft = try product("""
            {"product_name":"Juice","quantity":"1 l","nutriments":{"energy-kcal_100g":50,"fat_100g":0}}
            """)
        #expect(draft.servingSize == "100 mL")
        #expect(draft.millilitersPerServing == 100)
        #expect(draft.gramsPerServing == nil)
        var portion = Food(draft).portion
        portion.enter(volumeUnit: .milliliters)
        portion.enteredAmount = 180
        #expect(portion.calories == 90)
        #expect(portion.knownAmount(of: "dietaryFatTotal") == 0)
        #expect(portion.knownAmount(of: "dietarySodium") == nil)
    }

    @Test func barcodePer100GramsNeverBecomeVolume() throws {
        let draft = try product("""
            {"product_name":"Sauce","quantity":"200 g","nutriments":{"energy-kcal_100g":50}}
            """)
        #expect(draft.gramsPerServing == 100)
        #expect(draft.millilitersPerServing == nil)
    }

    @Test func conflictingBarcodePackageUnitsEstablishNeitherVolumeNorWeight() throws {
        let draft = try product("""
            {"product_name":"Sauce","quantity":"200 g","product_quantity_unit":"ml",
             "nutriments":{"energy-kcal_100g":50}}
            """)
        #expect(draft.gramsPerServing == nil)
        #expect(draft.millilitersPerServing == nil)
        #expect(draft.statedServingWeight == nil)
        #expect(draft.statedServingVolume == nil)
    }

    @Test func barcodeInvalidNumbersRemainUnknown() throws {
        let draft = try product("""
            {"product_name":"Drink","quantity":"100 ml",
             "nutriments":{"energy-kcal_100g":0,"sodium_100g":-1,"fat_100g":"nan","proteins_100g":"inf"}}
            """)
        #expect(draft.nutrients == ["dietaryEnergyConsumed": 0])
        #expect(draft.isValid)
    }

    @Test func perVolumeLabelScalesItsKnownNutrients() throws {
        let scanned = try label(["Nutrition per 100 mL", "Serving size 180 mL", "Calories 50",
                                 "Fat 0 g", "Protein 2 g"])
        var draft = FoodDraft()
        draft.apply(scanned)
        #expect(draft.millilitersPerServing == 180)
        #expect(draft.gramsPerServing == nil)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 90)
        #expect(draft.nutrients["dietaryProtein"] == 3.6)
        #expect(draft.nutrients["dietaryFatTotal"] == 0)
        #expect(draft.nutrients["dietarySodium"] == nil)
    }

    @Test func perVolumeLabelConvertsOnlyExplicitFluidOunces() throws {
        var explicit = FoodDraft()
        explicit.apply(try label(["Nutrition per 100 mL", "Serving size 1 US fl oz", "Calories 50", "Fat 0 g"]))
        #expect(abs(try #require(explicit.millilitersPerServing) - 29.5735295625) < 1e-6)
        #expect(explicit.nutrients["dietaryEnergyConsumed"] == 14.8)
        var ambiguous = FoodDraft()
        ambiguous.apply(try label(["Nutrition per 100 mL", "Serving size 1 fl oz", "Calories 50", "Fat 0 g"]))
        #expect(ambiguous.servingSize == "100 mL")
        #expect(ambiguous.millilitersPerServing == 100)
        #expect(ambiguous.nutrients["dietaryEnergyConsumed"] == 50)
    }

    @Test func perMassLabelWithVolumeServingKeepsTheMassColumn() throws {
        var draft = FoodDraft()
        draft.apply(try label(["Nutrition per 100 g", "Serving size 180 mL", "Calories 50", "Protein 2 g"]))
        #expect(draft.servingSize == "100 g")
        #expect(draft.gramsPerServing == 100)
        #expect(draft.millilitersPerServing == nil)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 50)
    }

    @Test func changingLabelServingReplacesVolumeAndClearsOldNutrition() throws {
        var draft = FoodDraft(servingSize: "100 mL", millilitersPerServing: 100,
                              nutrients: ["dietaryEnergyConsumed": 40, "dietarySodium": 0])
        draft.apply(try label(["Serving size 180 mL", "Calories 90", "Protein 2 g"]))
        #expect(draft.millilitersPerServing == 180)
        #expect(draft.nutrients["dietarySodium"] == nil)
        draft.apply(try label(["Serving size 20 g", "Calories 60", "Protein 1 g"]))
        #expect(draft.gramsPerServing == 20)
        #expect(draft.millilitersPerServing == nil)
    }

    @Test func equivalentLabelVolumeKeepsPreviouslyKnownNutrition() throws {
        var draft = FoodDraft(servingSize: "0.1 L", millilitersPerServing: 100,
                              nutrients: ["dietaryEnergyConsumed": 40, "dietarySodium": 0])
        draft.apply(try label(["Serving size 100 mL", "Calories 50", "Protein 2 g"]))
        #expect(draft.nutrients["dietarySodium"] == 0)
        #expect(draft.nutrients["dietaryEnergyConsumed"] == 50)
    }

    @Test func legacyBarcodeFallbackDoesNotProveTheSameLabelBasis() throws {
        var draft = FoodDraft(servingSize: FoodDatabase.per100Serving, barcode: "123",
                              nutrients: ["dietaryEnergyConsumed": 40, "dietarySodium": 0])
        draft.apply(try label(["Nutrition per 100 g", "Calories 50", "Protein 2 g"]))
        #expect(draft.gramsPerServing == 100)
        #expect(draft.millilitersPerServing == nil)
        #expect(draft.nutrients["dietarySodium"] == nil)
    }

    @Test func photoUnknownsAreOmittedAndKnownZerosStayEstimates() {
        let portion = estimatedPortion(name: "tea", servingSize: "240 mL", servings: 1, calories: 0,
            protein: -1, carbohydrates: -1, fat: 0, sugar: .nan, fiber: .infinity, caffeine: -1)
        #expect(portion.nutrients == ["dietaryEnergyConsumed": 0, "dietaryFatTotal": 0])
        #expect(portion.isEstimate)
        #expect(portion.millilitersPerServing == nil)
        #expect(portion.gramsPerServing == nil)
    }
}
