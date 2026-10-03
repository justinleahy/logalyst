import Foundation
import SwiftData

/// A food the user saved, logged to Health as a food entry of its nutrients times the servings eaten.
/// Synced through iCloud with every field end-to-end encrypted, which is why each has a default.
@Model
final class Food {
    @Attribute(.allowsCloudEncryption) var name = ""
    @Attribute(.allowsCloudEncryption) var brand = ""
    /// Free text from the label, e.g. "1 cup" or "30 g".
    @Attribute(.allowsCloudEncryption) var servingSize = ""
    /// What one serving weighs in grams, so the food can be logged by weight. Nil when it isn't known, as for foods
    /// saved before 1.1 or known only by volume. Added in 1.1, so it's optional for older records and iCloud.
    @Attribute(.allowsCloudEncryption) var gramsPerServing: Double?
    @Attribute(.allowsCloudEncryption) var barcode: String?
    /// Amount per serving keyed by metric ID, in each metric's first unit option (kcal, g, mg).
    @Attribute(.allowsCloudEncryption) var nutrients: [String: Double] = [:]
    @Attribute(.allowsCloudEncryption) var created = Date.now
    @Attribute(.allowsCloudEncryption) var lastLogged: Date?
    /// Favorites sort to the top of My Foods.
    @Attribute(.allowsCloudEncryption) var isFavorite = false

    init(_ draft: FoodDraft) {
        update(from: draft)
    }

    func update(from draft: FoodDraft) {
        name = draft.name.trimmingCharacters(in: .whitespaces)
        brand = draft.brand.trimmingCharacters(in: .whitespaces)
        servingSize = draft.servingSize.trimmingCharacters(in: .whitespaces)
        gramsPerServing = draft.gramsPerServing.flatMap { $0 > 0 ? $0 : nil }
        barcode = draft.barcode
        nutrients = draft.nutrients.filter { $0.value > 0 }
    }

    var draft: FoodDraft {
        FoodDraft(name: name, brand: brand, servingSize: servingSize, gramsPerServing: gramsPerServing,
                  barcode: barcode, nutrients: nutrients)
    }

    /// One serving, ready to log. A food whose serving is just a weight, like "100 g", starts out entered in grams.
    var portion: FoodPortion {
        FoodPortion(name: name, brand: brand, servingSize: servingSize, nutrients: nutrients,
                    gramsPerServing: gramsPerServing,
                    weightUnit: gramsPerServing != nil && ServingWeight.isWeightOnly(servingSize) ? .grams : nil)
    }

    /// "Brand · 1 cup · 150 kcal", skipping whatever is missing.
    var summary: String {
        let calories = nutrients["dietaryEnergyConsumed"].map { "\($0.formatted(.number.precision(.fractionLength(0)))) kcal" }
        return [brand, servingSize, calories].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

/// Editable copy of a food's fields, also used to prefill a new food from a barcode lookup.
struct FoodDraft: Hashable {
    enum Source { case manual, database, notFound, label }

    var name = ""
    var brand = ""
    var servingSize = ""
    /// Grams per serving, when known.
    var gramsPerServing: Double?
    var barcode: String?
    var nutrients: [String: Double] = [:]
    var source = Source.manual

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nutrients.values.contains { $0 > 0 }
    }

    /// A weight the serving size states in grams, to offer when the food has none yet. Not offered for the
    /// "100 g" that barcode lookups before 1.1 wrote for any product without a serving, since those amounts may be
    /// per 100 mL.
    var statedServingWeight: Double? {
        guard gramsPerServing == nil, !(barcode != nil && servingSize == FoodDatabase.per100Serving) else { return nil }
        return ServingWeight.grams(in: servingSize)
    }
}

enum FoodNutrient {
    /// What a food can contain: everything in Intake except water and alcohol, which are logged directly.
    /// Caffeine goes last so the list reads like a nutrition label.
    static let metrics: [Metric] = {
        let foods = Metric.metrics(in: .intake).filter { !["dietaryWater", "alcoholicBeverages"].contains($0.id) }
        return foods.filter { $0.id != "dietaryCaffeine" } + foods.filter { $0.id == "dietaryCaffeine" }
    }()
}

// MARK: - Barcode lookup

/// Looks up packaged foods by barcode in Open Food Facts (openfoodfacts.org), a free, open food database.
enum FoodDatabase {
    /// Open Food Facts nutriment names per metric ID, with the factor that converts to our unit.
    private static let fields: [String: (key: String, factor: Double)] = [
        "dietaryEnergyConsumed": ("energy-kcal", 1),
        "dietaryProtein": ("proteins", 1),
        "dietaryCarbohydrates": ("carbohydrates", 1),
        "dietaryFatTotal": ("fat", 1),
        "dietaryFatSaturated": ("saturated-fat", 1),
        "dietaryCholesterol": ("cholesterol", 1000), // reported in grams
        "dietarySodium": ("sodium", 1000), // reported in grams
        "dietarySugar": ("sugars", 1),
        "dietaryFiber": ("fiber", 1),
        "dietaryCaffeine": ("caffeine", 1000), // reported in grams
    ]

    /// The serving size used when a product lists amounts only per 100 g or 100 mL and which isn't known.
    static let per100Serving = "100 g"

    /// A draft prefilled from the database, or nil if the product isn't listed.
    static func lookUp(barcode: String) async throws -> FoodDraft? {
        guard !barcode.isEmpty, barcode.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,brands,serving_size,"
            + "serving_quantity,serving_quantity_unit,quantity,product_quantity_unit,nutriments")]
        var request = URLRequest(url: components.url!)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("HealthLogger/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        return try draft(from: data, barcode: barcode)
    }

    /// A draft from an Open Food Facts product response, or nil if it has no product.
    static func draft(from data: Data, barcode: String) throws -> FoodDraft? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any] else { return nil }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let servingSize = (product["serving_size"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        // Prefer per-serving values; fall back to per 100 g (or 100 mL) when the label doesn't give a serving.
        let perServing = !servingSize.isEmpty && fields.values.contains { number(nutriments[$0.key + "_serving"]) != nil }
        let suffix = perServing ? "_serving" : "_100g"

        var draft = FoodDraft(
            name: (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "",
            brand: (product["brands"] as? String)?.split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
            barcode: barcode,
            source: .database)
        if perServing {
            draft.servingSize = servingSize
            // The weight printed in the serving, like "1 bar (40 g)", or the database's own serving amount when
            // it's in grams. A serving in mL has no weight.
            draft.gramsPerServing = ServingWeight.grams(in: servingSize)
                ?? ((product["serving_quantity_unit"] as? String)?.lowercased() == "g"
                    ? number(product["serving_quantity"]).flatMap { $0 > 0 ? $0 : nil } : nil)
        } else {
            // Open Food Facts gives these per 100 g, or per 100 mL for liquids. Only a product known to be sold by
            // weight gets a 100 g serving weight; a drink mustn't.
            switch per100Unit(of: product) {
            case .grams?:
                draft.servingSize = "100 g"
                draft.gramsPerServing = 100
            case .milliliters?:
                draft.servingSize = "100 mL"
            case nil:
                draft.servingSize = per100Serving
            }
        }
        for (id, field) in fields {
            if let value = number(nutriments[field.key + suffix]) {
                draft.nutrients[id] = (value * field.factor * 10).rounded() / 10
            }
        }
        // Some products only list energy in kilojoules.
        if draft.nutrients["dietaryEnergyConsumed"] == nil, let kilojoules = number(nutriments["energy" + suffix]) {
            draft.nutrients["dietaryEnergyConsumed"] = (kilojoules / 4.184).rounded()
        }
        return draft
    }

    private enum Per100Unit { case grams, milliliters }

    /// Whether a product's per-100 amounts are per 100 g or 100 mL, from the unit its package size is in.
    /// Nil when that isn't clear.
    private static func per100Unit(of product: [String: Any]) -> Per100Unit? {
        switch (product["product_quantity_unit"] as? String)?.lowercased() {
        case "g", "kg": return .grams
        case "ml", "cl", "dl", "l": return .milliliters
        default: break
        }
        let quantity = (product["quantity"] as? String)?.lowercased() ?? ""
        let isVolume = quantity.contains(#/\d\s*(ml|cl|dl|l|fl\.?\s*oz)\b/#)
        let isWeight = quantity.contains(#/\d\s*(g|kg)\b/#)
        if isWeight != isVolume { return isWeight ? .grams : .milliliters }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }
}

extension FoodPortion {
    /// This portion with the serving weight of the saved food it was logged from, for an entry logged before that
    /// food had one, so it can be weighed when logged again. Only a saved food on exactly the same basis counts:
    /// the same name, brand, serving size and nutrition per serving. Otherwise it stays by the serving.
    func withServingWeight(from foods: [Food]) -> FoodPortion {
        guard gramsPerServing == nil else { return self }
        let match = foods.first { food in
            guard food.gramsPerServing != nil, isSameFood(as: food.portion),
                  food.servingSize.localizedCaseInsensitiveCompare(servingSize) == .orderedSame,
                  Set(food.nutrients.keys) == Set(nutrients.keys) else { return false }
            // Health stores totals, so per-serving amounts read back can be off in the last digits.
            return food.nutrients.allSatisfy { id, amount in
                abs((nutrients[id] ?? 0) - amount) <= max(0.01, amount * 0.001)
            }
        }
        guard let grams = match?.gramsPerServing else { return self }
        var portion = self
        portion.gramsPerServing = grams
        return portion
    }
}

extension Food {
    /// Marks the saved foods matching these portions as just logged, so they move up in My Foods.
    @MainActor static func markLogged(_ portions: [FoodPortion], among foods: [Food]) {
        for food in foods where portions.contains(where: { $0.isSameFood(as: food.portion) }) {
            food.lastLogged = .now
        }
    }
}
