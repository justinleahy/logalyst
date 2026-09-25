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

    init(name: String, servings: Double, ingredients: [FoodPortion]) {
        self.name = name
        self.servings = servings
        self.ingredients = ingredients
    }

    /// Each ingredient's nutrition per serving and how many servings go in. They're copies, so changing or
    /// deleting a saved food later doesn't change recipes made with it.
    var ingredients: [FoodPortion] {
        get { (try? JSONDecoder().decode([FoodPortion].self, from: ingredientData)) ?? [] }
        set { ingredientData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// One serving, ready to log.
    @MainActor var portion: FoodPortion {
        FoodPortion(name: name, servingSize: Self.servingLabel(servings),
                    nutrients: Self.perServing(ingredients, servings: servings))
    }

    /// "4 ingredients · 350 kcal per serving"
    @MainActor var summary: String {
        let count = ingredients.count
        let calories = portion.calories.formatted(.number.precision(.fractionLength(0)))
        return "\(count) \(count == 1 ? "ingredient" : "ingredients") · \(calories) kcal per serving"
    }

    /// What one serving of the ingredients holds, keyed by metric ID.
    @MainActor static func perServing(_ ingredients: [FoodPortion], servings: Double) -> [String: Double] {
        guard servings > 0 else { return [:] }
        var totals: [String: Double] = [:]
        for ingredient in ingredients {
            for id in ingredient.nutrients.keys {
                totals[id, default: 0] += ingredient.amount(of: id)
            }
        }
        return totals.mapValues { $0 / servings }
    }

    /// "1/4 recipe", or "Whole recipe" for one that makes a single serving.
    static func servingLabel(_ servings: Double) -> String {
        servings == 1 ? "Whole recipe" : "1/\(servings.formatted(.number.precision(.fractionLength(0...1)))) recipe"
    }
}
