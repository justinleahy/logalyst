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

/// Volume is independent of mass. Fluid ounces always name the system they belong to.
nonisolated enum VolumeUnit: String, CaseIterable, Identifiable, Codable {
    case milliliters = "mL"
    case usFluidOunces = "US fl oz"
    case imperialFluidOunces = "Imperial fl oz"

    static let millilitersPerUSFluidOunce = 29.5735295625
    static let millilitersPerImperialFluidOunce = 28.4130625

    var id: Self { self }
    var label: String { rawValue }
    var title: String {
        switch self {
        case .milliliters: "Milliliters"
        case .usFluidOunces: "U.S. fluid ounces"
        case .imperialFluidOunces: "Imperial fluid ounces"
        }
    }
    var fractionDigits: Int { self == .milliliters ? 1 : 2 }
    var step: Double { self == .milliliters ? 5 : 0.25 }

    func milliliters(from value: Double) -> Double {
        switch self {
        case .milliliters: value
        case .usFluidOunces: value * Self.millilitersPerUSFluidOunce
        case .imperialFluidOunces: value * Self.millilitersPerImperialFluidOunce
        }
    }

    func value(fromMilliliters milliliters: Double) -> Double {
        milliliters / self.milliliters(from: 1)
    }

    func format(milliliters: Double) -> String {
        let amount = value(fromMilliliters: milliliters)
            .formatted(.number.precision(.fractionLength(0...fractionDigits)))
        return "\(amount) \(label)"
    }
}

/// How many included ingredients do, and do not, state this nutrient. A recorded zero is known.
struct NutrientCoverage: Hashable, Codable {
    var known: Int
    var missing: Int
    var isUncertain = false

    var isPartial: Bool { known > 0 && missing > 0 }
    var isUnavailable: Bool { known == 0 }

    init(known: Int, missing: Int, isUncertain: Bool = false) {
        self.known = known
        self.missing = missing
        self.isUncertain = isUncertain
    }

    private enum CodingKeys: String, CodingKey { case known, missing, isUncertain }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        known = try values.decode(Int.self, forKey: .known)
        missing = try values.decode(Int.self, forKey: .missing)
        isUncertain = try values.decodeIfPresent(Bool.self, forKey: .isUncertain) ?? false
    }
}

/// Shared calculations for meals, recipes and their saved snapshots. Excluded ingredients contribute nothing.
enum FoodNutrition {
    static func totals(_ portions: [FoodPortion]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for portion in portions where portion.servings.isFinite && portion.servings > 0 {
            for id in portion.nutrients.keys {
                if let amount = portion.knownAmount(of: id) {
                    totals[id, default: 0] += amount
                }
            }
        }
        return totals
    }

    static func coverage(of metricID: String, in portions: [FoodPortion]) -> NutrientCoverage {
        var result = NutrientCoverage(known: 0, missing: 0)
        for portion in portions where portion.servings.isFinite && portion.servings > 0 {
            let coverage = portion.coverage(of: metricID)
            result.known += coverage.known
            result.missing += coverage.missing
            result.isUncertain = result.isUncertain || coverage.isUncertain
        }
        return result
    }

    static func coverage(in portions: [FoodPortion], metricIDs: [String]) -> [String: NutrientCoverage] {
        Dictionary(uniqueKeysWithValues: Set(metricIDs).map { ($0, coverage(of: $0, in: portions)) })
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
    /// Explicit volume of one serving, independent of any separately known mass.
    var millilitersPerServing: Double?
    /// The selected volume unit, or nil for servings or weight. Optional for old ingredient snapshots.
    var volumeUnit: VolumeUnit?
    /// For an aggregated recipe, the original ingredients' coverage for each nutrient. Nil on ordinary foods;
    /// their nutrient dictionary distinguishes a stated zero from an unknown value by presence of the key.
    var nutrientCoverage: [String: NutrientCoverage]?
    /// Older collapsed foods can have known subtotals without enough metadata to prove ingredient coverage.
    var coverageIsUncertain = false
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

    /// A known subtotal (possibly zero), or nil when no value was stated. Never use `amount` to infer availability.
    func knownAmount(of metricID: String) -> Double? {
        guard let amount = nutrients[metricID], amount.isFinite, amount >= 0, servings.isFinite else { return nil }
        let total = amount * servings
        return total.isFinite ? total : nil
    }

    func coverage(of metricID: String) -> NutrientCoverage {
        if let stored = nutrientCoverage?[metricID], stored.known >= 0, stored.missing >= 0 {
            // A damaged snapshot cannot claim a value is known when its value has been lost.
            if knownAmount(of: metricID) == nil {
                return NutrientCoverage(known: 0, missing: stored.known + stored.missing,
                                        isUncertain: stored.isUncertain || coverageIsUncertain)
            }
            var result = stored
            result.isUncertain = result.isUncertain || coverageIsUncertain
            return result
        }
        return NutrientCoverage(known: knownAmount(of: metricID) == nil ? 0 : 1,
                                missing: knownAmount(of: metricID) == nil && !coverageIsUncertain ? 1 : 0,
                                isUncertain: coverageIsUncertain)
    }

    /// Health food entries must contain at least one actual nutrient sample, including an explicit zero.
    var hasKnownNutrition: Bool {
        nutrients.contains { id, value in
            value.isFinite && value >= 0 && amount(of: id).isFinite
                && Metric.metrics(in: .intake).contains { $0.id == id }
        }
    }

    var calories: Double { amount(of: "dietaryEnergyConsumed") }

    /// Whether two portions are the same food, ignoring how much was eaten.
    func isSameFood(as other: FoodPortion) -> Bool {
        name.localizedCaseInsensitiveCompare(other.name) == .orderedSame
            && brand.localizedCaseInsensitiveCompare(other.brand) == .orderedSame
    }

    /// Whether the food can be entered by weight.
    var canWeigh: Bool {
        gramsPerServing.map { $0.isFinite && $0 > 0 } ?? false
    }

    var canMeasureVolume: Bool {
        millilitersPerServing.map { $0.isFinite && $0 > 0 } ?? false
    }

    var milliliters: Double? {
        canMeasureVolume ? millilitersPerServing.map { $0 * servings } : nil
    }

    var enteredVolumeUnit: VolumeUnit? {
        canMeasureVolume && enteredWeightUnit == nil ? volumeUnit : nil
    }

    /// The weight eaten, in grams, when the serving weight is known.
    var grams: Double? {
        canWeigh ? gramsPerServing.map { $0 * servings } : nil
    }

    /// The unit the amount is entered in, if it's weighed. Ignores a unit left over on a food that can't be weighed.
    var enteredWeightUnit: WeightUnit? {
        canWeigh ? weightUnit : nil
    }

    /// The amount in the unit it's entered in: servings, weight or volume. Setting it works out
    /// the servings, which is what nutrition is calculated from.
    var enteredAmount: Double {
        get {
            if let unit = enteredVolumeUnit, let milliliters {
                return unit.value(fromMilliliters: milliliters)
            }
            guard let unit = enteredWeightUnit, let grams else { return servings }
            return unit.value(fromGrams: grams)
        }
        set {
            if let unit = enteredVolumeUnit, let millilitersPerServing {
                servings = unit.milliliters(from: newValue) / millilitersPerServing
                return
            }
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
        volumeUnit = nil
    }

    /// Switches units without changing servings, and therefore without changing any nutrient amount.
    mutating func enter(volumeUnit unit: VolumeUnit?) {
        volumeUnit = canMeasureVolume ? unit : nil
        weightUnit = nil
    }

    /// "35 g" for a weighed portion, otherwise "2 × 1 cup", "1 cup" or "2 servings".
    var amountText: String {
        if let unit = enteredWeightUnit, let grams {
            return unit.format(grams: grams)
        }
        if let unit = enteredVolumeUnit, let milliliters {
            return unit.format(milliliters: milliliters)
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
        replacement.weightUnit = nil
        replacement.volumeUnit = nil
        if let unit = enteredWeightUnit, let grams {
            if replacement.canWeigh, let gramsPerServing = replacement.gramsPerServing {
                replacement.weightUnit = unit
                replacement.servings = grams / gramsPerServing
            } else {
                replacement.weightUnit = nil
                replacement.servings = 1
            }
        } else if let unit = enteredVolumeUnit, let milliliters {
            if replacement.canMeasureVolume, let millilitersPerServing = replacement.millilitersPerServing {
                replacement.volumeUnit = unit
                replacement.servings = milliliters / millilitersPerServing
            } else {
                // The caller asks the user to review a serving amount; mL must never become a serving count.
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
        case millilitersPerServing, volumeUnit, nutrientCoverage, coverageIsUncertain
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
        millilitersPerServing = (try? container.decodeIfPresent(Double.self, forKey: .millilitersPerServing)) ?? nil
        volumeUnit = (try? container.decodeIfPresent(VolumeUnit.self, forKey: .volumeUnit)) ?? nil
        nutrientCoverage = (try? container.decodeIfPresent([String: NutrientCoverage].self, forKey: .nutrientCoverage)) ?? nil
        coverageIsUncertain = (try? container.decodeIfPresent(Bool.self, forKey: .coverageIsUncertain))
            ?? (nutrientCoverage == nil)
        source = (try? container.decodeIfPresent(NutritionSource.self, forKey: .source)) ?? nil
        isEstimate = ((try? container.decodeIfPresent(Bool.self, forKey: .isEstimate)) ?? nil) ?? false
    }

    /// Optional measurement and source fields stay absent when unset. The coverage flag distinguishes a new
    /// simple ingredient from a legacy snapshot that might have collapsed a partially known recipe.
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
        try container.encodeIfPresent(millilitersPerServing, forKey: .millilitersPerServing)
        try container.encodeIfPresent(volumeUnit, forKey: .volumeUnit)
        try container.encodeIfPresent(nutrientCoverage, forKey: .nutrientCoverage)
        // The explicit false distinguishes a current simple ingredient from a legacy collapsed snapshot.
        try container.encode(coverageIsUncertain, forKey: .coverageIsUncertain)
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
        /// Exactly one weight, as in "1 bar (30 g)", "30g", "3/4 cup (170 g)", "1/2 g", "1 / 2 g" or ".5 g".
        case grams(Double)
        /// A weight that isn't one amount: a range ("20-30 g"), a multiple ("2 x 15 g", "2 x (15 g)",
        /// "15 g (x2)"), several different weights, or zero.
        case ambiguous
    }

    /// The weight in grams when the text states exactly one, and otherwise nil, so a weight is never guessed.
    static func grams(in text: String) -> Double? {
        guard case .grams(let grams) = reading(of: text) else { return nil }
        return grams
    }

    static func reading(of text: String) -> Reading {
        switch amount(in: text, volume: false) {
        case .unstated: .unstated
        case .one(let grams): .grams(grams)
        case .ambiguous: .ambiguous
        }
    }

    /// The volume in milliliters when the text states exactly one, as in "1 cup (240 mL)", read the same way as a
    /// weight, and otherwise nil.
    static func milliliters(in text: String) -> Double? {
        ServingVolume.milliliters(in: text)
    }

    private enum Amount { case unstated, one(Double), ambiguous }

    /// The one amount in grams (or for a volume, milliliters) that the text states. The whole text is read, so
    /// part of a multiple, a range or a fraction is never taken for the amount.
    private static func amount(in text: String, volume: Bool) -> Amount {
        var text = text.lowercased()
        // Thousands separators, as in "1,000 g", and decimal commas, as in "30,5 g".
        text = text.replacing(#/(\d),(\d{3})(?!\d)/#) { "\($0.output.1)\($0.output.2)" }
        text = text.replacing(#/(\d),(\d{1,2})(?!\d)/#) { "\($0.output.1).\($0.output.2)" }
        // Each amount with its unit, in full from where its number starts (after the start or anything but a digit
        // or point), with a number and dash or "to" right before it that would make it part of a range ("20-30 g",
        // "20 to 30 g").
        let measure = #/
            (?: ^ | [^\d.] )
            (?<range> (?: \d*\.\d+ | \d+ ) \s* (?: - | – | — | to ) \s* )?
            (?<amount> (?: \d+ \s+ )? \d+ \s* / \s* \d+ | \d*\.\d+ | \d+ ) \s*
            (?<unit> kg | kilograms? | g | grams? | gr | ml | milliliters? | millilitres? ) \b
            /#
        var amounts: [Double] = []
        for match in text.matches(of: measure) where match.output.unit.hasPrefix("m") == volume {
            guard match.output.range == nil, let amount = number(match.output.amount), amount.isFinite, amount > 0
            else { return .ambiguous }
            amounts.append(match.output.unit.hasPrefix("k") ? amount * 1000 : amount)
        }
        guard let first = amounts.first else { return .unstated }
        // A multiple, wherever its sign is: "2 x 15 g", "15 g x 2", "2 x (15 g)", "15 g (x2)", "2 bars x 15 g",
        // "2*15 g". An "x" counts only on its own, not in a word like "box", and "*" only between numbers, since
        // it also marks footnotes.
        if text.contains(#/(?:^|\P{L})[x×](?!\p{L})|\d\s*\*\s*\(?\s*\d/#) { return .ambiguous }
        return amounts.allSatisfy { $0 == first } ? .one(first) : .ambiguous
    }

    /// "30", "1.5", ".5", "1/2", "1 / 2" or "1 1/2".
    private static func number(_ text: Substring) -> Double? {
        let text = text.replacing(#/\s*\/\s*/#, with: "/")
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

/// Reads only stated serving volumes. Bare fluid ounces need a source-system decision; cups never imply mL.
nonisolated enum ServingVolume {
    enum Reading: Equatable {
        case unstated
        case milliliters(Double)
        case ambiguous
    }

    static func milliliters(in text: String) -> Double? {
        guard case .milliliters(let value) = reading(of: text) else { return nil }
        return value
    }

    static func reading(of text: String) -> Reading {
        var text = text.lowercased()
        text = text.replacing(#/(\d),(\d{3})(?!\d)/#) { "\($0.output.1)\($0.output.2)" }
        text = text.replacing(#/(\d),(\d{1,2})(?!\d)/#) { "\($0.output.1).\($0.output.2)" }
        let measure = #/
            (?: ^ | [^\d./] )
            (?<negative> - \s* )?
            (?<amount> (?: \d+ \s+ )? \d+ \s* / \s* \d+ | \d*\.\d+ | \d+ ) \s*
            (?<unit>
                ml | milliliters? | millilitres? | cl | centiliters? | centilitres? |
                dl | deciliters? | decilitres? | l | liters? | litres? |
                (?:(?:u\.?s\.?|imperial|u\.?k\.?) \s+)?
                (?: fl\.? \s* oz\.? | fluid \s+ ounces? )
                (?: \s* \(? (?:u\.?s\.?|imperial|u\.?k\.?) \)? )?
            ) (?!\p{L})
            /#
        let matches = text.matches(of: measure)
        guard !matches.isEmpty else { return .unstated }
        if text.contains(#/(?:^|\P{L})[x×](?!\p{L})|\d\s*\*\s*\(?\s*\d/#)
            || text.contains(#/\d\s*(?:-|–|—|to)\s*\d/#)
            || text.contains(#/(?:^|[^\d])-\s*\d/#) { return .ambiguous }
        var amounts: [Double] = []
        var unqualifiedFluidOunces = false
        for match in matches {
            guard match.output.negative == nil, let amount = number(match.output.amount), amount.isFinite,
                  amount > 0 else { return .ambiguous }
            let unit = match.output.unit.replacingOccurrences(of: ".", with: "")
            let factor: Double
            if unit.hasPrefix("m") { factor = 1 }
            else if unit.hasPrefix("c") { factor = 10 }
            else if unit.hasPrefix("d") { factor = 100 }
            else if unit.hasPrefix("l") { factor = 1000 }
            else if unit.contains("us") { factor = VolumeUnit.millilitersPerUSFluidOunce }
            else if unit.contains("imperial") || unit.contains("uk") {
                factor = VolumeUnit.millilitersPerImperialFluidOunce
            } else {
                unqualifiedFluidOunces = true
                continue
            }
            let milliliters = amount * factor
            guard milliliters.isFinite else { return .ambiguous }
            amounts.append(milliliters)
        }
        // An explicit mL equivalent such as "8 fl oz (240 mL)" supplies the basis without guessing the ounces.
        guard let first = amounts.first else { return unqualifiedFluidOunces ? .ambiguous : .unstated }
        return amounts.allSatisfy { abs($0 - first) < 0.000_001 } ? .milliliters(first) : .ambiguous
    }

    static func isVolumeOnly(_ text: String) -> Bool {
        guard milliliters(in: text) != nil else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().wholeMatch(of: #/
            (?: (?: \d+ \s+ )? \d+ \s* / \s* \d+ | \d*\.\d+ | \d+ ) \s*
            (?: ml | milliliters? | millilitres? | cl | centiliters? | centilitres? |
                dl | deciliters? | decilitres? | l | liters? | litres? |
                (?:u\.?s\.?|imperial|u\.?k\.?) \s+ (?:fl\.? \s* oz\.?|fluid \s+ ounces?) )
            /#) != nil
    }

    private static func number(_ text: Substring) -> Double? {
        let text = text.replacing(#/\s*\/\s*/#, with: "/")
        let parts = text.split(whereSeparator: \.isWhitespace)
        if parts.count == 2 {
            guard let whole = Double(parts[0]), let fraction = number(parts[1]) else { return nil }
            return whole + fraction
        }
        let fraction = text.split(separator: "/")
        if fraction.count == 2 {
            guard let numerator = Double(fraction[0]), let denominator = Double(fraction[1]), denominator > 0
            else { return nil }
            return numerator / denominator
        }
        return Double(text)
    }
}
