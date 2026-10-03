import AppIntents
import CoreData
import SwiftData

// Siri and Shortcuts actions for saved foods, recipes and recent meals. iPhone only: saved foods and recipes are
// kept by the iPhone app, and the Watch doesn't have them.

/// A saved food or recipe, for Siri and Shortcuts. It's identified by its name (and brand), the way the app tells
/// foods apart, so a shortcut keeps working on the user's other iPhones, where iCloud brings the same foods.
struct SavedFoodEntity: AppEntity {
    let id: String
    let name: String
    let detail: String
    let isRecipe: Bool

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food")
    static let defaultQuery = SavedFoodQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)",
                              image: .init(systemName: isRecipe ? "book.closed" : "fork.knife"))
    }

    @MainActor
    init(_ food: Food) {
        id = Self.id(food: food.name, brand: food.brand)
        name = food.name
        detail = food.summary
        isRecipe = false
    }

    @MainActor
    init(_ recipe: Recipe) {
        id = Self.id(recipe: recipe.name)
        name = recipe.name
        detail = recipe.summary
        isRecipe = true
    }

    private static func id(food name: String, brand: String) -> String {
        ["food", name.lowercased(), brand.lowercased()].joined(separator: "\u{1F}")
    }

    private static func id(recipe name: String) -> String {
        ["recipe", name.lowercased()].joined(separator: "\u{1F}")
    }

    /// The saved food or recipe this stands for: one serving of it, and how to mark it as just logged. Nil if it
    /// was deleted or renamed. If two have the same name, the one logged most recently.
    @MainActor
    func resolve(in context: ModelContext) -> (portion: FoodPortion, markLogged: () -> Void)? {
        if isRecipe {
            let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
            guard let recipe = recipes.filter({ Self.id(recipe: $0.name) == id }).max(by: Self.loggedEarlier) else {
                return nil
            }
            return (recipe.portion, { recipe.lastLogged = .now })
        }
        let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        guard let food = foods.filter({ Self.id(food: $0.name, brand: $0.brand) == id }).max(by: Self.loggedEarlier)
        else { return nil }
        return (food.portion, { food.lastLogged = .now })
    }

    private static func loggedEarlier(_ a: Food, _ b: Food) -> Bool {
        (a.lastLogged ?? .distantPast) < (b.lastLogged ?? .distantPast)
    }

    private static func loggedEarlier(_ a: Recipe, _ b: Recipe) -> Bool {
        (a.lastLogged ?? .distantPast) < (b.lastLogged ?? .distantPast)
    }
}

/// Finds saved foods and recipes by name. A name that matches several, like "yogurt", returns them all, so Siri and
/// Shortcuts ask which one.
struct SavedFoodQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [SavedFoodEntity.ID]) async throws -> [SavedFoodEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    /// Foods whose name has every word said, in any order, or that's said in full within a longer phrase.
    @MainActor
    func entities(matching string: String) async throws -> [SavedFoodEntity] {
        let words = string.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return all().filter { food in
            words.allSatisfy { food.name.localizedStandardContains($0) } || string.localizedStandardContains(food.name)
        }
    }

    /// Favorites, then the most recently logged, then the rest. These are also the names Siri listens for.
    @MainActor
    func suggestedEntities() async throws -> [SavedFoodEntity] {
        all()
    }

    @MainActor
    private func all() -> [SavedFoodEntity] {
        let context = HealthLoggerApp.sharedContainer.mainContext
        let foods = ((try? context.fetch(FetchDescriptor<Food>())) ?? []).sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            let (dateA, dateB) = (a.lastLogged ?? .distantPast, b.lastLogged ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let recipes = ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).sorted {
            ($0.lastLogged ?? .distantPast) > ($1.lastLogged ?? .distantPast)
        }
        var seen: Set<String> = []
        return (foods.map(SavedFoodEntity.init) + recipes.map(SavedFoodEntity.init)).filter { seen.insert($0.id).inserted }
    }
}

/// A meal, as Siri and Shortcuts offer it.
enum MealChoice: String, AppEnum {
    case breakfast, lunch, dinner, snack

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static let caseDisplayRepresentations: [MealChoice: DisplayRepresentation] = [
        .breakfast: DisplayRepresentation(title: "Breakfast", image: .init(systemName: "sunrise")),
        .lunch: DisplayRepresentation(title: "Lunch", image: .init(systemName: "sun.max")),
        .dinner: DisplayRepresentation(title: "Dinner", image: .init(systemName: "moon.stars")),
        .snack: DisplayRepresentation(title: "Snack", image: .init(systemName: "carrot")),
    ]

    var meal: Meal { Meal(rawValue: rawValue) ?? .snack }
}

/// Logs a saved food or recipe by the serving, as the Log screen would.
struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription(
        "Logs one of your saved foods or recipes to the Health app, by the serving, at a meal.")
    /// Health data can't be written while the phone is locked, and a locked phone shouldn't log on your behalf.
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Food", requestValueDialog: "Which food?")
    var food: SavedFoodEntity

    @Parameter(title: "Servings", default: 1, inclusiveRange: (0.1, 50))
    var servings: Double

    /// The usual meal for the time of day when missing.
    @Parameter(title: "Meal")
    var meal: MealChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$servings) servings of \(\.$food)") {
            \.$meal
        }
    }

    init() {}

    init(food: SavedFoodEntity, servings: Double = 1, meal: MealChoice? = nil) {
        self.food = food
        self.servings = servings
        self.meal = meal
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = HealthLoggerApp.sharedContainer.mainContext
        guard let saved = food.resolve(in: context) else {
            throw IntentMessage("\(food.name) isn't one of your foods any more.")
        }
        guard servings > 0, servings <= 50 else {
            throw IntentMessage("Log between 0.1 and 50 servings.")
        }
        var portion = saved.portion
        portion.servings = servings
        portion.weightUnit = nil
        let meal = meal?.meal ?? Meal(at: .now)
        let health = await HealthStore.standalone()
        try await health.saveFoods([portion], meal: meal, date: .now)
        saved.markLogged()
        try? context.save()
        let calories = portion.calories.formatted(.number.precision(.fractionLength(0)))
        return .result(dialog: "Logged \(portion.amountText) of \(portion.name), \(calories) kcal, at \(meal.title.lowercased()).")
    }
}

/// Logs the foods of the last breakfast, lunch, dinner or snack before today again, now. Recent meals have no
/// names, so they're chosen by meal: "Log my last breakfast again".
struct LogRecentMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Last Meal Again"
    static let description = IntentDescription(
        "Logs the foods from your last breakfast, lunch, dinner or snack before today again, now, at the same meal.")
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Meal", requestValueDialog: "Which meal?")
    var meal: MealChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Log my last \(\.$meal) again")
    }

    init() {}

    init(meal: MealChoice) {
        self.meal = meal
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let meal = meal.meal
        let health = await HealthStore.standalone()
        let since = Calendar.current.date(byAdding: .day, value: -Recents.days, to: .now)!
        let entries = try await health.recentEntries(of: [], since: since, limit: 500)
        guard let last = Recents.lastMeal(meal, in: entries) else {
            throw IntentMessage("There's no \(meal.title.lowercased()) from the last \(Recents.days) days to log again.")
        }
        try await health.saveFoods(last.foods, meal: meal, date: .now)
        let context = HealthLoggerApp.sharedContainer.mainContext
        Food.markLogged(last.foods, among: (try? context.fetch(FetchDescriptor<Food>())) ?? [])
        try? context.save()
        let names = last.foods.map(\.name).formatted(.list(type: .and))
        let calories = last.foods.map(\.calories).reduce(0, +).formatted(.number.precision(.fractionLength(0)))
        return .result(dialog: "Logged \(meal.title.lowercased()) from \(last.dayText.lowercased()) again: \(names), \(calories) kcal.")
    }
}

/// Keeps Siri's list of food names current. Siri learns the names a phrase can hold from the app, which otherwise
/// tells it only at launch, so this tells it again when foods or recipes change, here or from iCloud.
@MainActor
final class FoodShortcutNames {
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    init() {
        let center = NotificationCenter.default
        for name in [ModelContext.didSave, .NSPersistentStoreRemoteChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleUpdate() }
            })
        }
    }

    /// Waits for a burst of saves (or a sync) to settle.
    private func scheduleUpdate() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            HealthLoggerShortcuts.updateAppShortcutParameters()
        }
    }
}
