import Foundation
import Testing
@testable import HealthLogger

/// A food defined per 100 g, like most European labels and Open Food Facts' fallback.
private func per100g(_ name: String = "Granola") -> FoodPortion {
    FoodPortion(name: name, servingSize: "100 g", nutrients: [
        "dietaryEnergyConsumed": 400, "dietaryProtein": 10, "dietaryCarbohydrates": 64, "dietaryFatTotal": 12,
        "dietarySodium": 90,
    ], gramsPerServing: 100)
}

/// What the Nutrition screen shows for a nutrient: kcal and mg whole, grams to a tenth.
private func displayed(_ id: String, _ value: Double) -> String {
    let digits = Metric.metric(id: id)?.unitOptions.first?.fractionDigits ?? 0
    return value.formatted(.number.precision(.fractionLength(0...digits)))
}

@MainActor
struct ServingWeightTests {
    @Test(arguments: [
        ("1 bar (30 g)", 30.0), ("30g", 30), ("3/4 cup (170 g)", 170), ("100 g", 100), ("1 oz (28 g)", 28),
        ("28g/1oz", 28), ("Serving 30,5 g", 30.5), ("1,5 kg", 1500), ("1 package (28 g)", 28), ("2 grams", 2),
        ("1 bar (30 g) = 30 g", 30), ("1/2 g", 0.5), (".5 g", 0.5), ("1 1/2 g", 1.5), ("1/2 cup (60 g)", 60),
        ("1/2 kg", 500), ("1,000 g", 1000), ("1 / 2 g", 0.5), ("1 box (30 g)", 30), ("1 bar (30 g)*", 30),
        ("1 cup (240 mL) 30 g", 30),
    ])
    func readsAStatedGramWeight(text: String, grams: Double) {
        #expect(ServingWeight.grams(in: text) == grams)
    }

    /// Volumes aren't weights, bare ounces may be fluid ounces, and two different weights are ambiguous.
    @Test(arguments: ["250 mL", "1 cup (240mL)", "8 fl oz", "1 oz", "1 cup", "", "200 mg", "0 g",
                      "1 portion (330 ml)", "2 x 15 g (30 g)", "1 medium"])
    func neverGuessesAWeight(text: String) {
        #expect(ServingWeight.grams(in: text) == nil)
    }

    /// A multiple or a range is read in full, as no one weight, rather than as its last number.
    @Test(arguments: ["2 x 30 g", "2x30g", "2 × 30 g", "30 g x 2", "2 biscuits x 15 g", "20-30 g", "20 – 30 g",
                      "20 to 30 g", "1.5-2 g", "1/0 g", "2 x (30 g)", "30 g (x2)", "30 g (2x)", "2*15 g",
                      ".5-1 g"])
    func multiplesAndRangesAreAmbiguous(text: String) {
        #expect(ServingWeight.reading(of: text) == .ambiguous)
    }

    /// A volume is read the same way, for labels whose nutrition is per 100 mL.
    @Test func readsAStatedVolume() {
        #expect(ServingWeight.milliliters(in: "1 cup (240mL)") == 240)
        #expect(ServingWeight.milliliters(in: "1/2 can (165 ml)") == 165)
        #expect(ServingWeight.milliliters(in: "2 x 250 mL") == nil)
        #expect(ServingWeight.milliliters(in: "1 bar (30 g)") == nil)
    }

    @Test func noWeightIsUnstated() {
        #expect(ServingWeight.reading(of: "1 cup (240 mL)") == .unstated)
        #expect(ServingWeight.reading(of: "1 bar") == .unstated)
    }

    @Test func weightOnlyServings() {
        #expect(ServingWeight.isWeightOnly("100 g"))
        #expect(ServingWeight.isWeightOnly(" 30g "))
        #expect(!ServingWeight.isWeightOnly("1 bar (30 g)"))
        #expect(!ServingWeight.isWeightOnly("100 mL"))
    }
}

@MainActor
struct WeighedPortionTests {
    /// Ready when: a 35 g portion of a food defined per 100 g logs 0.35 times each nutrient.
    @Test func thirtyFiveGramsIsPointThreeFiveServings() {
        var portion = per100g()
        portion.enter(in: .grams)
        portion.enteredAmount = 35
        #expect(abs(portion.servings - 0.35) < 1e-12)
        for (id, perServing) in portion.nutrients {
            #expect(abs(portion.amount(of: id) - perServing * 0.35) < 1e-9, "\(id)")
        }
        #expect(abs(portion.calories - 140) < 1e-9)
        #expect(portion.amountText == "35 g")
        #expect(portion.summary == "35 g · 140 kcal")
    }

    /// Ready when: the same portion entered in ounces logs the same nutrients to displayed precision.
    @Test(arguments: [35.0, 56.7, 100, 250, 12.5])
    func ouncesMatchGramsToDisplayedPrecision(grams: Double) {
        var byGrams = per100g()
        byGrams.enter(in: .grams)
        byGrams.enteredAmount = grams
        var byOunces = per100g()
        byOunces.enter(in: .ounces)
        byOunces.enteredAmount = grams / WeightUnit.gramsPerOunce
        for id in byGrams.nutrients.keys {
            #expect(displayed(id, byGrams.amount(of: id)) == displayed(id, byOunces.amount(of: id)), "\(id) at \(grams) g")
            #expect(abs(byGrams.amount(of: id) - byOunces.amount(of: id)) < 1e-9)
        }
    }

    @Test func twoOuncesIsTheSameAsItsGrams() {
        var byOunces = per100g()
        byOunces.enter(in: .ounces)
        byOunces.enteredAmount = 2
        #expect(abs(byOunces.grams! - 56.69904625) < 1e-9)
        #expect(byOunces.amountText == "2 oz")
    }

    @Test func switchingUnitsKeepsTheAmountEaten() {
        var portion = per100g()
        portion.servings = 0.35
        portion.enter(in: .ounces)
        #expect(abs(portion.servings - 0.35) < 1e-12)
        #expect(portion.amountText == "1.23 oz")
        portion.enter(in: nil)
        #expect(portion.amountText == "0.35 × 100 g")
    }

    /// A food with no serving weight can't be weighed, even if asked to.
    @Test func unweighedFoodsStayInServings() {
        var portion = FoodPortion(name: "Soup", servingSize: "1 cup (240 mL)", nutrients: ["dietaryEnergyConsumed": 90])
        #expect(!portion.canWeigh)
        portion.enter(in: .grams)
        #expect(portion.weightUnit == nil)
        portion.enteredAmount = 2
        #expect(portion.servings == 2)
        #expect(portion.amountText == "2 × 1 cup (240 mL)")
        #expect(portion.grams == nil)
    }

    @Test func servingSummariesAreUnchanged() {
        var portion = FoodPortion(name: "Oatmeal", brand: "Quaker", servingSize: "1/2 cup dry",
                                  nutrients: ["dietaryEnergyConsumed": 150])
        #expect(portion.summary == "Quaker · 1/2 cup dry · 150 kcal")
        portion.servings = 2
        #expect(portion.summary == "Quaker · 2 × 1/2 cup dry · 300 kcal")
        portion.servingSize = ""
        #expect(portion.summary == "Quaker · 2 servings · 300 kcal")
    }
}

@MainActor
struct ReplacementTests {
    private let rice = FoodPortion(name: "Jasmine Rice", servingSize: "1 cup cooked (158 g)",
                                   nutrients: ["dietaryEnergyConsumed": 205], gramsPerServing: 158)
    private let bread = FoodPortion(name: "Bread", servingSize: "1 slice", nutrients: ["dietaryEnergyConsumed": 80])

    @Test func aCountOfServingsCarriesOver() {
        var guess = FoodPortion(name: "Egg", servingSize: "1 large", nutrients: ["dietaryEnergyConsumed": 70])
        guess.servings = 3
        let fixed = guess.replaced(by: bread)
        #expect(fixed.name == "Bread")
        #expect(fixed.servings == 3)
        #expect(fixed.id != bread.id)
    }

    @Test func aWeightStaysTheSameWeight() {
        var guess = per100g("Rice")
        guess.enter(in: .grams)
        guess.enteredAmount = 200
        let fixed = guess.replaced(by: rice)
        #expect(fixed.weightUnit == .grams)
        #expect(abs(fixed.grams! - 200) < 1e-9)
        #expect(abs(fixed.calories - 205 * 200 / 158) < 1e-9)
    }

    @Test func aWeightCantBecomeServingsOfSomethingElse() {
        var guess = per100g("Toast")
        guess.enter(in: .grams)
        guess.enteredAmount = 60
        let fixed = guess.replaced(by: bread)
        #expect(fixed.weightUnit == nil)
        #expect(fixed.servings == 1)
    }

    @Test func aLeftOutFoodComesBackAsOneServing() {
        var guess = bread
        guess.servings = 0
        #expect(guess.replaced(by: rice).servings == 1)
    }
}

@MainActor
struct PortionCodingTests {
    /// An ingredient as build 25 encodes it, with none of the 1.1 keys.
    private let build25 = Data("""
        [{"id":"6F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Oats","brand":"Quaker","servingSize":"1/2 cup",
          "nutrients":{"dietaryEnergyConsumed":150,"dietaryProtein":5},"servings":2}]
        """.utf8)

    @Test func ingredientsFromBuild25StillDecode() throws {
        let portions = try JSONDecoder().decode([FoodPortion].self, from: build25)
        #expect(portions.count == 1)
        #expect(portions[0].name == "Oats")
        #expect(portions[0].servings == 2)
        #expect(portions[0].gramsPerServing == nil)
        #expect(portions[0].weightUnit == nil)
        #expect(portions[0].calories == 300)
    }

    /// A weight unit a later version might add mustn't empty the whole recipe.
    @Test func anUnknownWeightUnitIsIgnored() throws {
        let json = Data("""
            [{"id":"6F1B1C1E-5D2A-4B39-9C4E-2A8E7C1D9B10","name":"Oats","brand":"","servingSize":"40 g",
              "nutrients":{"dietaryEnergyConsumed":150},"servings":1.5,"gramsPerServing":40,"weightUnit":"lb"}]
            """.utf8)
        let portions = try JSONDecoder().decode([FoodPortion].self, from: json)
        #expect(portions.count == 1)
        #expect(portions[0].gramsPerServing == 40)
        #expect(portions[0].weightUnit == nil)
    }

    @Test func weightsRoundTrip() throws {
        var portion = per100g()
        portion.enter(in: .ounces)
        portion.enteredAmount = 3
        let decoded = try JSONDecoder().decode(FoodPortion.self, from: JSONEncoder().encode(portion))
        #expect(decoded == portion)
    }

    /// The new coverage marker is ignored by build 25; unweighed portions still omit measurement keys.
    @Test func unweighedPortionsEncodeWithoutTheNewKeys() throws {
        let portion = FoodPortion(name: "Oats", nutrients: ["dietaryEnergyConsumed": 150])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(portion)) as! [String: Any]
        #expect(Set(object.keys) == ["id", "name", "brand", "servingSize", "nutrients", "servings", "coverageIsUncertain"])
        #expect(object["coverageIsUncertain"] as? Bool == false)
    }
}
