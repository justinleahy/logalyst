import SwiftUI
import SwiftData
import Vision
import VisionKit
import AVFoundation

// MARK: - Library

/// Where foods are logged from: recent meals and foods to log again in one tap, then saved foods,
/// favorites first and then most recently logged.
struct FoodLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthStore.self) private var health
    @Query(sort: \Food.name) private var foods: [Food]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var search = ""
    @State private var editor: EditorTarget?
    @State private var scanning = false
    @State private var scanningLabel = false
    @State private var photographingMeal = false
    @State private var composingMeal = false
    @State private var recentFoods: [FoodPortion] = []
    @State private var recentMeals: [RecentMeal] = []
    /// Recent foods and meals logged a moment ago with their quick-log button, to show a checkmark.
    @State private var justLogged: Set<String> = []
    @State private var error: String?

    private static let recentFoodLimit = 8
    private static let recentMealLimit = 3

    private enum EditorTarget: Identifiable {
        case new
        case edit(Food)
        case newRecipe
        case editRecipe(Recipe)

        var id: AnyHashable {
            switch self {
            case .new: "new"
            case .edit(let food): food.persistentModelID
            case .newRecipe: "newRecipe"
            case .editRecipe(let recipe): recipe.persistentModelID
            }
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                if !recentMeals.isEmpty {
                    Section("Recent Meals") {
                        ForEach(recentMeals) { recentMealRow($0) }
                    }
                }
                if !recentFoods.isEmpty {
                    Section {
                        ForEach(recentFoods) { recentFoodRow($0) }
                    } header: {
                        Text("Recent")
                    } footer: {
                        Text("Tap \(Image(systemName: "plus.circle")) to log it again now, as much as last time.")
                    }
                }
            }
            if !visibleRecipes.isEmpty {
                Section("Recipes") {
                    ForEach(visibleRecipes) { recipeRow($0) }
                }
            }
            Section(foods.isEmpty ? "" : "My Foods") {
                ForEach(visibleFoods) { savedFoodRow($0) }
            }
        }
        .overlay {
            if foods.isEmpty && recentFoods.isEmpty && recipes.isEmpty {
                ContentUnavailableView {
                    Label("No Foods Yet", systemImage: "fork.knife")
                } description: {
                    Text("Create a food from its nutrition label, or scan its barcode to fill it in.")
                } actions: {
                    Button("Scan Barcode") { scanning = true }.buttonStyle(.borderedProminent)
                    Button("Scan Nutrition Label") { scanningLabel = true }
                    Button("New Food") { editor = .new }
                }
            } else if !search.isEmpty && visibleFoods.isEmpty && visibleRecipes.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search Foods and Recipes")
        .navigationTitle("Add Food")
        .toolbar {
            Button("Scan Barcode", systemImage: "barcode.viewfinder") { scanning = true }
            Menu("New Food", systemImage: "plus") {
                Button("New Food", systemImage: "square.and.pencil") { editor = .new }
                Button("Scan Nutrition Label", systemImage: "text.viewfinder") { scanningLabel = true }
                Button("New Recipe", systemImage: "book.closed") { editor = .newRecipe }
                Button("New Meal", systemImage: "fork.knife.circle") { composingMeal = true }
                if MealPhoto.isAvailable {
                    Button("Photo of Meal", systemImage: "camera") { photographingMeal = true }
                }
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .new: FoodEditor { _ in editor = nil }.cancelButton { editor = nil }
                case .edit(let food): FoodEditor(food: food) { _ in editor = nil }.cancelButton { editor = nil }
                case .newRecipe: RecipeEditor { _ in editor = nil }.cancelButton { editor = nil }
                case .editRecipe(let recipe):
                    RecipeEditor(recipe: recipe) { _ in editor = nil }.cancelButton { editor = nil }
                }
            }
        }
        .sheet(isPresented: $scanning) { ScanFoodView() }
        .sheet(isPresented: $scanningLabel) { ScanLabelView() }
        .sheet(isPresented: $photographingMeal) { MealPhotoView() }
        .sheet(isPresented: $composingMeal) { NewMealView() }
        .task(id: health.changeCount) { await loadRecents() }
        .sensoryFeedback(.success, trigger: justLogged.count) { old, new in new > old }
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: Rows

    private func recentMealRow(_ recent: RecentMeal) -> some View {
        NavigationLink {
            LogMealView(title: recent.meal.title, portions: recent.foods, meal: recent.meal)
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(recent.meal.title), \(recent.dayText)")
                        Text(recent.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } icon: {
                    Image(systemName: recent.meal.systemImage)
                }
                Spacer()
                quickLogButton(key: recent.id, label: "Log \(recent.meal.title) Again") {
                    try await health.saveFoods(recent.foods, meal: recent.meal, date: .now)
                    Food.markLogged(recent.foods, among: foods)
                }
            }
        }
    }

    private func recentFoodRow(_ portion: FoodPortion) -> some View {
        NavigationLink {
            LogFoodView(portion, food: foods.first { $0.portion.isSameFood(as: portion) })
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(portion.name)
                    Text(portion.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                quickLogButton(key: portion.identityKey, label: "Log \(portion.name) Again") {
                    try await health.saveFoods([portion], meal: Meal(at: .now), date: .now)
                    Food.markLogged([portion], among: foods)
                }
            }
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        NavigationLink {
            LogFoodView(recipe: recipe)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name)
                    Text(recipe.summary).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "book.closed")
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(recipe) }
            Button("Edit", systemImage: "pencil") { editor = .editRecipe(recipe) }
        }
    }

    private func savedFoodRow(_ food: Food) -> some View {
        NavigationLink {
            LogFoodView(food: food)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(food.name)
                    if food.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                if !food.summary.isEmpty {
                    Text(food.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button(food.isFavorite ? "Unfavorite" : "Favorite",
                   systemImage: food.isFavorite ? "star.slash" : "star") { food.isFavorite.toggle() }
                .tint(.yellow)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(food) }
            Button("Edit", systemImage: "pencil") { editor = .edit(food) }
        }
    }

    /// Logs without opening the food, then shows a checkmark for a moment.
    private func quickLogButton(key: String, label: String, log: @escaping () async throws -> Void) -> some View {
        let logged = justLogged.contains(key)
        return Button {
            Task {
                do {
                    try await log()
                    justLogged.insert(key)
                    try? await Task.sleep(for: .seconds(2))
                    justLogged.remove(key)
                } catch {
                    self.error = error.healthMessage
                }
            }
        } label: {
            Image(systemName: logged ? "checkmark.circle.fill" : "plus.circle")
                .font(.title2)
                .foregroundStyle(logged ? .green : .accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .disabled(logged)
        .accessibilityLabel(logged ? "Logged" : label)
    }

    // MARK: Data

    private var visibleFoods: [Food] {
        let matches = search.isEmpty ? foods : foods.filter {
            $0.name.localizedStandardContains(search) || $0.brand.localizedStandardContains(search)
        }
        // Favorites, then recently logged, then alphabetical (the query's order) for the rest.
        return matches.enumerated().sorted { a, b in
            if a.element.isFavorite != b.element.isFavorite { return a.element.isFavorite }
            let (dateA, dateB) = (a.element.lastLogged ?? .distantPast, b.element.lastLogged ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.offset < b.offset
        }.map(\.element)
    }

    /// Recently logged first, then alphabetical.
    private var visibleRecipes: [Recipe] {
        let matches = search.isEmpty ? recipes : recipes.filter { $0.name.localizedStandardContains(search) }
        return matches.enumerated().sorted { a, b in
            let (dateA, dateB) = (a.element.lastLogged ?? .distantPast, b.element.lastLogged ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.offset < b.offset
        }.map(\.element)
    }

    private func loadRecents() async {
        let since = Calendar.current.date(byAdding: .day, value: -Recents.days, to: .now)!
        // Recents are a shortcut, so if Health can't be read (such as while locked) just keep what's showing.
        guard let entries = try? await health.recentEntries(of: [], since: since, limit: 500) else { return }
        // Foods logged before they had a serving weight can be weighed when logged again, if they match.
        let logged = entries.map { entry in
            var entry = entry
            entry.food = entry.food?.withServingWeight(from: self.foods)
            return entry
        }
        recentFoods = Recents.foods(in: logged, limit: Self.recentFoodLimit)
        recentMeals = Recents.meals(in: logged, limit: Self.recentMealLimit)
    }
}

/// Foods and meals logged lately, rebuilt from Health's food entries, so they work even after a saved food is
/// deleted. Shared by Add Food and the Siri and Shortcuts actions.
enum Recents {
    /// How far back to look.
    static let days = 30

    /// Each food logged, newest first, once each.
    static func foods(in entries: [LoggedEntry], limit: Int) -> [FoodPortion] {
        var foods: [FoodPortion] = []
        for case let food? in entries.map(\.food) where !foods.contains(where: { $0.isSameFood(as: food) }) {
            foods.append(food)
            if foods.count == limit { break }
        }
        return foods
    }

    /// Meals of at least `minimumFoods` foods (two by default, since one food is a recent food), newest first,
    /// skipping repeats of the same foods at the same meal.
    static func meals(in entries: [LoggedEntry], limit: Int, minimumFoods: Int = 2) -> [RecentMeal] {
        let calendar = Calendar.current
        var meals: [RecentMeal] = []
        var seen: Set<String> = []
        let groups = Dictionary(grouping: entries.filter { $0.food != nil && $0.meal != nil }) {
            MealKey(day: calendar.startOfDay(for: $0.date), meal: $0.meal!)
        }
        for key in groups.keys.sorted(by: { $0.day != $1.day ? $0.day > $1.day : $0.meal.sortOrder > $1.meal.sortOrder }) {
            let entries = groups[key]!.sorted { $0.date < $1.date }
            guard entries.count >= minimumFoods else { continue }
            let meal = RecentMeal(day: key.day, meal: key.meal, foods: entries.compactMap(\.food))
            guard seen.insert(meal.id).inserted else { continue }
            meals.append(meal)
            if meals.count == limit { break }
        }
        return meals
    }

    /// The most recent time this meal was logged before today, with however many foods it had, for logging it
    /// again. Nil if it wasn't logged in the last `days` days.
    static func lastMeal(_ meal: Meal, in entries: [LoggedEntry]) -> RecentMeal? {
        meals(in: entries.filter { $0.meal == meal && !Calendar.current.isDateInToday($0.date) },
              limit: 1, minimumFoods: 1).first
    }

    private struct MealKey: Hashable {
        let day: Date
        let meal: Meal
    }
}

/// The foods eaten at one meal on one day.
struct RecentMeal: Identifiable {
    let day: Date
    let meal: Meal
    let foods: [FoodPortion]

    /// The meal and which foods, so the same breakfast on two days shows once.
    var id: String {
        meal.rawValue + ":" + foods.map(\.identityKey).sorted().joined(separator: "|")
    }

    var dayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "Oatmeal, Coffee · 520 kcal"
    var summary: String {
        let calories = foods.map(\.calories).reduce(0, +)
        return foods.map(\.name).joined(separator: ", ") + " · " + formatCalories(calories)
    }
}

extension Meal {
    var sortOrder: Int { Meal.allCases.firstIndex(of: self)! }
}

private func formatCalories(_ calories: Double) -> String {
    "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal"
}

extension FoodPortion {
    /// Stays the same when the food is logged again, unlike `id`.
    var identityKey: String {
        name.lowercased() + "\u{1F}" + brand.lowercased()
    }

    /// "Brand · 2 × 1 cup · 300 kcal", or "Brand · 35 g · 140 kcal" when weighed, skipping whatever is missing.
    var summary: String {
        [brand, amountText, formatCalories(calories)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension View {
    func cancelButton(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: action) }
        }
    }
}

// MARK: - Logging

/// Logs one food, by the serving or by weight. Also corrects a food already logged.
struct LogFoodView: View {
    /// Marks the saved food or recipe this came from, if any, as just logged so it moves up its list.
    private let markLogged: () -> Void
    /// Called after saving; pops this screen when nil.
    var onSaved: (() -> Void)?
    /// A logged food being corrected. Saving replaces its entry in Health and leaves saved foods and recipes alone,
    /// including when they were last logged.
    private var editing: LoggedEntry?

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var portion: FoodPortion
    @State private var meal = Meal(at: .now)
    /// Once the user picks a meal, changing the time no longer changes it.
    @State private var mealChosen = false
    @State private var date = Date.now
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved = false
    /// The correction saved but the original couldn't be deleted.
    @State private var incompleteEdit: IncompleteEdit?

    init(food: Food, onSaved: (() -> Void)? = nil) {
        self.init(food.portion, food: food, onSaved: onSaved)
    }

    init(_ portion: FoodPortion, food: Food? = nil, onSaved: (() -> Void)? = nil) {
        self.init(portion, onSaved: onSaved) { food?.lastLogged = .now }
    }

    init(recipe: Recipe, onSaved: (() -> Void)? = nil) {
        self.init(recipe.portion, onSaved: onSaved) { recipe.lastLogged = .now }
    }

    /// Changes the servings (or weight, if it was saved with one), meal, or date and time of a logged food. Its
    /// nutrition per serving comes from the entry itself.
    init(editing entry: LoggedEntry, onSaved: (() -> Void)? = nil) {
        self.init(entry.food ?? FoodPortion(name: entry.title, nutrients: [:]), onSaved: onSaved) {}
        editing = entry
        _meal = State(initialValue: entry.meal ?? Meal(at: entry.date))
        _mealChosen = State(initialValue: true)
        _date = State(initialValue: entry.date)
    }

    private init(_ portion: FoodPortion, onSaved: (() -> Void)?, markLogged: @escaping () -> Void) {
        self.markLogged = markLogged
        self.onSaved = onSaved
        _portion = State(initialValue: portion)
    }

    var body: some View {
        Form {
            Section {
                if !portion.servingSize.isEmpty {
                    LabeledContent("Serving Size", value: portion.servingSize)
                }
                if portion.canWeigh {
                    Picker("Enter In", selection: unitBinding) {
                        Text("Servings").tag(WeightUnit?.none)
                        ForEach(WeightUnit.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                let amount = HStack {
                    AmountField(portion: $portion, width: dynamicTypeSize.isAccessibilitySize ? .infinity : 70)
                    if let unit = portion.enteredWeightUnit {
                        Text(unit.label).foregroundStyle(.secondary)
                    }
                    AmountStepper(portion: $portion, servings: 0.5...20)
                }
                // At the largest text sizes the amount gets its own line, so it isn't cut off.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading) {
                        Text(portion.enteredWeightUnit == nil ? "Servings" : "Weight")
                        amount
                    }
                } else {
                    HStack {
                        Text(portion.enteredWeightUnit == nil ? "Servings" : "Weight")
                        Spacer()
                        amount
                    }
                }
            } header: {
                if !portion.brand.isEmpty { Text(portion.brand) }
            } footer: {
                if let grams = portion.gramsPerServing, portion.canWeigh {
                    Text("One serving weighs \(WeightUnit.grams.format(grams: grams)).")
                }
            }
            NutritionTotals(portions: [portion])
            MealAndTimeSection(meal: $meal, mealChosen: $mealChosen, date: $date)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(portion.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Log" : "Save", action: save).disabled(isSaving || portion.servings <= 0)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .incompleteEditAlert($incompleteEdit, onDone: close)
    }

    private var unitBinding: Binding<WeightUnit?> {
        Binding { portion.enteredWeightUnit } set: { portion.enter(in: $0) }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await health.saveFoods([portion], meal: meal, date: date, replacing: editing)
            } catch {
                if let incomplete = IncompleteEdit(error) {
                    // The correction saved, so Save stays off; the alert offers to finish the edit.
                    incompleteEdit = incomplete
                } else {
                    self.error = error.healthMessage
                    isSaving = false
                }
                return
            }
            if editing == nil { markLogged() }
            saved.toggle()
            close()
        }
    }

    private func close() {
        if let onSaved { onSaved() } else { dismiss() }
    }
}

/// Types a portion's amount in the unit it's entered in: servings, grams or ounces.
private struct AmountField: View {
    @Binding var portion: FoodPortion
    let width: CGFloat

    var body: some View {
        let digits = portion.enteredWeightUnit?.fractionDigits ?? 2
        TextField("0", value: $portion.enteredAmount, format: .number.precision(.fractionLength(0...digits)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(maxWidth: width)
            .accessibilityLabel(portion.enteredWeightUnit.map { "\($0.title) of \(portion.name)" }
                ?? "Servings of \(portion.name)")
    }
}

/// Steps a portion's amount: half servings, 5 g or a quarter ounce at a time.
private struct AmountStepper: View {
    @Binding var portion: FoodPortion
    /// The range when entering servings.
    let servings: ClosedRange<Double>

    var body: some View {
        let range: ClosedRange<Double> = switch portion.enteredWeightUnit {
        case .grams?: 0...5000
        case .ounces?: 0...176
        case nil: servings
        }
        Stepper("Amount of \(portion.name)", value: $portion.enteredAmount, in: range,
                step: portion.enteredWeightUnit?.step ?? 0.5)
            .labelsHidden()
    }
}

/// Logs several foods at once, such as a meal eaten before. Each is saved as its own food entry.
struct LogMealView: View {
    let title: String
    /// Shown under the foods, e.g. to say they're estimates.
    var note: String?
    /// Called after saving; pops this screen when nil.
    var onSaved: (() -> Void)?

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [Food]
    @State private var portions: [FoodPortion]
    @State private var meal: Meal
    @State private var mealChosen: Bool
    @State private var date: Date
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved = false
    @State private var savingRecipe = false
    @State private var addingFood = false
    @State private var replacing: Replacement?

    /// A food in the list being swapped for another, such as a meal-photo guess for the right saved food.
    private struct Replacement: Identifiable {
        let id: FoodPortion.ID
        let name: String
    }

    /// With no meal, it defaults to the usual one for the time, which is now unless `date` says otherwise.
    init(title: String, portions: [FoodPortion], meal: Meal? = nil, date: Date? = nil, note: String? = nil,
         onSaved: (() -> Void)? = nil) {
        self.title = title
        self.note = note
        self.onSaved = onSaved
        _portions = State(initialValue: portions)
        _date = State(initialValue: date ?? .now)
        _meal = State(initialValue: meal ?? Meal(at: date ?? .now))
        _mealChosen = State(initialValue: meal != nil)
    }

    var body: some View {
        Form {
            Section {
                ForEach($portions) { $portion in
                    PortionRow(portion: $portion, zeroText: "Left out")
                        .swipeActions {
                            Button("Replace", systemImage: "arrow.left.arrow.right") { replace(portion) }
                                .tint(.indigo)
                        }
                        .contextMenu {
                            Button("Replace \(portion.name)", systemImage: "arrow.left.arrow.right") { replace(portion) }
                        }
                }
                Button("Add Food", systemImage: "plus.circle") { addingFood = true }
            } header: {
                Text("Foods")
            } footer: {
                Text([note, "Set a food to 0 to leave it out, or swipe left on it to replace it with one of your foods."]
                    .compactMap { $0 }.joined(separator: " "))
            }
            NutritionTotals(portions: included)
            MealAndTimeSection(meal: $meal, mealChosen: $mealChosen, date: $date)
            Section {
                Button("Save as Recipe", systemImage: "book.closed") { savingRecipe = true }
                    .disabled(included.isEmpty)
            } footer: {
                Text("Save these foods as a recipe to log them together later.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $savingRecipe) {
            NavigationStack {
                RecipeEditor(ingredients: included) { _ in savingRecipe = false }
                    .cancelButton { savingRecipe = false }
            }
        }
        .sheet(isPresented: $addingFood) {
            NavigationStack {
                FoodPicker(title: "Add Food", allowsMultiple: true) { picked in
                    portions += picked
                    addingFood = false
                }
                .cancelButton { addingFood = false }
            }
        }
        .sheet(item: $replacing) { target in
            NavigationStack {
                FoodPicker(title: "Replace \(target.name)") { picked in
                    if let food = picked.first, let index = portions.firstIndex(where: { $0.id == target.id }) {
                        portions[index] = portions[index].replaced(by: food)
                    }
                    replacing = nil
                }
                .cancelButton { replacing = nil }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log", action: save).disabled(isSaving || included.isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var included: [FoodPortion] {
        portions.filter { $0.servings > 0 }
    }

    private func replace(_ portion: FoodPortion) {
        replacing = Replacement(id: portion.id, name: portion.name)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await health.saveFoods(included, meal: meal, date: date)
                Food.markLogged(included, among: savedFoods)
                saved.toggle()
                if let onSaved { onSaved() } else { dismiss() }
            } catch {
                self.error = error.healthMessage
            }
        }
    }
}

/// A food in a list of several, with its amount to change: servings, or a weight for a food with a known serving
/// weight. At zero it shows `zeroText`.
struct PortionRow: View {
    @Binding var portion: FoodPortion
    let zeroText: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At the largest text sizes the amount goes under the food, so neither is cut off.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                food
                HStack { amount(width: .infinity) }
            }
        } else {
            HStack {
                food
                Spacer()
                amount(width: portion.enteredWeightUnit == nil ? 44 : 56)
            }
        }
    }

    private var food: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(portion.name)
                .foregroundStyle(portion.servings > 0 ? .primary : .secondary)
            Text(portion.servings > 0 ? portion.summary : zeroText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func amount(width: CGFloat) -> some View {
        AmountField(portion: $portion, width: width)
        if portion.canWeigh {
            Menu {
                Picker("Enter \(portion.name) In", selection: unitBinding) {
                    Text("Servings").tag(WeightUnit?.none)
                    ForEach(WeightUnit.allCases) { Text($0.title).tag(Optional($0)) }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(portion.enteredWeightUnit?.label ?? "×")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
            .accessibilityLabel("Unit for \(portion.name)")
            .accessibilityValue(portion.enteredWeightUnit?.title ?? "Servings")
        }
        AmountStepper(portion: $portion, servings: 0...50)
    }

    private var unitBinding: Binding<WeightUnit?> {
        Binding { portion.enteredWeightUnit } set: { portion.enter(in: $0) }
    }
}

/// What the portions add up to, per nutrient.
struct NutritionTotals: View {
    let portions: [FoodPortion]
    var title = "Nutrition"

    var body: some View {
        Section(title) {
            ForEach(FoodNutrient.metrics) { metric in
                let total = portions.map { $0.amount(of: metric.id) }.reduce(0, +)
                if total > 0, let option = metric.unitOptions.first {
                    LabeledContent {
                        Text(option.format(total)).monospacedDigit()
                    } label: {
                        Label(metric.name, systemImage: metric.systemImage)
                    }
                }
            }
        }
    }
}

/// Meal and time pickers. The meal follows the time until the user picks one.
private struct MealAndTimeSection: View {
    @Binding var meal: Meal
    @Binding var mealChosen: Bool
    @Binding var date: Date

    var body: some View {
        Section {
            Picker("Meal", selection: Binding { meal } set: { meal = $0; mealChosen = true }) {
                ForEach(Meal.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            DatePicker("Date & Time", selection: $date, in: ...Date.now)
        }
        .onChange(of: date) { _, date in
            if !mealChosen { meal = Meal(at: date) }
        }
    }
}

// MARK: - Editing

struct FoodEditor: View {
    let food: Food?
    let onSave: (Food) -> Void

    @Environment(\.modelContext) private var context
    @State private var draft: FoodDraft
    @State private var scanningLabel = false

    init(food: Food? = nil, draft: FoodDraft? = nil, onSave: @escaping (Food) -> Void) {
        self.food = food
        self.onSave = onSave
        _draft = State(initialValue: draft ?? food?.draft ?? FoodDraft())
    }

    var body: some View {
        Form {
            Section {
                textField("Name", text: $draft.name, prompt: "Required")
                textField("Brand", text: $draft.brand, prompt: "Optional")
                textField("Serving Size", text: $draft.servingSize, prompt: "e.g. 1 cup or 30 g")
                LabeledContent("Serving Weight") {
                    HStack(spacing: 4) {
                        TextField("Serving Weight", value: $draft.gramsPerServing,
                                  format: .number.precision(.fractionLength(0...1)), prompt: Text("Optional"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .accessibilityLabel("Serving Weight in grams")
                        Text("g").foregroundStyle(.secondary)
                    }
                }
                if let stated = draft.statedServingWeight {
                    Button("Use \(WeightUnit.grams.format(grams: stated)) from Serving Size", systemImage: "scalemass") {
                        draft.gramsPerServing = stated
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    switch draft.source {
                    case .database: Text("Filled in from Open Food Facts. Check it against the label before saving.")
                    case .notFound: Text("This barcode isn't in Open Food Facts. Scan its nutrition label or enter the details.")
                    case .label: Text("Filled in from the label. Check each amount against it, and add a name, before saving.")
                    case .manual: EmptyView()
                    }
                    Text("With a serving weight, you can log this food in grams or ounces.")
                }
            }
            Section {
                ForEach(FoodNutrient.metrics) { nutrientField($0) }
            } header: {
                HStack {
                    Text("Nutrition per Serving")
                    Spacer()
                    Button("Scan Label", systemImage: "text.viewfinder") { scanningLabel = true }
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
            if let barcode = draft.barcode {
                Section("Barcode") {
                    Text(barcode).monospacedDigit()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(food == nil ? "New Food" : "Edit Food")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanningLabel) {
            NavigationStack {
                LabelCaptureView { label in
                    draft.apply(label)
                    scanningLabel = false
                }
                .navigationTitle("Scan Nutrition Label")
                .navigationBarTitleDisplayMode(.inline)
                .cancelButton { scanningLabel = false }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!draft.isValid)
            }
        }
    }

    private func textField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func nutrientField(_ metric: Metric) -> some View {
        if let option = metric.unitOptions.first {
            let amount = Binding<Double?> {
                draft.nutrients[metric.id]
            } set: {
                draft.nutrients[metric.id] = $0
            }
            HStack {
                Label(metric.name, systemImage: metric.systemImage)
                Spacer()
                TextField("0", value: amount, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .accessibilityLabel("\(metric.name) in \(option.label)")
                Text(option.label).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let saved: Food
        if let food {
            food.update(from: draft)
            saved = food
        } else {
            saved = Food(draft)
            context.insert(saved)
        }
        onSave(saved)
    }
}

// MARK: - Scanning

/// Scans (or takes a typed) barcode, then logs the matching saved food or creates one from a lookup.
struct ScanFoodView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []
    @State private var cameraReady = false
    @State private var typedCode = ""
    @State private var lookingUp = false
    @State private var error: String?

    private enum Step: Hashable {
        case log(Food)
        case create(FoodDraft)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ZStack {
                    if cameraReady {
                        BarcodeScanner(onScan: handle)
                    } else {
                        ContentUnavailableView("Camera Unavailable", systemImage: "barcode.viewfinder",
                                               description: Text("Type the number under the barcode instead."))
                    }
                    if lookingUp {
                        ProgressView("Looking Up…")
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    TextField("Barcode Number", text: $typedCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look Up") { handle(typedCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(typedCode.isEmpty || lookingUp)
                }
                .padding()
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .log(let food): LogFoodView(food: food) { dismiss() }
                case .create(let draft): FoodEditor(draft: draft) { food in path = [.log(food)] }
                }
            }
            .alert("Couldn't Look Up Barcode", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                }
                cameraReady = BarcodeScanner.isAvailable
            }
        }
    }

    private func handle(_ code: String) {
        let barcode = code.filter { $0.isASCII && $0.isNumber }
        // The scanner keeps reporting while a result is on screen, so ignore it until we're back.
        guard !barcode.isEmpty, path.isEmpty, !lookingUp else { return }
        if let food = savedFood(withBarcode: barcode) {
            path = [.log(food)]
            return
        }
        lookingUp = true
        Task {
            defer { lookingUp = false }
            do {
                let draft = try await FoodDatabase.lookUp(barcode: barcode)
                    ?? FoodDraft(barcode: barcode, source: .notFound)
                path = [.create(draft)]
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func savedFood(withBarcode barcode: String) -> Food? {
        var descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.barcode == barcode })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Live camera barcode reader.
private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let value = barcode.payloadStringValue {
                    onScan(value)
                    return
                }
            }
        }
    }
}

// MARK: - Log again

extension View {
    /// For a food entry, a swipe and a menu item that log the same food again now.
    /// Reports a failure through `onError`.
    func logAgainActions(_ entry: LoggedEntry, in health: HealthStore,
                         onError: @escaping (String) -> Void) -> some View {
        modifier(LogAgainActions(food: entry.food, health: health, onError: onError))
    }
}

private struct LogAgainActions: ViewModifier {
    let food: FoodPortion?
    let health: HealthStore
    let onError: (String) -> Void

    @State private var logged = false

    func body(content: Content) -> some View {
        if let food {
            content
                .swipeActions(edge: .leading) {
                    Button("Log Again", systemImage: "arrow.clockwise") { log(food) }.tint(.accentColor)
                }
                .contextMenu {
                    Button("Log Again", systemImage: "arrow.clockwise") { log(food) }
                }
                .sensoryFeedback(.success, trigger: logged)
        } else {
            content
        }
    }

    private func log(_ food: FoodPortion) {
        Task {
            do {
                try await health.saveFoods([food], meal: Meal(at: .now), date: .now)
                logged.toggle()
            } catch {
                onError(error.healthMessage)
            }
        }
    }
}
