import Foundation

/// What Suggest Goals needs to estimate someone's daily water, calories and nutrients.
struct BodyProfile {
    enum Sex: String, CaseIterable, Identifiable {
        case female, male, other

        var id: Self { self }

        var title: String {
            switch self {
            case .female: "Female"
            case .male: "Male"
            case .other: "Other"
            }
        }

        /// The Mifflin–St Jeor constant. Other uses the midpoint of the two.
        var formulaConstant: Double {
            switch self {
            case .female: -161
            case .male: 5
            case .other: -78
            }
        }

        /// The lowest calorie goal suggested, so a weight-loss goal is never a crash diet.
        var calorieFloor: Double {
            self == .male ? 1500 : 1200
        }

        /// Water from drinks a day in mL: about 80% of the US National Academies' adequate intake of total water
        /// (2.7 L for women, 3.7 L for men), since food supplies the rest. Other uses the midpoint of the two.
        var drinkingWater: Double {
            switch self {
            case .female: 2200
            case .male: 3000
            case .other: 2600
            }
        }
    }

    enum Activity: String, CaseIterable, Identifiable {
        case sedentary, light, moderate, active, veryActive

        var id: Self { self }

        var title: String {
            switch self {
            case .sedentary: "Sedentary"
            case .light: "Lightly Active"
            case .moderate: "Moderately Active"
            case .active: "Very Active"
            case .veryActive: "Extremely Active"
            }
        }

        var detail: String {
            switch self {
            case .sedentary: "Little or no exercise"
            case .light: "Light exercise 1–3 days a week"
            case .moderate: "Moderate exercise 3–5 days a week"
            case .active: "Hard exercise 6–7 days a week"
            case .veryActive: "Hard daily exercise and a physical job"
            }
        }

        /// Multiplier from resting calories to a typical day's calories.
        var factor: Double {
            switch self {
            case .sedentary: 1.2
            case .light: 1.375
            case .moderate: 1.55
            case .active: 1.725
            case .veryActive: 1.9
            }
        }

        /// Extra water in mL a day to replace sweat lost to exercise, averaged over the week.
        var extraWater: Double {
            switch self {
            case .sedentary: 0
            case .light: 250
            case .moderate: 500
            case .active: 750
            case .veryActive: 1000
            }
        }
    }

    enum Aim: String, CaseIterable, Identifiable {
        case lose, maintain, gain

        var id: Self { self }

        var title: String {
            switch self {
            case .lose: "Lose"
            case .maintain: "Maintain"
            case .gain: "Gain"
            }
        }
    }

    /// Suggestions are for adults; children's needs change as they grow.
    static let adultAges = 18...110
    static let weightRange = 30.0...300.0
    static let heightRange = 100.0...250.0

    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: Sex
    var activity: Activity
    var aim: Aim
    /// Resting energy measured by Apple Watch, used instead of the equation when present.
    var measuredRestingCalories: Double?

    /// Calories burned at rest, from the Mifflin–St Jeor equation.
    var estimatedRestingCalories: Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + sex.formulaConstant
    }

    var restingCalories: Double {
        measuredRestingCalories ?? estimatedRestingCalories
    }

    /// Calories burned on a typical day at this activity level.
    var maintenanceCalories: Double {
        restingCalories * activity.factor
    }
}

/// Daily goals estimated from a body profile, in each metric's first unit option (mL, kcal and grams).
struct SuggestedGoals {
    static let deficit = 500.0
    static let surplus = 300.0
    static let proteinPerKg = 1.6
    static let maintenanceProteinPerKg = 1.2

    let water: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugar: Double
    let fiber: Double

    init(_ profile: BodyProfile) {
        // Water doesn't depend on the weight goal.
        water = ((profile.sex.drinkingWater + profile.activity.extraWater) / 100).rounded() * 100
        let maintenance = profile.maintenanceCalories
        let target = switch profile.aim {
        // Cap the deficit at 20% so smaller, less active people aren't cut too hard.
        case .lose: maintenance - min(Self.deficit, maintenance * 0.2)
        case .maintain: maintenance
        case .gain: maintenance + Self.surplus
        }
        calories = (max(target, profile.sex.calorieFloor) / 50).rounded() * 50
        // More protein while losing or gaining helps keep or build muscle. Capped at 35% of calories,
        // the top of the recommended range, so heavier people aren't told to eat mostly protein.
        let perKg = profile.aim == .maintain ? Self.maintenanceProteinPerKg : Self.proteinPerKg
        protein = (min(profile.weightKg * perKg, calories * 0.35 / 4) / 5).rounded() * 5
        fat = (calories * 0.3 / 9).rounded()
        carbs = ((calories - protein * 4 - fat * 9) / 4).rounded()
        sugar = (calories * 0.1 / 4).rounded()
        fiber = (calories / 1000 * 14).rounded()
    }

    /// Goals keyed by metric ID, for `NutritionGoals.setGoals`.
    var amounts: [String: Double] {
        [
            "dietaryWater": water,
            "dietaryEnergyConsumed": calories,
            "dietaryProtein": protein,
            "dietaryCarbohydrates": carbs,
            "dietaryFatTotal": fat,
            "dietarySugar": sugar,
            "dietaryFiber": fiber,
        ]
    }
}
