import Foundation
import HealthKit
import SwiftData
import Testing
@testable import HealthLogger

/// Siri and Shortcuts food actions, run against the app's own store and the simulator's Health store. Each test uses
/// foods with its own names and removes them afterwards.
@MainActor
@Suite(.serialized)
final class FoodIntentTests {
    private let context = HealthLoggerApp.sharedContainer.mainContext
    private let health = HealthStore(syncs: false)
    private let tag = String(UUID().uuidString.prefix(6))
    private var made: [Food] = []
    private var madeRecipes: [Recipe] = []

    init() throws {
        let status = HKHealthStore().authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed))
        try #require(status == .sharingAuthorized, "Open Logalyst in this simulator and allow Health access first.")
    }

    private func food(_ name: String, brand: String = "", calories: Double = 200) -> Food {
        let food = Food(FoodDraft(name: "\(name) \(tag)", brand: brand, servingSize: "1 bowl",
                                  nutrients: ["dietaryEnergyConsumed": calories, "dietaryProtein": 10]))
        context.insert(food)
        made.append(food)
        return food
    }

    private func entries(named names: [String], since start: Date) async throws -> [LoggedEntry] {
        try await health.recentEntries(of: [], since: start).filter { names.contains($0.title) }
    }

    private func cleanUp(names: [String], since start: Date) async throws {
        for entry in try await entries(named: names, since: start) { try await health.delete(entry) }
        made.forEach(context.delete)
        madeRecipes.forEach(context.delete)
        try context.save()
    }

    @Test func foodsAreFoundByNameAndAmbiguousNamesOfferEach() async throws {
        let greek = food("Greek Yogurt")
        let vanilla = food("Vanilla Yogurt")
        _ = food("Granola")
        let recipe = Recipe(name: "Yogurt Bowl \(tag)", servings: 2, ingredients: [greek.portion])
        context.insert(recipe)
        madeRecipes.append(recipe)
        try context.save()

        let query = SavedFoodQuery()
        let yogurts = try await query.entities(matching: "yogurt \(tag)")
        #expect(Set(yogurts.map(\.name)) == [greek.name, vanilla.name, recipe.name])
        #expect(try await query.entities(matching: "Granola \(tag)").map(\.name) == ["Granola \(tag)"])

        // A shortcut saved with an entity finds it again by ID, and a deleted food is no longer found.
        let saved = try #require(yogurts.first { $0.name == greek.name })
        #expect(try await query.entities(for: [saved.id]).map(\.name) == [greek.name])
        #expect(try await query.suggestedEntities().contains { $0.id == saved.id })
        context.delete(greek)
        made.removeAll { $0 === greek }
        try context.save()
        #expect(try await query.entities(for: [saved.id]).isEmpty)
        try await cleanUp(names: [], since: .now)
    }

    @Test func logFoodSavesItAndMarksItLogged() async throws {
        let start = Date.now.addingTimeInterval(-60)
        let oats = food("Oats", brand: "Quaker", calories: 150)
        try context.save()
        let entity = SavedFoodEntity(oats)

        let intent = LogFoodIntent(food: entity, servings: 2, meal: .breakfast)
        _ = try await intent.perform()

        let logged = try await entries(named: [oats.name], since: start)
        #expect(logged.count == 1)
        #expect(logged.first?.food?.calories == 300)
        #expect(logged.first?.food?.servings == 2)
        #expect(logged.first?.food?.brand == "Quaker")
        #expect(logged.first?.meal == .breakfast)
        #expect(oats.lastLogged.map { $0 > start } == true)
        try await cleanUp(names: [oats.name], since: start)
    }

    /// Two saved foods with the same name and brand are each offered, and the one picked is the one logged, even
    /// when the other was logged more recently.
    @Test func duplicateFoodsAreEachOfferedAndLoggedAsThemselves() async throws {
        let start = Date.now.addingTimeInterval(-60)
        let favorite = food("Oats", brand: "Quaker", calories: 200)
        favorite.isFavorite = true
        favorite.created = .now.addingTimeInterval(-3600)
        let other = food("Oats", brand: "Quaker", calories: 100)
        other.lastLogged = .now.addingTimeInterval(-120)
        try context.save()

        let offered = try await SavedFoodQuery().entities(matching: favorite.name)
        #expect(offered.count == 2)
        #expect(Set(offered.map(\.id)).count == 2)
        let picked = try #require(offered.first)
        #expect(picked.detail.contains("200 kcal"))
        #expect(try await SavedFoodQuery().entities(for: [picked.id]).map(\.detail) == [picked.detail])

        _ = try await LogFoodIntent(food: picked, meal: .snack).perform()
        let logged = try await entries(named: [favorite.name], since: start)
        #expect(logged.map { $0.food?.calories } == [200])
        try await cleanUp(names: [favorite.name], since: start)
    }

    @Test func duplicateRecipesAreEachOffered() async throws {
        let ingredient = food("Rice")
        let first = Recipe(name: "Rice Bowl \(tag)", servings: 1, ingredients: [ingredient.portion])
        first.created = .now.addingTimeInterval(-3600)
        let second = Recipe(name: "Rice Bowl \(tag)", servings: 2, ingredients: [ingredient.portion])
        for recipe in [first, second] {
            context.insert(recipe)
            madeRecipes.append(recipe)
        }
        try context.save()
        let offered = try await SavedFoodQuery().entities(matching: first.name).filter(\.isRecipe)
        #expect(Set(offered.map(\.id)).count == 2)
        try await cleanUp(names: [], since: .now)
    }

    /// Two foods with the same name and brand created within the same millisecond are still told apart: the one
    /// offered is the one logged.
    @Test func foodsCreatedTogetherAreToldApart() async throws {
        let start = Date.now.addingTimeInterval(-60)
        let time = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 3600).rounded())
        let favorite = food("Oats", brand: "Quaker", calories: 200)
        favorite.isFavorite = true
        favorite.created = time.addingTimeInterval(0.0004)
        let other = food("Oats", brand: "Quaker", calories: 100)
        other.created = time.addingTimeInterval(0.0001)
        try context.save()

        let offered = try await SavedFoodQuery().entities(matching: favorite.name)
        #expect(offered.count == 2)
        let picked = try #require(offered.first)
        #expect(picked.detail.contains("200 kcal"))
        #expect(SavedFoodEntity.food(for: picked.id, in: [other, favorite]) === favorite)
        _ = try await LogFoodIntent(food: picked, meal: .snack).perform()
        #expect(try await entries(named: [favorite.name], since: start).map { $0.food?.calories } == [200])
        try await cleanUp(names: [favorite.name], since: start)
    }

    /// A shortcut whose food was deleted reports it, rather than logging another food with the same name created
    /// moments later.
    @Test func aDeletedFoodIsNotReplacedByOneWithTheSameName() async throws {
        let time = Date.now.addingTimeInterval(-3600)
        let deleted = food("Oats", brand: "Quaker")
        deleted.created = time
        let remaining = food("Oats", brand: "Quaker")
        remaining.created = time.addingTimeInterval(0.5)
        try context.save()
        let id = SavedFoodEntity(deleted).id
        context.delete(deleted)
        made.removeAll { $0 === deleted }
        try context.save()

        #expect(SavedFoodEntity.food(for: id, in: [remaining]) == nil)
        #expect(try await SavedFoodQuery().entities(for: [id]).isEmpty)
        try await cleanUp(names: [], since: .now)
    }

    /// A food saved before 1.1 has no permanent ID until Siri and Shortcuts first look for it, and then keeps it.
    @Test func anOlderFoodGetsAPermanentID() async throws {
        let older = food("Granola")
        older.uuid = nil
        try context.save()

        let offered = try #require(try await SavedFoodQuery().entities(matching: older.name).first)
        let uuid = try #require(older.uuid)
        #expect(offered.id == uuid.uuidString)
        #expect(context.hasChanges == false)
        #expect(try await SavedFoodQuery().entities(for: [offered.id]).map(\.name) == [older.name])
        try await cleanUp(names: [], since: .now)
    }

    @Test func aFoodThatsGoneIsReportedAndNothingIsLogged() async throws {
        let start = Date.now.addingTimeInterval(-60)
        let gone = food("Gone")
        try context.save()
        let entity = SavedFoodEntity(gone)
        context.delete(gone)
        made.removeAll()
        try context.save()

        await #expect(throws: IntentMessage.self) { _ = try await LogFoodIntent(food: entity).perform() }
        #expect(try await entries(named: [entity.name], since: start).isEmpty)
        try await cleanUp(names: [], since: start)
    }

    /// "Log my last snack again": the most recent snack before today, all its foods, now.
    @Test func theLastMealBeforeTodayIsLoggedAgain() async throws {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        let snackTime = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: yesterday)!
        let apple = FoodPortion(name: "Apple \(tag)", servingSize: "1 medium", nutrients: ["dietaryEnergyConsumed": 95])
        var cheese = FoodPortion(name: "Cheese \(tag)", servingSize: "1 slice", nutrients: ["dietaryEnergyConsumed": 110])
        cheese.servings = 2
        try await health.saveFoods([apple, cheese], meal: .snack, date: snackTime)
        let start = Date.now.addingTimeInterval(-60)

        _ = try await LogRecentMealIntent(meal: .snack).perform()

        let today = try await entries(named: [apple.name, cheese.name], since: start)
        #expect(Set(today.map(\.title)) == [apple.name, cheese.name])
        #expect(today.allSatisfy { $0.meal == .snack })
        #expect(today.first { $0.title == cheese.name }?.food?.servings == 2)
        try await cleanUp(names: [apple.name, cheese.name], since: snackTime.addingTimeInterval(-60))
    }

    /// However much else was logged since, the whole of the last snack is logged again. 500 newer entries were
    /// once enough to hide it.
    @Test func theLastMealIsWholeAfterManyNewerEntries() async throws {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))!
        let snackTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: yesterday)!
        let apple = FoodPortion(name: "Apple \(tag)", servingSize: "1 medium", nutrients: ["dietaryEnergyConsumed": 95])
        let cheese = FoodPortion(name: "Cheese \(tag)", servingSize: "1 slice", nutrients: ["dietaryEnergyConsumed": 110])
        try await health.saveFoods([apple, cheese], meal: .snack, date: snackTime)
        let filler = FoodPortion(name: "Filler \(tag)", nutrients: ["dietaryEnergyConsumed": 1])
        try await health.saveFoods(Array(repeating: filler, count: 500), meal: .lunch,
                                   date: snackTime.addingTimeInterval(3600))
        let start = Date.now.addingTimeInterval(-60)

        _ = try await LogRecentMealIntent(meal: .snack).perform()

        let today = try await entries(named: [apple.name, cheese.name], since: start)
        #expect(Set(today.map(\.title)) == [apple.name, cheese.name])
        // Remove all 504 entries at once.
        let names = [apple.name, cheese.name, filler.name]
        let ours = try await health.recentEntries(of: [], since: snackTime.addingTimeInterval(-60), limit: nil)
            .filter { names.contains($0.title) }
        let objects = ours.flatMap { [$0.sample] + Array(($0.sample as? HKCorrelation)?.objects ?? []) }
        try await HKHealthStore().delete(objects)
        try await cleanUp(names: names, since: snackTime.addingTimeInterval(-60))
    }

    @Test func recentMealsChooseByMealAndSkipToday() {
        func entry(_ name: String, _ meal: Meal, daysAgo: Int, hour: Int) -> LoggedEntry {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            let sample = HKQuantitySample(type: HKQuantityType(.dietaryEnergyConsumed),
                                          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 100), start: date, end: date)
            return LoggedEntry(sample: sample, metric: nil, title: name, systemImage: "fork.knife", valueText: "100 kcal",
                               food: FoodPortion(name: name, nutrients: ["dietaryEnergyConsumed": 100]), meal: meal)
        }
        let entries = [
            entry("Toast", .breakfast, daysAgo: 0, hour: 8),
            entry("Eggs", .breakfast, daysAgo: 2, hour: 8), entry("Juice", .breakfast, daysAgo: 2, hour: 8),
            entry("Soup", .lunch, daysAgo: 1, hour: 12),
        ]
        #expect(Recents.lastMeal(.breakfast, in: entries)?.foods.map(\.name).sorted() == ["Eggs", "Juice"])
        #expect(Recents.lastMeal(.lunch, in: entries)?.foods.map(\.name) == ["Soup"])
        #expect(Recents.lastMeal(.dinner, in: entries) == nil)
        // Add Food's recent meals still need two foods.
        #expect(Recents.meals(in: entries, limit: 5).map(\.meal) == [.breakfast])
    }
}
