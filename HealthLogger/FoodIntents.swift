import AppIntents
import CoreData
import SwiftData

// Siri and Shortcuts actions for saved foods, recipes and recent meals. iPhone only: saved foods and recipes are
// kept by the iPhone app, and the Watch doesn't have them.

/// A saved food or recipe, for Siri and Shortcuts. It's identified by its name (and brand) and when it was created,
/// which iCloud brings to the user's other iPhones with it, so a shortcut keeps working there, and two foods with
/// the same name are each offered and each logged as themselves.
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

    /// Pass an `id` to keep the one a shortcut was saved with, which may differ slightly from this record's.
    @MainActor
    init(_ food: Food, id: String? = nil) {
        self.id = id ?? Self.identifier(Self.key(food: food), created: food.created)
        name = food.name
        detail = food.summary
        isRecipe = false
    }

    @MainActor
    init(_ recipe: Recipe, id: String? = nil) {
        self.id = id ?? Self.identifier(Self.key(recipe: recipe), created: recipe.created)
        name = recipe.name
        detail = recipe.summary
        isRecipe = true
    }

    private static let separator: Character = "\u{1F}"

    @MainActor
    private static func key(food: Food) -> String {
        ["food", food.name.lowercased(), food.brand.lowercased()].joined(separator: String(separator))
    }

    @MainActor
    private static func key(recipe: Recipe) -> String {
        ["recipe", recipe.name.lowercased()].joined(separator: String(separator))
    }

    /// The key, then the creation time in milliseconds.
    private static func identifier(_ key: String, created: Date) -> String {
        key + String(separator) + String(Int64((created.timeIntervalSince1970 * 1000).rounded()))
    }

    /// Which of these records, in `SavedFoodQuery`'s order, an ID is: the one with the same key created closest to
    /// its time. iCloud may keep that time less precisely than this iPhone, so it needn't match exactly, but one
    /// created a second or more apart is a different record. Nil if there's none, such as after it was deleted or
    /// renamed.
    private static func match<Record>(_ id: String, in records: [Record], key: (Record) -> String,
                                      created: (Record) -> Date) -> Record? {
        guard let split = id.lastIndex(of: separator), let milliseconds = Int64(id[id.index(after: split)...]) else {
            return nil
        }
        let (wanted, time) = (String(id[..<split]), Date(timeIntervalSince1970: Double(milliseconds) / 1000))
        var best: (record: Record, gap: TimeInterval)?
        for record in records where key(record) == wanted {
            let gap = abs(created(record).timeIntervalSince(time))
            if gap < min(1, best?.gap ?? 1) { best = (record, gap) }
        }
        return best?.record
    }

    @MainActor
    static func food(for id: String, in foods: [Food]) -> Food? {
        match(id, in: foods, key: key(food:), created: \.created)
    }

    @MainActor
    static func recipe(for id: String, in recipes: [Recipe]) -> Recipe? {
        match(id, in: recipes, key: key(recipe:), created: \.created)
    }

    /// The saved food or recipe this stands for: one serving of it, and how to mark it as just logged. Nil if it
    /// was deleted or renamed.
    @MainActor
    func resolve(in context: ModelContext) -> (portion: FoodPortion, markLogged: () -> Void)? {
        if isRecipe {
            guard let recipe = Self.recipe(for: id, in: SavedFoodQuery.recipes(in: context)) else { return nil }
            return (recipe.portion, { recipe.lastLogged = .now })
        }
        guard let food = Self.food(for: id, in: SavedFoodQuery.foods(in: context)) else { return nil }
        return (food.portion, { food.lastLogged = .now })
    }
}

/// Finds saved foods and recipes by name. A name that matches several, like "yogurt", returns them all, so Siri and
/// Shortcuts ask which one.
struct SavedFoodQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [SavedFoodEntity.ID]) async throws -> [SavedFoodEntity] {
        let context = HealthLoggerApp.sharedContainer.mainContext
        let (foods, recipes) = (Self.foods(in: context), Self.recipes(in: context))
        return identifiers.compactMap { id in
            if let food = SavedFoodEntity.food(for: id, in: foods) { return SavedFoodEntity(food, id: id) }
            return SavedFoodEntity.recipe(for: id, in: recipes).map { SavedFoodEntity($0, id: id) }
        }
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
        let entities = Self.foods(in: context).map { SavedFoodEntity($0) }
            + Self.recipes(in: context).map { SavedFoodEntity($0) }
        // Records created in the same millisecond have the same ID, which finds the first of them.
        var seen: Set<String> = []
        return entities.filter { seen.insert($0.id).inserted }
    }

    /// Saved foods: favorites, then the most recently logged, then by name.
    @MainActor
    static func foods(in context: ModelContext) -> [Food] {
        ((try? context.fetch(FetchDescriptor<Food>())) ?? []).sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            let (dateA, dateB) = (a.lastLogged ?? .distantPast, b.lastLogged ?? .distantPast)
            if dateA != dateB { return dateA > dateB }
            let byName = a.name.localizedStandardCompare(b.name)
            return byName != .orderedSame ? byName == .orderedAscending : a.created < b.created
        }
    }

    /// Recipes, most recently logged first.
    @MainActor
    static func recipes(in context: ModelContext) -> [Recipe] {
        ((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).sorted { a, b in
            let (dateA, dateB) = (a.lastLogged ?? .distantPast, b.lastLogged ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.created < b.created
        }
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
        guard let last = try await Recents.lastMeal(meal, in: health) else {
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
