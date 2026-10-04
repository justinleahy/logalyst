import Foundation
import SwiftData

/// Foods combined into a dish the user makes, logged by the serving like a saved food.
/// Synced through iCloud with every field end-to-end encrypted, which is why each has a default.
@Model
final class Recipe {
    @Attribute(.allowsCloudEncryption) var name = ""
    /// How many servings the whole recipe makes.
    @Attribute(.allowsCloudEncryption) var servings = 1.0
    /// The ingredients as encoded `FoodPortion`s; use `ingredients`.
    @Attribute(.allowsCloudEncryption) private var ingredientData = Data()
    @Attribute(.allowsCloudEncryption) var created = Date.now
    @Attribute(.allowsCloudEncryption) var lastLogged: Date?
    /// A permanent ID that iCloud syncs with the recipe, for Siri and Shortcuts, as for `Food.uuid`.
    @Attribute(.allowsCloudEncryption) var uuid: UUID?

    init(name: String, servings: Double, ingredients: [FoodPortion]) {
        uuid = UUID()
        self.name = name
        self.servings = servings
        self.ingredients = ingredients
    }

    /// Each ingredient's nutrition per serving and how many servings go in, with its weight when it was weighed.
    /// They're copies, so changing or deleting a saved food later doesn't change recipes made with it. A recipe is
    /// still logged by the serving: its own weight isn't known, and isn't guessed from its ingredients'.
    var ingredients: [FoodPortion] {
        get { (try? JSONDecoder().decode([FoodPortion].self, from: ingredientData)) ?? [] }
        set { ingredientData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// One serving, ready to log.
    @MainActor var portion: FoodPortion {
        FoodPortion(name: name, servingSize: Self.servingLabel(servings),
                    nutrients: Self.perServing(ingredients, servings: servings),
                    nutrientCoverage: Self.perServingCoverage(ingredients))
    }

    /// "4 ingredients · 350 kcal per serving"
    @MainActor var summary: String {
        let count = ingredients.count
        let portion = portion
        let calories = portion.knownAmount(of: "dietaryEnergyConsumed")
            .map { "\($0.formatted(.number.precision(.fractionLength(0)))) kcal per serving" }
            ?? "Calories unavailable"
        let coverage = portion.coverage(of: "dietaryEnergyConsumed")
        let qualifier = coverage.isPartial ? " (partial)" : coverage.isUncertain ? " (coverage unknown)" : ""
        return "\(count) \(count == 1 ? "ingredient" : "ingredients") · \(calories)\(qualifier)"
    }

    /// What one serving of the ingredients holds, keyed by metric ID.
    @MainActor static func perServing(_ ingredients: [FoodPortion], servings: Double) -> [String: Double] {
        guard servings.isFinite && servings > 0 else { return [:] }
        return FoodNutrition.totals(ingredients).mapValues { $0 / servings }
    }

    /// Counts are per ingredient, independent of the recipe yield or how many servings are later eaten.
    @MainActor static func perServingCoverage(_ ingredients: [FoodPortion]) -> [String: NutrientCoverage] {
        let ids = Set(FoodNutrient.metrics.map(\.id))
            .union(ingredients.flatMap { $0.nutrients.keys })
            .union(ingredients.flatMap { $0.nutrientCoverage?.keys.map { $0 } ?? [] })
        return FoodNutrition.coverage(in: ingredients, metricIDs: Array(ids))
    }

    /// "1/4 recipe", or "Whole recipe" for one that makes a single serving.
    static func servingLabel(_ servings: Double) -> String {
        servings == 1 ? "Whole recipe" : "1/\(servings.formatted(.number.precision(.fractionLength(0...1)))) recipe"
    }
}
