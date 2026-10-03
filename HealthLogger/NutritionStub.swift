import Foundation

#if DEBUG
/// Stands in for brands' websites in the simulator and UI tests, with `-StubNutritionLookup` and one of: `ok`,
/// `offline`, `slow`, `rateLimited`, `unavailable` or `empty`. Its foods are marked as test data.
struct StubNutritionProvider: NutritionProvider {
    enum Mode: String {
        case ok, offline, slow, rateLimited, unavailable, empty
    }

    let mode: Mode

    static var fromLaunchArguments: StubNutritionProvider? {
        UserDefaults.standard.string(forKey: "StubNutritionLookup").flatMap(Mode.init(rawValue:)).map(Self.init)
    }

    func foods(for request: LookupRequest) async throws -> LookupResult {
        switch mode {
        case .offline: throw URLError(.notConnectedToInternet)
        case .rateLimited: throw LookupError.rateLimited(retryAfter: 120)
        case .unavailable: throw LookupError.unavailable
        case .empty: return LookupResult(foods: [:], pages: [NutritionPage(
            title: "\(request.brand) Nutrition (test link)", url: URL(string: "https://example.com/nutrition")!)])
        case .slow: try await Task.sleep(for: .seconds(60))
        case .ok: break
        }
        let menu = Self.menus[request.brand.lowercased()] ?? []
        var found: [String: [PublishedFood]] = [:]
        for term in request.terms {
            found[term] = menu.filter { NutritionMatcher.score(NutritionMatcher.words(term),
                                                               NutritionMatcher.words($0.name)) > 0 }
        }
        return LookupResult(foods: found)
    }

    private static func food(_ id: String, _ name: String, brand: String, serving: String, grams: Double?,
                             _ nutrients: [String: Double], url: String) -> PublishedFood {
        PublishedFood(id: "test:\(id)", name: name, brand: brand, nutrients: nutrients, gramsPerServing: grams,
                      source: NutritionSource(title: "\(brand) nutrition (test data)", url: URL(string: url)!,
                                              retrieved: Date(timeIntervalSince1970: 1_790_000_000), market: nil,
                                              servingBasis: serving, provider: "test data"))
    }

    /// Test values in the shape a brand's website gives, for tests only.
    private static let menus: [String: [PublishedFood]] = {
        let chipotle = "https://www.chipotle.com/nutrition-calculator"
        let sample = "https://example.com/nutrition"
        func amounts(_ kcal: Double, fat: Double, carbs: Double, protein: Double, sodium: Double,
                     sugar: Double? = nil) -> [String: Double] {
            var values = ["dietaryEnergyConsumed": kcal, "dietaryFatTotal": fat, "dietaryCarbohydrates": carbs,
                          "dietaryProtein": protein, "dietarySodium": sodium]
            values["dietarySugar"] = sugar
            return values
        }
        return [
            "chipotle": [
                food("chicken", "Chicken", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(180, fat: 7, carbs: 0, protein: 32, sodium: 310, sugar: 0), url: chipotle),
                food("white-rice", "White Rice", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(210, fat: 4, carbs: 40, protein: 4, sodium: 350, sugar: 0), url: chipotle),
                food("brown-rice", "Brown Rice", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(210, fat: 6, carbs: 36, protein: 4, sodium: 190, sugar: 0), url: chipotle),
                food("black-beans", "Black Beans", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(130, fat: 1.5, carbs: 22, protein: 8, sodium: 210, sugar: 2), url: chipotle),
                food("pinto-beans", "Pinto Beans", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(130, fat: 1.5, carbs: 21, protein: 8, sodium: 210, sugar: 1), url: chipotle),
                food("sofritas", "Sofritas", brand: "Chipotle", serving: "4 oz", grams: 113,
                     amounts(150, fat: 10, carbs: 9, protein: 8, sodium: 560, sugar: 5), url: chipotle),
                // No sugar published, to check a missing nutrient stays missing.
                food("guacamole", "Guacamole", brand: "Chipotle", serving: "4 oz", grams: nil,
                     amounts(230, fat: 22, carbs: 8, protein: 2, sodium: 370), url: chipotle),
            ],
            "sample bakery": [
                food("croissant", "Butter Croissant", brand: "Sample Bakery", serving: "1 croissant (70 g)",
                     grams: 70, amounts(290, fat: 16, carbs: 31, protein: 6, sodium: 300, sugar: 6), url: sample),
            ],
        ]
    }()
}
#endif
