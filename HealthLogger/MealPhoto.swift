import Foundation
import FoundationModels
import ImageIO

/// Estimates the foods in a photo of a meal with Apple Intelligence's on-device model, so nothing leaves the iPhone.
enum MealPhoto {
    /// Whether this iPhone can do it: iOS 27 or later, with Apple Intelligence turned on and ready.
    static var isAvailable: Bool {
        #if DEBUG
        if isStubbed { return true }
        #endif
        guard #available(iOS 27.0, *) else { return false }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.capabilities.contains(.vision) && model.capabilities.contains(.guidedGeneration)
    }

    enum Failure: LocalizedError {
        case unavailable, noFood

        var errorDescription: String? {
            switch self {
            case .unavailable: "Apple Intelligence isn't available right now. Check that it's turned on in Settings."
            case .noFood: "No food was found in the photo. Try again with the whole meal in view."
            }
        }
    }

    /// The foods in the photo. Separate pieces of one food, like 5 bananas, come back as one piece with that many
    /// servings; anything else is one serving of the amount shown. Foods named like one of `known` (saved foods and
    /// recipes) use its nutrition instead of an estimate. `details`, what the user says about the meal, is read
    /// on the iPhone only.
    static func foods(in image: CGImage, orientation: CGImagePropertyOrientation, known: [FoodPortion],
                      details: String = "") async throws -> [FoodPortion] {
        #if DEBUG
        if isStubbed { return stubFoods }
        #endif
        guard #available(iOS 27.0, *), isAvailable else { throw Failure.unavailable }
        let session = LanguageModelSession(
            instructions: instructions(knownNames: known.map(\.name)) + describing(details))
        let response = try await session.respond(to: Prompt {
            "Estimate each food and drink in this photo, including drinks next to the plate."
            Attachment(image, orientation: orientation)
        }, generating: MealEstimate.self, options: GenerationOptions(samplingMode: .greedy))
        let foods = response.content.foods.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard response.content.showsFood, !foods.isEmpty else { throw Failure.noFood }
        return foods.map { estimate in
            if var match = savedFood(named: estimate.name, in: known) {
                match.servings = Double(estimate.count)
                return match
            }
            return estimate.portion
        }
    }

    /// A saved food or recipe with exactly this name, as a fresh portion.
    static func savedFood(named name: String, in known: [FoodPortion]) -> FoodPortion? {
        guard var match = known.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        match.id = UUID()
        return match
    }

    /// The foods in a photo of a meal from a restaurant or brand, with short names to look up in its published
    /// nutrition and an on-device estimate to fall back on. `details` (what the user says about the meal, such as
    /// "double chicken, no sour cream") is read here on the iPhone and never sent anywhere.
    static func brandedItems(in image: CGImage, orientation: CGImagePropertyOrientation, brand: String,
                             details: String) async throws -> [BrandedItem] {
        #if DEBUG
        if isStubbed { return stubBrandedItems }
        #endif
        guard #available(iOS 27.0, *), isAvailable else { throw Failure.unavailable }
        let session = LanguageModelSession(instructions: brandedInstructions(brand: brand, details: details))
        let response = try await session.respond(to: Prompt {
            "List each food and drink in this meal from \(brand), as \(brand) portions them."
            Attachment(image, orientation: orientation)
        }, generating: BrandedMealEstimate.self, options: GenerationOptions(samplingMode: .greedy))
        let items = response.content.items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard response.content.showsFood || items.contains(where: { $0.origin == .details }), !items.isEmpty else {
            throw Failure.noFood
        }
        return items.map(\.item)
    }

    private static func brandedInstructions(brand: String, details: String) -> String {
        var text = """
            You identify the foods in photos of meals from restaurants and brands for a food log. This meal is \
            from \(brand). List each food and drink separately, the way \(brand) portions them: for a bowl, \
            burrito, salad or tacos, list the base, each protein, each topping and each sauce or salsa as its own \
            item. Use \(brand)'s own menu names when you know them. For each item, give how many of \(brand)'s \
            standard portions it is: 1 for a regular portion, 2 for double or extra, 0.5 for light, or the count \
            of pieces like 3 for three tacos. Mark items you can see as photo. Mark foods that this dish usually \
            has underneath other foods, but that you can't see, as hidden. Estimate typical nutrition for one \
            standard portion of each item. Use -1 for a nutrient you cannot estimate; zero means an actual \
            estimate of zero, not missing information. Don't list plates, cutlery, napkins or packaging.
            """
        let description = describing(details)
        if !description.isEmpty {
            text += description + " List foods the description mentions that you can't see as details."
        }
        return text
    }

    /// What the user says about the meal, for the model's instructions, or nothing if they didn't say.
    private static func describing(_ details: String) -> String {
        let details = LookupRequest.clean(details.replacingOccurrences(of: "\n", with: ", "), maxLength: 300)
        guard !details.isEmpty else { return "" }
        return " The user describes the meal as: \"\(details)\". The description is right where it differs from "
            + "what you see: \"double\" or \"extra\" means 2 portions, \"light\" means 0.5, and \"no\" or "
            + "\"without\" means leave that food out."
    }

    /// A food or drink in a branded meal's photo.
    struct BrandedItem: Hashable {
        enum Origin: Hashable {
            /// Seen in the photo.
            case photo
            /// Only in what the user said about the meal.
            case details
            /// Usually under other foods in this dish, but not seen or mentioned, so it needs confirming.
            case hidden
        }

        /// The brand's own name for it, when the model knows it.
        var name: String
        /// One to three words to look up, such as "white rice".
        var searchTerm: String
        /// How many of the brand's standard portions: 2 for double, 0.5 for light.
        var portions: Double
        var origin: Origin
        /// One standard portion estimated on the device, eaten `portions` times, for when no published food matches.
        var estimate: FoodPortion
    }

    private static func instructions(knownNames: [String]) -> String {
        var text = """
            You estimate nutrition from photos of meals for a food log. List every separate food and every drink \
            you can see, using typical nutrition values for that food and portion. When a food is several separate \
            pieces of the same kind, like bananas, eggs, cookies or slices of pizza, list it once with its singular \
            name, count the pieces carefully, and give the serving size and nutrition of just one piece. Otherwise \
            the count is 1 and the serving is the whole amount shown. Judge portion sizes from the plate, bowl, cup \
            and utensils. \
            Judge drinks by how they look: black coffee, tea and water have almost no calories unless milk, cream \
            or sugar is visible. Don't list plates, cutlery or garnishes too small to matter. Only list what's \
            really in the photo; if there's no food or drink, return no foods. Use -1 for a nutrient you cannot \
            estimate; zero means an actual estimate of zero, not missing information.
            """
        // The photo takes most of the model's context, so only the most recently used names fit.
        let names = knownNames.prefix(20)
        if !names.isEmpty {
            text += " The user has saved some foods. Only when one of them is clearly in the photo, use its name "
                + "exactly; never list a saved food that isn't visible: " + names.joined(separator: "; ") + "."
        }
        return text
    }

    #if DEBUG
    /// With `-StubMealPhoto YES`, Photo of Meal is offered on any simulator and finds these foods in any photo, so
    /// UI tests can check the meal screen without depending on Apple Intelligence's answers.
    static var isStubbed: Bool { UserDefaults.standard.bool(forKey: "StubMealPhoto") }

    private static func stubEstimate(_ name: String, _ calories: Double, servings: Double) -> FoodPortion {
        FoodPortion(name: name, servingSize: "1 serving", nutrients: ["dietaryEnergyConsumed": calories],
                    servings: servings, isEstimate: true)
    }

    private static let stubFoods = [stubEstimate("Banana", 105, servings: 2), stubEstimate("Coffee", 5, servings: 1)]

    /// A Chipotle bowl: double chicken, rice that might be under the toppings (white or brown), black beans,
    /// guacamole from the description, and a lime wedge no published food matches.
    private static let stubBrandedItems: [BrandedItem] = [
        BrandedItem(name: "Chicken", searchTerm: "chicken", portions: 2, origin: .photo,
                    estimate: stubEstimate("Chicken", 200, servings: 2)),
        BrandedItem(name: "Rice", searchTerm: "rice", portions: 1, origin: .hidden,
                    estimate: stubEstimate("Rice", 220, servings: 1)),
        BrandedItem(name: "Black Beans", searchTerm: "black beans", portions: 1, origin: .photo,
                    estimate: stubEstimate("Black Beans", 120, servings: 1)),
        BrandedItem(name: "Guac", searchTerm: "guac", portions: 1, origin: .details,
                    estimate: stubEstimate("Guac", 250, servings: 1)),
        BrandedItem(name: "Lime Wedge", searchTerm: "lime", portions: 1, origin: .photo,
                    estimate: stubEstimate("Lime Wedge", 2, servings: 1)),
    ]
    #endif

    /// When a photo was taken, from its camera metadata, or nil if it doesn't say.
    static func dateTaken(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}

@available(iOS 27.0, *)
@Generable
private struct MealEstimate {
    // Generated in order, so describing the photo first keeps the list grounded in what's there.
    @Guide(description: "What the photo shows, in a few plain words")
    var scene: String
    @Guide(description: "Whether the photo shows food or drink that someone is eating or about to eat")
    var showsFood: Bool
    @Guide(description: "Each separate food or drink in the photo, largest first. Empty if it shows no food.")
    var foods: [FoodEstimate]
}

@available(iOS 27.0, *)
@Generable
private struct FoodEstimate {
    @Guide(description: "The food's common singular name, such as Banana rather than Bananas, including how it's prepared when you can tell")
    var name: String
    @Guide(description: "How many separate pieces of this food are shown, such as 5 for five bananas. 1 for food that isn't in separate pieces, like rice, soup or a drink.", .range(1...50))
    var count: Int
    @Guide(description: "One serving in everyday units: one piece, such as 1 medium or 1 slice, when there are separate pieces; otherwise the whole amount shown, such as 1.5 cups or 12 fluid ounces")
    var servingSize: String
    @Guide(description: "Calories in kcal for one serving, or -1 if unknown", .range(-1...3000))
    var calories: Int
    @Guide(description: "Protein in grams for one serving, or -1 if unknown", .range(-1...300))
    var protein: Double
    @Guide(description: "Carbohydrates in grams for one serving, or -1 if unknown", .range(-1...500))
    var carbohydrates: Double
    @Guide(description: "Total fat in grams for one serving, or -1 if unknown", .range(-1...300))
    var fat: Double
    @Guide(description: "Sugar in grams for one serving, or -1 if unknown", .range(-1...300))
    var sugar: Double
    @Guide(description: "Fiber in grams for one serving, or -1 if unknown", .range(-1...100))
    var fiber: Double
    @Guide(description: "Caffeine in milligrams for one serving, or -1 if unknown; do not assume zero", .range(-1...500))
    var caffeine: Double

    /// One piece or the whole amount shown, eaten `count` times.
    var portion: FoodPortion {
        estimatedPortion(name: name, servingSize: servingSize, servings: Double(count), calories: calories,
                         protein: protein, carbohydrates: carbohydrates, fat: fat, sugar: sugar, fiber: fiber,
                         caffeine: caffeine)
    }
}

/// An estimate from a photo, with known amounts (including zero) rounded to a tenth. Negative/invalid values
/// represent unknown nutrition. Descriptions in a photo never establish a measured weight or volume.
nonisolated func estimatedPortion(name: String, servingSize: String, servings: Double, calories: Int, protein: Double,
                              carbohydrates: Double, fat: Double, sugar: Double, fiber: Double,
                              caffeine: Double) -> FoodPortion {
    let nutrients: [String: Double] = [
        "dietaryEnergyConsumed": Double(calories),
        "dietaryProtein": protein,
        "dietaryCarbohydrates": carbohydrates,
        "dietaryFatTotal": fat,
        "dietarySugar": sugar,
        "dietaryFiber": fiber,
        "dietaryCaffeine": caffeine,
    ]
    let name = name.trimmingCharacters(in: .whitespaces)
    var amount = servingSize.trimmingCharacters(in: .whitespaces)
    // A bare count like "1" reads oddly on its own.
    if !amount.isEmpty, !amount.contains(where: \.isLetter) {
        amount += amount == "1" ? " serving" : " servings"
    }
    return FoodPortion(name: name.prefix(1).uppercased() + name.dropFirst(), servingSize: amount,
                       nutrients: nutrients.filter { $0.value.isFinite && $0.value >= 0 }
                        .mapValues { ($0 * 10).rounded() / 10 },
                       servings: servings, isEstimate: true)
}

@available(iOS 27.0, *)
@Generable
private struct BrandedMealEstimate {
    @Guide(description: "What the photo shows, in a few plain words")
    var scene: String
    @Guide(description: "Whether the photo shows food or drink that someone is eating or about to eat")
    var showsFood: Bool
    @Guide(description: "Each food and drink in the meal, portioned the way the restaurant or brand serves it")
    var items: [BrandedFoodEstimate]
}

@available(iOS 27.0, *)
@Generable
private enum ItemOrigin {
    case photo, details, hidden
}

@available(iOS 27.0, *)
@Generable
private struct BrandedFoodEstimate {
    @Guide(description: "The food's name on the restaurant's menu or the brand's package when you know it, such as Chicken, White Rice or Fresh Tomato Salsa; otherwise its common singular name")
    var name: String
    @Guide(description: "One to three plain lowercase words to search the brand's nutrition for, such as chicken, white rice or sour cream. No amounts, brand names or descriptions.")
    var searchTerm: String
    @Guide(description: "How many of the brand's standard portions: 1 regular, 2 double or extra, 0.5 light, or the number of pieces", .range(0.25...12))
    var portions: Double
    @Guide(description: "photo if you can see it, details if only the user's description mentions it, hidden if it's usually under other foods in this dish but you can't see it")
    var origin: ItemOrigin
    @Guide(description: "One standard portion in everyday units, such as 4 oz, 1 cup or 1 taco")
    var servingSize: String
    @Guide(description: "Calories in kcal for one standard portion, or -1 if unknown", .range(-1...3000))
    var calories: Int
    @Guide(description: "Protein in grams for one standard portion, or -1 if unknown", .range(-1...300))
    var protein: Double
    @Guide(description: "Carbohydrates in grams for one standard portion, or -1 if unknown", .range(-1...500))
    var carbohydrates: Double
    @Guide(description: "Total fat in grams for one standard portion, or -1 if unknown", .range(-1...300))
    var fat: Double
    @Guide(description: "Sugar in grams for one standard portion, or -1 if unknown", .range(-1...300))
    var sugar: Double
    @Guide(description: "Fiber in grams for one standard portion, or -1 if unknown", .range(-1...100))
    var fiber: Double
    @Guide(description: "Caffeine in milligrams for one standard portion, or -1 if unknown; do not assume zero", .range(-1...500))
    var caffeine: Double

    var item: MealPhoto.BrandedItem {
        let origin: MealPhoto.BrandedItem.Origin = switch origin {
        case .photo: .photo
        case .details: .details
        case .hidden: .hidden
        }
        let estimate = estimatedPortion(name: name, servingSize: servingSize, servings: portions, calories: calories,
                                        protein: protein, carbohydrates: carbohydrates, fat: fat, sugar: sugar,
                                        fiber: fiber, caffeine: caffeine)
        // Only a few words are sent, so a longer phrase from the user's details can't go along with them.
        let words = { (text: String) in text.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ") }
        let term = words(searchTerm)
        return MealPhoto.BrandedItem(name: estimate.name, searchTerm: term.isEmpty ? words(name) : term,
                                     portions: portions, origin: origin, estimate: estimate)
    }
}
