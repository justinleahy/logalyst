#if DEBUG
import SwiftData
import SwiftUI

/// Launched with `-SeedScreenshotData YES` in a fresh simulator, fills Health and My Foods with a believable
/// week of entries for App Store screenshots. Runs once per install.
enum ScreenshotData {
    private static let seededKey = "didSeedScreenshotData"

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "SeedScreenshotData") && !UserDefaults.standard.bool(forKey: seededKey)
    }

    @MainActor
    static func seed(health: HealthStore, goals: NutritionGoals, context: ModelContext) async {
        guard isRequested else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        // US units throughout, and a water goal that 16 fl oz glasses divide evenly.
        if let flOz = Metric.water.unitOptions.first(where: { $0.label == "fl oz" }) {
            health.setUnitOverride(flOz, for: Metric.water)
            goals.setGoal(80, for: Metric.water, in: flOz)
        }

        let foods = savedFoods.map { draft in
            let food = Food(draft)
            context.insert(food)
            return food
        }
        foods.first { $0.name == "Greek Yogurt" }?.isFavorite = true
        foods.first { $0.name == "Cold Brew Coffee" }?.isFavorite = true
        try? context.save()
        let food = { (name: String) in foods.first { $0.name == name }!.portion }

        for id in ["dietaryWater", "bloodPressure", "bodyMass", "bloodGlucose", "dietaryCaffeine"] {
            if let metric = Metric.metric(id: id), !health.isFavorite(metric) { health.toggleFavorite(metric) }
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            return min(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!, .now.addingTimeInterval(-60))
        }
        func quantity(_ id: String, _ value: Double, _ label: String, _ date: Date) async {
            guard let metric = Metric.metric(id: id), let option = metric.unitOptions.first(where: { $0.label == label })
            else { return }
            try? await health.saveQuantity(metric, value: value, option: option, date: date)
        }
        func eat(_ names: [String], servings: Double = 1, _ meal: Meal, _ date: Date) async {
            let portions = names.map { var portion = food($0); portion.servings = servings; return portion }
            try? await health.saveFoods(portions, meal: meal, date: date)
        }

        // Past week, so the 7-day charts and history have some shape.
        let waterByDay: [Double] = [0, 64, 72, 56, 80, 68, 76]
        for daysAgo in 1...6 {
            let glasses = waterByDay[daysAgo] / 16
            for glass in 0..<Int(glasses) { await quantity("dietaryWater", 16, "fl oz", at(daysAgo, 8 + glass * 3)) }
            await eat(["Oatmeal", "Banana"], .breakfast, at(daysAgo, 7, 45))
            await eat(["Cold Brew Coffee"], .breakfast, at(daysAgo, 8, 10))
            await eat([daysAgo.isMultiple(of: 2) ? "Turkey Sandwich" : "Grilled Chicken Salad"], .lunch, at(daysAgo, 12, 30))
            await eat([daysAgo.isMultiple(of: 3) ? "Pasta Primavera" : "Salmon & Rice Bowl"], .dinner, at(daysAgo, 18, 45))
            if daysAgo.isMultiple(of: 2) { await eat(["Almonds"], .snack, at(daysAgo, 15, 30)) }
        }
        for (daysAgo, pounds) in [(13, 178.2), (11, 177.6), (9, 177.4), (7, 176.8), (5, 176.2), (3, 175.8), (1, 175.4)] {
            await quantity("bodyMass", pounds, "lb", at(daysAgo, 7, 5))
        }
        for (daysAgo, systolic, diastolic) in [(6, 124.0, 81.0), (4, 121.0, 79.0), (2, 119.0, 78.0), (0, 117.0, 76.0)] {
            try? await health.saveBloodPressure(systolic: systolic, diastolic: diastolic, date: at(daysAgo, 7, 20))
        }
        for (daysAgo, glucose) in [(5, 98.0), (3, 104.0), (1, 95.0), (0, 92.0)] {
            await quantity("bloodGlucose", glucose, "mg/dL", at(daysAgo, 7, 25))
        }
        if let headache = Metric.metric(id: "HKCategoryTypeIdentifierHeadache") {
            try? await health.saveSymptom(headache, severity: .mild, start: at(2, 14, 10), end: at(2, 15, 40))
        }

        // Today: partway to the water goal, with breakfast, lunch and a snack logged.
        await quantity("bodyMass", 175.2, "lb", at(0, 7, 5))
        for (hour, minute) in [(7, 30), (9, 45), (12, 40), (15, 10)] { await quantity("dietaryWater", 16, "fl oz", at(0, hour, minute)) }
        await eat(["Greek Yogurt", "Blueberries"], .breakfast, at(0, 7, 50))
        await eat(["Cold Brew Coffee"], .breakfast, at(0, 8, 5))
        await eat(["Grilled Chicken Salad"], .lunch, at(0, 12, 35))
        await eat(["Almonds"], .snack, at(0, 15, 30))
        if let brushing = Metric.metric(id: "HKCategoryTypeIdentifierToothbrushingEvent") {
            try? await health.saveTimedEvent(brushing, duration: 120, end: at(0, 7, 15))
        }
    }

    private static let savedFoods: [FoodDraft] = [
        FoodDraft(name: "Greek Yogurt", brand: "Fage", servingSize: "3/4 cup (170 g)", nutrients: [
            "dietaryEnergyConsumed": 150, "dietaryProtein": 17, "dietaryCarbohydrates": 6, "dietaryFatTotal": 7,
            "dietaryFatSaturated": 4.5, "dietarySugar": 6, "dietaryCholesterol": 20, "dietarySodium": 65]),
        FoodDraft(name: "Blueberries", servingSize: "1 cup", nutrients: [
            "dietaryEnergyConsumed": 85, "dietaryProtein": 1, "dietaryCarbohydrates": 21, "dietaryFatTotal": 0.5,
            "dietarySugar": 15, "dietaryFiber": 3.6]),
        FoodDraft(name: "Cold Brew Coffee", brand: "Stumptown", servingSize: "10.5 fl oz", nutrients: [
            "dietaryEnergyConsumed": 5, "dietaryCaffeine": 200, "dietarySodium": 10]),
        FoodDraft(name: "Grilled Chicken Salad", servingSize: "1 bowl", nutrients: [
            "dietaryEnergyConsumed": 430, "dietaryProtein": 38, "dietaryCarbohydrates": 18, "dietaryFatTotal": 22,
            "dietaryFatSaturated": 4, "dietarySugar": 7, "dietaryFiber": 6, "dietaryCholesterol": 95,
            "dietarySodium": 720]),
        FoodDraft(name: "Almonds", brand: "Blue Diamond", servingSize: "1 oz (28 g)", nutrients: [
            "dietaryEnergyConsumed": 170, "dietaryProtein": 6, "dietaryCarbohydrates": 6, "dietaryFatTotal": 15,
            "dietaryFatSaturated": 1, "dietarySugar": 1, "dietaryFiber": 3]),
        FoodDraft(name: "Oatmeal", brand: "Quaker", servingSize: "1/2 cup dry", nutrients: [
            "dietaryEnergyConsumed": 150, "dietaryProtein": 5, "dietaryCarbohydrates": 27, "dietaryFatTotal": 3,
            "dietarySugar": 1, "dietaryFiber": 4]),
        FoodDraft(name: "Banana", servingSize: "1 medium", nutrients: [
            "dietaryEnergyConsumed": 105, "dietaryProtein": 1.3, "dietaryCarbohydrates": 27, "dietaryFatTotal": 0.4,
            "dietarySugar": 14, "dietaryFiber": 3.1]),
        FoodDraft(name: "Turkey Sandwich", servingSize: "1 sandwich", nutrients: [
            "dietaryEnergyConsumed": 380, "dietaryProtein": 28, "dietaryCarbohydrates": 40, "dietaryFatTotal": 11,
            "dietaryFatSaturated": 3, "dietarySugar": 6, "dietaryFiber": 5, "dietaryCholesterol": 50,
            "dietarySodium": 980]),
        FoodDraft(name: "Salmon & Rice Bowl", servingSize: "1 bowl", nutrients: [
            "dietaryEnergyConsumed": 610, "dietaryProtein": 40, "dietaryCarbohydrates": 62, "dietaryFatTotal": 21,
            "dietaryFatSaturated": 4, "dietarySugar": 8, "dietaryFiber": 5, "dietaryCholesterol": 85,
            "dietarySodium": 820]),
        FoodDraft(name: "Pasta Primavera", servingSize: "1 1/2 cups", nutrients: [
            "dietaryEnergyConsumed": 540, "dietaryProtein": 18, "dietaryCarbohydrates": 78, "dietaryFatTotal": 17,
            "dietaryFatSaturated": 5, "dietarySugar": 9, "dietaryFiber": 7, "dietarySodium": 640]),
    ]
}
#endif
