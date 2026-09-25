import Foundation
import SwiftData

/// A food the user saved, logged to Health as a food entry of its nutrients times the servings eaten.
@Model
final class Food {
    var name: String
    var brand: String
    /// Free text from the label, e.g. "1 cup" or "30 g".
    var servingSize: String
    var barcode: String?
    /// Amount per serving keyed by metric ID, in each metric's first unit option (kcal, g, mg).
    var nutrients: [String: Double]
    var created: Date
    var lastLogged: Date?
    /// Favorites sort to the top of My Foods.
    var isFavorite: Bool = false

    init(_ draft: FoodDraft) {
        name = ""
        brand = ""
        servingSize = ""
        nutrients = [:]
        created = .now
        update(from: draft)
    }

    func update(from draft: FoodDraft) {
        name = draft.name.trimmingCharacters(in: .whitespaces)
        brand = draft.brand.trimmingCharacters(in: .whitespaces)
        servingSize = draft.servingSize.trimmingCharacters(in: .whitespaces)
        barcode = draft.barcode
        nutrients = draft.nutrients.filter { $0.value > 0 }
    }

    var draft: FoodDraft {
        FoodDraft(name: name, brand: brand, servingSize: servingSize, barcode: barcode, nutrients: nutrients)
    }

    /// One serving, ready to log.
    var portion: FoodPortion {
        FoodPortion(name: name, brand: brand, servingSize: servingSize, nutrients: nutrients)
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
    var barcode: String?
    var nutrients: [String: Double] = [:]
    var source = Source.manual

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nutrients.values.contains { $0 > 0 }
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

    /// A draft prefilled from the database, or nil if the product isn't listed.
    static func lookUp(barcode: String) async throws -> FoodDraft? {
        guard !barcode.isEmpty, barcode.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,brands,serving_size,nutriments")]
        var request = URLRequest(url: components.url!)
        // Open Food Facts asks apps to identify themselves.
        request.setValue("HealthLogger/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any] else { return nil }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let servingSize = (product["serving_size"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        // Prefer per-serving values; fall back to per 100 g when the label doesn't give a serving.
        let perServing = !servingSize.isEmpty && fields.values.contains { number(nutriments[$0.key + "_serving"]) != nil }
        let suffix = perServing ? "_serving" : "_100g"

        var draft = FoodDraft(
            name: (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "",
            brand: (product["brands"] as? String)?.split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? "",
            servingSize: perServing ? servingSize : "100 g",
            barcode: barcode,
            source: .database)
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

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
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
