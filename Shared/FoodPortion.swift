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

/// One food as it goes into Health: its nutrition per serving and how many servings were eaten.
/// Built from a saved food, or read back from a past food entry so it can be logged again.
struct FoodPortion: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var brand = ""
    /// Free text from the label, e.g. "1 cup" or "30 g".
    var servingSize = ""
    /// Amount per serving keyed by metric ID, in each metric's first unit option (kcal, g, mg).
    var nutrients: [String: Double]
    var servings = 1.0

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
}
