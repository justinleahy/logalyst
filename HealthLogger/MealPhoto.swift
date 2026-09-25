import Foundation
import FoundationModels
import ImageIO

/// Estimates the foods in a photo of a meal with Apple Intelligence's on-device model, so nothing leaves the iPhone.
enum MealPhoto {
    /// Whether this iPhone can do it: iOS 27 or later, with Apple Intelligence turned on and ready.
    static var isAvailable: Bool {
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

    /// The foods in the photo, one serving each being the amount shown. Foods named like one of `known` (saved foods
    /// and recipes) use its nutrition instead of an estimate.
    static func foods(in image: CGImage, orientation: CGImagePropertyOrientation,
                      known: [FoodPortion]) async throws -> [FoodPortion] {
        guard #available(iOS 27.0, *), isAvailable else { throw Failure.unavailable }
        let session = LanguageModelSession(instructions: instructions(knownNames: known.map(\.name)))
        let response = try await session.respond(to: Prompt {
            "Estimate each food and drink in this photo, including drinks next to the plate."
            Attachment(image, orientation: orientation)
        }, generating: MealEstimate.self, options: GenerationOptions(samplingMode: .greedy))
        let foods = response.content.foods.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard response.content.showsFood, !foods.isEmpty else { throw Failure.noFood }
        return foods.map { estimate in
            if var match = known.first(where: { $0.name.localizedCaseInsensitiveCompare(estimate.name) == .orderedSame }) {
                match.id = UUID()
                match.servings = 1
                return match
            }
            return estimate.portion
        }
    }

    private static func instructions(knownNames: [String]) -> String {
        var text = """
            You estimate nutrition from photos of meals for a food log. List every separate food and every drink \
            you can see, with the amount shown and its nutrition for that amount, using typical values for that \
            food and portion. Count items carefully, and judge portion sizes from the plate, bowl, cup and utensils. \
            Judge drinks by how they look: black coffee, tea and water have almost no calories unless milk, cream \
            or sugar is visible. Don't list plates, cutlery or garnishes too small to matter. Only list what's \
            really in the photo; if there's no food or drink, return no foods.
            """
        // The photo takes most of the model's context, so only the most recently used names fit.
        let names = knownNames.prefix(20)
        if !names.isEmpty {
            text += " The user has saved some foods. Only when one of them is clearly in the photo, use its name "
                + "exactly; never list a saved food that isn't visible: " + names.joined(separator: "; ") + "."
        }
        return text
    }

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
    @Guide(description: "The food's common name, including how it's prepared when you can tell")
    var name: String
    @Guide(description: "The amount shown in everyday units, such as cups, pieces, slices or fluid ounces")
    var amount: String
    @Guide(description: "Calories in kcal for the amount shown", .range(0...3000))
    var calories: Int
    @Guide(description: "Protein in grams for the amount shown", .range(0...300))
    var protein: Double
    @Guide(description: "Carbohydrates in grams for the amount shown", .range(0...500))
    var carbohydrates: Double
    @Guide(description: "Total fat in grams for the amount shown", .range(0...300))
    var fat: Double
    @Guide(description: "Sugar in grams for the amount shown", .range(0...300))
    var sugar: Double
    @Guide(description: "Fiber in grams for the amount shown", .range(0...100))
    var fiber: Double
    @Guide(description: "Caffeine in milligrams for the amount shown, 0 for most foods", .range(0...500))
    var caffeine: Double

    /// The amount shown counts as one serving.
    var portion: FoodPortion {
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
        var amount = amount.trimmingCharacters(in: .whitespaces)
        // A bare count like "1" reads oddly on its own.
        if !amount.isEmpty, !amount.contains(where: \.isLetter) {
            amount += amount == "1" ? " serving" : " servings"
        }
        return FoodPortion(name: name.prefix(1).uppercased() + name.dropFirst(), servingSize: amount,
                           nutrients: nutrients.filter { $0.value > 0 }.mapValues { ($0 * 10).rounded() / 10 })
    }
}
