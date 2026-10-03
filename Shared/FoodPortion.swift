import Foundation

/// Which meal a food was eaten at, saved with each food entry in Health.
enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: Self { self }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// The meal usually eaten at this time of day, used as the default and for entries saved without one.
    init(at date: Date) {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: self = .breakfast
        case 11..<15: self = .lunch
        case 17..<22: self = .dinner
        default: self = .snack
        }
    }
}

/// A unit a food's amount can be weighed in. Only mass: volumes aren't weights without knowing the food's density.
enum WeightUnit: String, CaseIterable, Identifiable, Codable {
    case grams = "g"
    case ounces = "oz"

    static let gramsPerOunce = 28.349523125

    var id: Self { self }
    var label: String { rawValue }

    var title: String {
        switch self {
        case .grams: "Grams"
        case .ounces: "Ounces"
        }
    }

    /// Digits shown and typed: whole grams are precise enough, but an ounce is coarse.
    var fractionDigits: Int {
        switch self {
        case .grams: 1
        case .ounces: 2
        }
    }

    /// How much the stepper changes the amount.
    var step: Double {
        switch self {
        case .grams: 5
        case .ounces: 0.25
        }
    }

    func grams(from value: Double) -> Double {
        switch self {
        case .grams: value
        case .ounces: value * Self.gramsPerOunce
        }
    }

    func value(fromGrams grams: Double) -> Double {
        switch self {
        case .grams: grams
        case .ounces: grams / Self.gramsPerOunce
        }
    }

    /// "35 g" or "1.25 oz".
    func format(grams: Double) -> String {
        let value = value(fromGrams: grams).formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return "\(value) \(label)"
    }
}

/// One food as it goes into Health: its nutrition per serving and how many servings were eaten.
/// Built from a saved food, or read back from a past food entry so it can be logged again.
struct FoodPortion: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var brand = ""
    /// Free text from the label, e.g. "1 cup" or "30 g".
    var servingSize = ""
    /// Amount per serving keyed by metric ID, in each metric's first unit option (kcal, g, mg).
    var nutrients: [String: Double]
    var servings = 1.0
    /// What one serving weighs, in grams, when that's known, so the food can be entered by weight. Nil for foods
    /// known only by volume or count. Optional so ingredients saved before it existed still decode.
    var gramsPerServing: Double?
    /// The unit the amount was weighed in, or nil when it was entered in servings. Only set with `gramsPerServing`.
    var weightUnit: WeightUnit?
    /// Where the nutrition per serving was published, for a food looked up online (added in 1.1). Nil for saved
    /// foods, labels, barcodes and estimates.
    var source: NutritionSource?
    /// Whether the nutrition per serving is Apple Intelligence's estimate from a photo rather than a saved food,
    /// a label or published values (added in 1.1).
    var isEstimate = false

    /// Total amount eaten, in the metric's first unit option.
    func amount(of metricID: String) -> Double {
        (nutrients[metricID] ?? 0) * servings
    }

    var calories: Double { amount(of: "dietaryEnergyConsumed") }

    /// Whether two portions are the same food, ignoring how much was eaten.
    func isSameFood(as other: FoodPortion) -> Bool {
        name.localizedCaseInsensitiveCompare(other.name) == .orderedSame
            && brand.localizedCaseInsensitiveCompare(other.brand) == .orderedSame
    }

    /// Whether the food can be entered by weight.
    var canWeigh: Bool {
        (gramsPerServing ?? 0) > 0
    }

    /// The weight eaten, in grams, when the serving weight is known.
    var grams: Double? {
        canWeigh ? gramsPerServing.map { $0 * servings } : nil
    }

    /// The unit the amount is entered in, if it's weighed. Ignores a unit left over on a food that can't be weighed.
    var enteredWeightUnit: WeightUnit? {
        canWeigh ? weightUnit : nil
    }

    /// The amount in the unit it's entered in: servings, or the weight in grams or ounces. Setting it works out
    /// the servings, which is what nutrition is calculated from.
    var enteredAmount: Double {
        get {
            guard let unit = enteredWeightUnit, let grams else { return servings }
            return unit.value(fromGrams: grams)
        }
        set {
            guard let unit = enteredWeightUnit, let gramsPerServing else {
                servings = newValue
                return
            }
            servings = unit.grams(from: newValue) / gramsPerServing
        }
    }

    /// Switches between entering servings and a weight, keeping the amount eaten the same.
    mutating func enter(in unit: WeightUnit?) {
        weightUnit = canWeigh ? unit : nil
    }

    /// "35 g" for a weighed portion, otherwise "2 × 1 cup", "1 cup" or "2 servings".
    var amountText: String {
        if let unit = enteredWeightUnit, let grams {
            return unit.format(grams: grams)
        }
        let count = servings.formatted(.number.precision(.fractionLength(0...2)))
        if servingSize.isEmpty {
            return servings == 1 ? "1 serving" : "\(count) servings"
        }
        return servings == 1 ? servingSize : "\(count) × \(servingSize)"
    }

    /// This portion swapped for another food, such as a meal-photo guess corrected to a saved food. A weighed
    /// amount stays the same weight when the new food can be weighed, and a count of servings (like 3 eggs) carries
    /// over; a weight can't become servings of something else, so that starts at one serving.
    func replaced(by food: FoodPortion) -> FoodPortion {
        var replacement = food
        replacement.id = UUID()
        if let unit = enteredWeightUnit, let grams {
            if replacement.canWeigh, let gramsPerServing = replacement.gramsPerServing {
                replacement.weightUnit = unit
                replacement.servings = grams / gramsPerServing
            } else {
                replacement.weightUnit = nil
                replacement.servings = 1
            }
        } else {
            replacement.weightUnit = nil
            replacement.servings = servings > 0 ? servings : 1
        }
        return replacement
    }
}

extension FoodPortion {
    private enum CodingKeys: String, CodingKey {
        case id, name, brand, servingSize, nutrients, servings, gramsPerServing, weightUnit, source, isEstimate
    }

    /// Recipes store their ingredients as a list of these, and a list that fails to decode loads as no ingredients,
    /// so the fields added in 1.1 are read leniently: missing or unreadable just means not weighed, and no source.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decode(String.self, forKey: .brand)
        servingSize = try container.decode(String.self, forKey: .servingSize)
        nutrients = try container.decode([String: Double].self, forKey: .nutrients)
        servings = try container.decode(Double.self, forKey: .servings)
        gramsPerServing = (try? container.decodeIfPresent(Double.self, forKey: .gramsPerServing)) ?? nil
        weightUnit = (try? container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)) ?? nil
        source = (try? container.decodeIfPresent(NutritionSource.self, forKey: .source)) ?? nil
        isEstimate = ((try? container.decodeIfPresent(Bool.self, forKey: .isEstimate)) ?? nil) ?? false
    }

    /// Leaves out what's unset, so a food without a weight, source or estimate encodes exactly as build 25 does.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(brand, forKey: .brand)
        try container.encode(servingSize, forKey: .servingSize)
        try container.encode(nutrients, forKey: .nutrients)
        try container.encode(servings, forKey: .servings)
        try container.encodeIfPresent(gramsPerServing, forKey: .gramsPerServing)
        try container.encodeIfPresent(weightUnit, forKey: .weightUnit)
        try container.encodeIfPresent(source, forKey: .source)
        if isEstimate { try container.encode(true, forKey: .isEstimate) }
    }
}

/// Where a looked-up food's nutrition was published, kept with the food when it's logged or put in a recipe, so
/// it can be checked later. The values are a copy: a later change to the page doesn't change what was logged.
struct NutritionSource: Hashable, Codable {
    /// The page or document the values come from, such as "Full Nutrition Facts".
    var title: String
    var url: URL
    /// When the values were fetched, which may be earlier than when they were logged if they came from the cache.
    var retrieved: Date
    /// The country the values are published for, as a region code such as "US", if known.
    var market: String?
    /// What the published values are for, as the source says it, such as "4 oz" or "1 burrito (520 g)".
    var servingBasis: String
    /// The website it's from, such as "chipotle.com".
    var provider: String
}

/// Reads a serving's weight from how it's written on a label, such as "1 bar (30 g)".
nonisolated enum ServingWeight {
    /// What a serving's text says it weighs.
    enum Reading: Equatable {
        /// No weight in grams or kilograms, as for "1 cup", "250 mL" or "1 oz" (which could be fluid ounces).
        case unstated
        /// Exactly one weight, as in "1 bar (30 g)", "30g", "3/4 cup (170 g)", "1/2 g" or ".5 g".
        case grams(Double)
        /// A weight that isn't one amount: a range ("20-30 g"), a multiple ("2 x 15 g"), several different
        /// weights, or zero.
        case ambiguous
    }

    /// The weight in grams when the text states exactly one, and otherwise nil, so a weight is never guessed.
    static func grams(in text: String) -> Double? {
        guard case .grams(let grams) = reading(of: text) else { return nil }
        return grams
    }

    static func reading(of text: String) -> Reading {
        var text = text.lowercased()
        // Thousands separators, as in "1,000 g", and decimal commas, as in "30,5 g".
        text = text.replacing(#/(\d),(\d{3})(?!\d)/#) { "\($0.output.1)\($0.output.2)" }
        text = text.replacing(#/(\d),(\d{1,2})(?!\d)/#) { "\($0.output.1).\($0.output.2)" }
        // Each amount in grams or kilograms in full, with what comes right before or after it that would make it
        // part of a multiple ("2 x 15 g", "15 g x 2", "2 bars x 15 g") or a range ("20-30 g", "20 to 30 g").
        let weight = #/
            (?<multiple> [\d.] \s* [x×*] \s* | (?: ^ | [\s(] ) [x×] \s* )?
            (?<range> \d \s* (?: - | – | — | to ) \s* )?
            (?<amount> \d+ \s+ \d+/\d+ | \d+/\d+ | \d*\.\d+ | \d+ ) \s*
            (?<unit> kg | kilograms? | g | grams? | gr ) \b
            (?<multipliedBy> \s* [x×*] \s* \d )?
            /#
        var weights: [Double] = []
        for match in text.matches(of: weight) {
            guard match.output.multiple == nil, match.output.range == nil, match.output.multipliedBy == nil,
                  let amount = number(match.output.amount), amount.isFinite, amount > 0 else { return .ambiguous }
            weights.append(match.output.unit.hasPrefix("k") ? amount * 1000 : amount)
        }
        guard let first = weights.first else { return .unstated }
        return weights.allSatisfy { $0 == first } ? .grams(first) : .ambiguous
    }

    /// "30", "1.5", ".5", "1/2" or "1 1/2".
    private static func number(_ text: Substring) -> Double? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        if parts.count == 2 {
            guard let whole = Double(parts[0]), let fraction = number(parts[1]) else { return nil }
            return whole + fraction
        }
        let fraction = text.split(separator: "/")
        if fraction.count == 2 {
            guard let numerator = Double(fraction[0]), let denominator = Double(fraction[1]), denominator > 0 else {
                return nil
            }
            return numerator / denominator
        }
        return Double(text)
    }

    /// Whether the serving is just a weight, like "100 g", so it's more natural to enter by weight than by serving.
    static func isWeightOnly(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).lowercased()
            .wholeMatch(of: #/\d+(?:[.,]\d+)?\s*(kg|g|grams?)/#) != nil
    }
}
