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
    /// Food entries from the last `Recents.days` days, newest first, which the recents below are made from.
    @State private var loggedRecently: [LoggedEntry] = []
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
        // Editing a saved food here or on another iPhone can give recents of it a serving weight, or take it away.
        .onChange(of: foods.map(\.draft)) { showRecents() }
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
        loggedRecently = entries
        showRecents()
    }

    private func showRecents() {
        // Foods logged before they had a serving weight can be weighed when logged again, if they match.
        let logged = loggedRecently.map { entry in
            var entry = entry
            entry.food = entry.food?.withServingWeight(from: foods)
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

    /// The same, read from Health a day at a time from yesterday back, so the meal has all its foods however much
    /// else was logged since.
    static func lastMeal(_ meal: Meal, in health: HealthStore) async throws -> RecentMeal? {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -days, to: .now)!
        var end = calendar.startOfDay(for: .now)
        while end > since {
            let start = max(calendar.date(byAdding: .day, value: -1, to: end)!, since)
            let day = try await health.recentEntries(of: [], since: start, before: end, limit: nil)
                .filter { $0.date >= start && $0.date < end }
            if let found = lastMeal(meal, in: day) { return found }
            end = start
        }
        return nil
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
        let coverage = FoodNutrition.coverage(of: "dietaryEnergyConsumed", in: foods)
        let calories = FoodNutrition.totals(foods)["dietaryEnergyConsumed"]
        let detail = calories.map {
            formatCalories($0) + (coverage.isPartial ? " · Partial" : "")
                + (coverage.isUncertain ? " · Coverage unknown" : "")
        }
            ?? "Calories unavailable"
        return foods.map(\.name).joined(separator: ", ") + " · " + detail
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
        [brand, amountText, calorieSummary].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var calorieSummary: String {
        guard let calories = knownAmount(of: "dietaryEnergyConsumed") else { return "Calories unavailable" }
        let coverage = coverage(of: "dietaryEnergyConsumed")
        return formatCalories(calories)
            + (coverage.isPartial ? " · Partial" : "") + (coverage.isUncertain ? " · Coverage unknown" : "")
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
                PortionUnitPicker(portion: $portion)
                // Fluid-ounce labels need a separate line as soon as text is enlarged.
                if dynamicTypeSize > .large {
                    VStack(alignment: .leading) {
                        Text(portion.entryUnit.amountTitle)
                        if let label = portion.entryUnit.label {
                            Text(label).foregroundStyle(.secondary)
                        }
                        HStack {
                            AmountField(portion: $portion, width: .infinity)
                            AmountStepper(portion: $portion, servings: 0.5...20)
                        }
                    }
                } else {
                    HStack {
                        Text(portion.entryUnit.amountTitle)
                        Spacer()
                        AmountField(portion: $portion, width: 70)
                        if let label = portion.entryUnit.label {
                            Text(label).foregroundStyle(.secondary)
                        }
                        AmountStepper(portion: $portion, servings: 0.5...20)
                    }
                }
            } header: {
                if !portion.brand.isEmpty { Text(portion.brand) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let grams = portion.gramsPerServing, portion.canWeigh {
                        Text("One serving weighs \(WeightUnit.grams.format(grams: grams)).")
                    }
                    if let milliliters = portion.millilitersPerServing, portion.canMeasureVolume {
                        Text("One serving contains \(VolumeUnit.milliliters.format(milliliters: milliliters)).")
                    }
                }
            }
            NutritionTotals(portions: [portion])
            if !portion.hasKnownNutrition {
                Section {
                    Label("No known nutrition to log", systemImage: "info.circle")
                } footer: {
                    Text("Add nutrition to this food or its recipe ingredients before logging. Unavailable values can't be saved to Health as zero.")
                }
            }
            if let source = portion.source {
                Section {
                    SourceRow(source: source)
                } header: {
                    Text("Source")
                } footer: {
                    Text("Logged as published when it was looked up; a later change to the source doesn't change it.")
                }
            } else if portion.isEstimate {
                Section {
                    Label("Estimated by Apple Intelligence from a photo", systemImage: "sparkles")
                }
            }
            MealAndTimeSection(meal: $meal, mealChosen: $mealChosen, date: $date)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(portion.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Log" : "Save", action: save)
                    .disabled(isSaving || !portion.servings.isFinite || portion.servings <= 0 || !portion.hasKnownNutrition)
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

    private func save() {
        guard !isSaving, portion.servings.isFinite, portion.servings > 0, portion.hasKnownNutrition else { return }
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

/// One selection across servings, weight and volume. The serving count stays unchanged when units change.
private enum PortionEntryUnit: Hashable {
    case servings
    case weight(WeightUnit)
    case volume(VolumeUnit)

    var title: String {
        switch self {
        case .servings: "Servings"
        case .weight(let unit): unit == .ounces ? "Ounces (weight)" : unit.title
        case .volume(let unit): unit.title
        }
    }

    var label: String? {
        switch self {
        case .servings: nil
        case .weight(let unit): unit == .ounces ? "oz wt" : unit.label
        case .volume(let unit): unit.label
        }
    }

    var amountTitle: String {
        switch self {
        case .servings: "Servings"
        case .weight: "Weight"
        case .volume: "Volume"
        }
    }
}

private extension FoodPortion {
    var entryUnit: PortionEntryUnit {
        get {
            if let unit = enteredVolumeUnit { return .volume(unit) }
            if let unit = enteredWeightUnit { return .weight(unit) }
            return .servings
        }
        set {
            switch newValue {
            case .servings: enter(in: nil)
            case .weight(let unit): enter(in: unit)
            case .volume(let unit): enter(volumeUnit: unit)
            }
        }
    }
}

private struct PortionUnitPicker: View {
    @Binding var portion: FoodPortion

    var body: some View {
        if portion.canMeasureVolume {
            Picker("Enter In", selection: $portion.entryUnit) {
                PortionUnitOptions(portion: portion)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("portionUnitPicker")
        } else if portion.canWeigh {
            // Preserve the compact weight-only control; no fluid units to confuse with its ounces.
            Picker("Enter In", selection: $portion.entryUnit) {
                Text("Servings").tag(PortionEntryUnit.servings)
                ForEach(WeightUnit.allCases) { Text($0.title).tag(PortionEntryUnit.weight($0)) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct PortionUnitOptions: View {
    let portion: FoodPortion

    var body: some View {
        Text("Servings").tag(PortionEntryUnit.servings)
        if portion.canWeigh {
            ForEach(WeightUnit.allCases) { unit in
                Text(PortionEntryUnit.weight(unit).title).tag(PortionEntryUnit.weight(unit))
            }
        }
        if portion.canMeasureVolume {
            ForEach(VolumeUnit.allCases) { Text($0.title).tag(PortionEntryUnit.volume($0)) }
        }
    }
}

/// Types a portion's amount in its selected serving, weight or volume unit.
private struct AmountField: View {
    @Binding var portion: FoodPortion
    let width: CGFloat

    var body: some View {
        let digits = portion.enteredVolumeUnit?.fractionDigits ?? portion.enteredWeightUnit?.fractionDigits ?? 2
        TextField("0", value: $portion.enteredAmount, format: .number.precision(.fractionLength(0...digits)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(maxWidth: width)
            .accessibilityLabel("\(portion.enteredVolumeUnit?.title ?? portion.enteredWeightUnit?.title ?? "Servings") of \(portion.name)")
    }
}

/// Steps a portion's amount: half servings, 5 g or a quarter ounce at a time.
private struct AmountStepper: View {
    @Binding var portion: FoodPortion
    /// The range when entering servings.
    let servings: ClosedRange<Double>

    var body: some View {
        let range: ClosedRange<Double> = switch portion.entryUnit {
        case .weight(.grams), .volume(.milliliters): 0...5000
        case .weight(.ounces): 0...176
        case .volume: 0...180
        case .servings: servings
        }
        Stepper("Amount of \(portion.name)", value: $portion.enteredAmount, in: range,
                step: portion.enteredVolumeUnit?.step ?? portion.enteredWeightUnit?.step ?? 0.5)
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
    /// For a meal from a photo with a restaurant or brand: why its lookup failed, if it did, and the brand's
    /// published foods to add or replace foods with.
    private var branded: BrandedMeal?
    /// Looks the brand's nutrition up again after a failure.
    private var onRetryLookup: (() -> Void)?

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [Food]
    @State private var portions: [FoodPortion]
    /// What to ask about foods from a branded photo: which published food it is, or whether a food that may be
    /// hidden was there. A food waiting for an answer stays at zero, so it isn't logged.
    @State private var reviews: [FoodPortion.ID: ItemReview] = [:]
    @State private var meal: Meal
    @State private var mealChosen: Bool
    @State private var date: Date
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved = false
    @State private var savingRecipe = false
    @State private var addingFood = false
    @State private var replacing: Replacement?
    /// A measured volume can't be carried to a food without a volume basis. Keep it out of totals until reviewed.
    @State private var unconfirmedPortions: [FoodPortion.ID: FoodPortion] = [:]

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

    /// A meal from a photo with a restaurant or brand, its foods matched to the brand's published nutrition.
    init(branded meal: BrandedMeal, date: Date?, onRetryLookup: (() -> Void)?, onSaved: (() -> Void)? = nil) {
        let estimates = meal.failure != nil || meal.published.isEmpty
        self.init(title: "\(meal.brand) Meal", portions: meal.portions, date: date,
                  note: estimates ? "Estimated from your photo. Check each food and amount before logging."
                      : "Foods marked Published use \(meal.brand)'s nutrition; the rest are estimates. Amounts come "
                        + "from your photo and details, so check them before logging.",
                  onSaved: onSaved)
        branded = meal
        self.onRetryLookup = onRetryLookup
        _reviews = State(initialValue: meal.reviews)
    }

    var body: some View {
        Form {
            if let branded { lookupStatus(branded) }
            Section {
                ForEach($portions) { $portion in
                    VStack(alignment: .leading, spacing: 6) {
                        PortionRow(portion: $portion, zeroText: zeroText(for: portion))
                        if let original = unconfirmedPortions[portion.id], portion.servings > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(original.amountText) can't be converted to this food's servings. Enter a serving amount, then confirm it. It isn't counted yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Confirm \(portion.amountText)") {
                                    unconfirmedPortions[portion.id] = nil
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Confirm amount of \(portion.name)")
                            }
                        }
                        if let review = reviews[portion.id] {
                            ReviewPrompt(portion: portion, review: review, brand: branded?.brand ?? "",
                                         onChoose: { choose($0, for: portion) },
                                         onUseEstimate: { useEstimate(for: portion) },
                                         onInclude: { include(portion) })
                        }
                    }
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
                Text([note, branded == nil
                      ? "Set a food to 0 to leave it out, or swipe left on it to replace it with one of your foods."
                      : "Set a food to 0 to leave it out, or swipe left on it to replace it."]
                    .compactMap { $0 }.joined(separator: " "))
            }
            NutritionTotals(portions: included)
            if !foodsWithoutNutrition.isEmpty {
                Section {
                    Label("Some foods have no known nutrition", systemImage: "info.circle")
                    Text(foodsWithoutNutrition.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Add nutrition or leave these foods out before logging. If another ingredient has nutrition, save the meal as a recipe to preserve the unavailable ingredients and their partial totals.")
                }
            }
            sourcesSection
            MealAndTimeSection(meal: $meal, mealChosen: $mealChosen, date: $date)
            Section {
                Button("Save as Recipe", systemImage: "book.closed") { savingRecipe = true }
                    .disabled(!included.contains(where: \.hasKnownNutrition) || needsPortionConfirmation)
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
                MealFoodPicker(title: "Add Food", branded: branded, allowsMultiple: true) { picked in
                    portions += picked
                    addingFood = false
                }
                .cancelButton { addingFood = false }
            }
        }
        .sheet(item: $replacing) { target in
            NavigationStack {
                MealFoodPicker(title: "Replace \(target.name)", branded: branded) { picked in
                    if let food = picked.first, let index = portions.firstIndex(where: { $0.id == target.id }) {
                        replacePortion(at: index, with: food)
                        reviews[target.id] = nil
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
                Button("Log", action: save)
                    .disabled(isSaving || included.isEmpty || needsPortionConfirmation || !foodsWithoutNutrition.isEmpty)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    /// Why the brand's nutrition couldn't be used, with a way to try again or check its own pages.
    @ViewBuilder
    private func lookupStatus(_ branded: BrandedMeal) -> some View {
        if let failure = branded.failure {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Couldn't Look Up \(branded.brand)").font(.headline)
                        Text(failure.localizedDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let onRetryLookup {
                    Button("Try Again", systemImage: "arrow.clockwise", action: onRetryLookup)
                }
            } footer: {
                Text("Until then, these are Apple Intelligence's estimates from your photo. You can also replace a "
                     + "food with one of yours.")
            }
        } else if branded.published.isEmpty {
            Section {
                Label("\(branded.brand)'s published nutrition wasn't found, so these are Apple Intelligence's "
                      + "estimates from your photo.", systemImage: "magnifyingglass")
                ForEach(branded.pages, id: \.url) { page in
                    Link(destination: page.url) { Label(page.title, systemImage: "safari") }
                }
            } footer: {
                if !branded.pages.isEmpty {
                    Text("To use \(branded.brand)'s own figures, check them there, then replace a food with a new "
                         + "one of yours that has them.")
                }
            }
        }
    }

    /// Where the counted foods' published values come from.
    @ViewBuilder
    private var sourcesSection: some View {
        let sources = BrandedMeal.sources(of: included)
        if !sources.isEmpty {
            Section {
                ForEach(sources, id: \.url) { SourceRow(source: $0, showsServing: false) }
            } header: {
                Text("Sources")
            } footer: {
                Text("Published values are for the serving shown with each food. "
                     + (branded == nil ? "" : "The amounts come from your photo and details. ")
                     + "Nutrients a source doesn't publish aren't counted.")
            }
        }
    }

    private var included: [FoodPortion] {
        portions.filter { $0.servings.isFinite && $0.servings > 0 && unconfirmedPortions[$0.id] == nil }
    }

    private var foodsWithoutNutrition: [FoodPortion] {
        included.filter { !$0.hasKnownNutrition }
    }

    private var needsPortionConfirmation: Bool {
        portions.contains { $0.servings > 0 && unconfirmedPortions[$0.id] != nil }
    }

    private func replacePortion(at index: Int, with food: FoodPortion) {
        let previous = portions[index]
        // Replacing an unconfirmed choice again must not silently confirm its default serving count.
        let original = unconfirmedPortions[previous.id] ?? previous
        let replacement = original.replaced(by: food)
        unconfirmedPortions[previous.id] = nil
        if original.enteredVolumeUnit != nil && !replacement.canMeasureVolume {
            unconfirmedPortions[replacement.id] = original
        }
        portions[index] = replacement
    }

    /// What a food at zero says: left out, or waiting for the prompt under it.
    private func zeroText(for portion: FoodPortion) -> String {
        guard let review = reviews[portion.id], !review.choices.isEmpty || review.needsConfirmation else {
            return "Left out"
        }
        return "Not counted yet"
    }

    private func replace(_ portion: FoodPortion) {
        replacing = Replacement(id: portion.id, name: portion.name)
    }

    /// Uses a published food the user picked for one that matched several, at the amount the photo suggested
    /// (or the amount they've typed).
    private func choose(_ choice: FoodPortion, for portion: FoodPortion) {
        settle(portion, as: choice)
    }

    /// Uses the on-device estimate for a food no published one is right for.
    private func useEstimate(for portion: FoodPortion) {
        guard let review = reviews[portion.id] else { return }
        settle(portion, as: review.estimate)
    }

    private func settle(_ portion: FoodPortion, as food: FoodPortion) {
        guard let index = portions.firstIndex(where: { $0.id == portion.id }), let review = reviews[portion.id] else {
            return
        }
        if portion.servings > 0 {
            replacePortion(at: index, with: food)
        } else {
            var settled = food
            settled.id = UUID()
            settled.servings = review.suggestedServings
            portions[index] = settled
        }
        let settled = portions[index]
        reviews[portion.id] = nil
        reviews[settled.id] = ItemReview(origin: review.origin, suggestedServings: review.suggestedServings,
                                         estimate: review.estimate)
    }

    /// Counts a food that may have been hidden, at the amount suggested.
    private func include(_ portion: FoodPortion) {
        guard let index = portions.firstIndex(where: { $0.id == portion.id }),
              let suggested = reviews[portion.id]?.suggestedServings else { return }
        portions[index].servings = suggested
        reviews[portion.id]?.needsConfirmation = false
    }

    private func save() {
        guard !isSaving, !included.isEmpty, !needsPortionConfirmation, foodsWithoutNutrition.isEmpty else { return }
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

/// What to check about a food from a branded photo: which of the brand's foods it is, or whether a food that may
/// be hidden was there, with where it came from.
private struct ReviewPrompt: View {
    let portion: FoodPortion
    let review: ItemReview
    let brand: String
    let onChoose: (FoodPortion) -> Void
    let onUseEstimate: () -> Void
    let onInclude: () -> Void

    var body: some View {
        if let note {
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        if !review.choices.isEmpty {
            HStack {
                Text(review.choices.count == 1 ? "Is it \(review.choices[0].name)?" : "Which is it?")
                    .font(.caption.bold())
                Spacer()
                Menu {
                    ForEach(review.choices) { choice in
                        Button {
                            onChoose(choice)
                        } label: {
                            Text(choice.name)
                            Text(choice.choiceDetail)
                        }
                    }
                    Divider()
                    Button("Use the Estimate", systemImage: "sparkles", action: onUseEstimate)
                } label: {
                    Text("Choose")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Choose which \(portion.name)")
            }
        } else if review.needsConfirmation && portion.servings == 0 {
            HStack {
                Text("Was it there?").font(.caption.bold())
                Spacer()
                Button("Include", action: onInclude)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Include \(portion.name)")
            }
        }
    }

    private var note: String? {
        if review.origin == .hidden && review.needsConfirmation {
            return "Usually under the other foods, but not in your photo or details."
        }
        if review.origin == .details { return "From your details." }
        if review.notFound && portion.isEstimate {
            return "Not in \(brand)'s published nutrition, so this is an estimate."
        }
        return nil
    }
}

extension FoodPortion {
    /// "4 oz · 210 kcal", to tell published foods apart when choosing one.
    var choiceDetail: String {
        [servingSize, calorieSummary].filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// A published source: its title linking to it, its website, what its values are for, and when they were read.
/// In a meal's list of sources, where several foods can share one document, each food shows its own serving
/// instead.
struct SourceRow: View {
    let source: NutritionSource
    var showsServing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(destination: source.url) {
                Label(source.title, systemImage: "link")
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        [source.provider.isEmpty ? nil : source.provider,
         source.servingBasis.isEmpty || !showsServing ? nil : "Per \(source.servingBasis)",
         source.market.flatMap { Locale.current.localizedString(forRegionCode: $0) },
         "Read \(source.retrieved.formatted(date: .abbreviated, time: .omitted))"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// A food in a list of several, with its amount to change: servings, or a weight for a food with a known serving
/// weight. At zero it shows `zeroText`.
struct PortionRow: View {
    @Binding var portion: FoodPortion
    let zeroText: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Enlarged text separates the unit from the amount, so neither is cut off.
        if dynamicTypeSize > .large {
            VStack(alignment: .leading, spacing: 8) {
                food
                unitMenu
                HStack {
                    AmountField(portion: $portion, width: .infinity)
                    AmountStepper(portion: $portion, servings: 0...50)
                }
            }
        } else if portion.enteredVolumeUnit != nil {
            VStack(alignment: .leading, spacing: 8) {
                food
                HStack { amount(width: .infinity) }
            }
        } else {
            HStack {
                food
                Spacer()
                amount(width: portion.entryUnit == .servings ? 44 : 56)
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
            NutritionBasisLabel(portion: portion)
            if portion.servings > 0 { NutritionAvailabilityLabel(portion: portion) }
        }
    }

    @ViewBuilder
    private func amount(width: CGFloat) -> some View {
        AmountField(portion: $portion, width: width)
        unitMenu
        AmountStepper(portion: $portion, servings: 0...50)
    }

    @ViewBuilder
    private var unitMenu: some View {
        if portion.canWeigh || portion.canMeasureVolume {
            Menu {
                Picker("Enter \(portion.name) In", selection: $portion.entryUnit) {
                    PortionUnitOptions(portion: portion)
                }
            } label: {
                HStack(spacing: 2) {
                    Text(portion.entryUnit.label ?? "×")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
            .accessibilityLabel("Unit for \(portion.name)")
            .accessibilityValue(portion.entryUnit.title)
        }
    }

}

/// Availability is separate from where a value came from or whether it is an estimate.
struct NutritionAvailabilityLabel: View {
    let portion: FoodPortion

    var body: some View {
        let missing = FoodNutrient.metrics.filter {
            let coverage = portion.coverage(of: $0.id)
            return coverage.isUnavailable || coverage.isPartial
        }
        let uncertain = FoodNutrient.metrics.contains { portion.coverage(of: $0.id).isUncertain }
        if uncertain {
            Text(missing.isEmpty ? "Ingredient coverage unknown"
                 : "Some nutrition unavailable; ingredient coverage unknown")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if !missing.isEmpty {
            Text("\(missing.count) \(missing.count == 1 ? "nutrient" : "nutrients") unavailable or partial")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Nutrition unavailable or partial: \(missing.map(\.name).joined(separator: ", "))")
        }
    }
}

/// Whether a food's nutrition is published by a restaurant or brand (and for what serving) or an estimate from a
/// photo. Nothing for a food's own label or a saved food.
struct NutritionBasisLabel: View {
    let portion: FoodPortion

    var body: some View {
        // Text rather than a Label, which a list row would space like its icon.
        if let source = portion.source {
            let text = source.servingBasis.isEmpty ? "Published" : "Published per \(source.servingBasis)"
            Text("\(Image(systemName: "checkmark.seal")) \(text)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(text)
        } else if portion.isEstimate {
            Text("\(Image(systemName: "sparkles")) Estimate")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Estimate")
        }
    }
}

/// What the portions add up to, per nutrient.
struct NutritionTotals: View {
    let portions: [FoodPortion]
    var title = "Nutrition"
    /// Recipe previews show per-serving amounts but name the original ingredients with missing values.
    var ingredientDetails: [FoodPortion]?

    var body: some View {
        let totals = FoodNutrition.totals(portions)
        Section {
            ForEach(FoodNutrient.metrics) { metric in
                let coverage = FoodNutrition.coverage(of: metric.id, in: portions)
                if let option = metric.unitOptions.first {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let total = totals[metric.id], !coverage.isUnavailable {
                                    Text(option.format(total)).monospacedDigit()
                                        .accessibilityIdentifier("nutritionValue-\(metric.id)")
                                    if coverage.isPartial {
                                        Text(coverage.isUncertain ? "Partial · Coverage unknown" : "Partial")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .accessibilityIdentifier("nutritionCoverage-\(metric.id)")
                                    } else if coverage.isUncertain {
                                        Text("Coverage unknown").font(.caption).foregroundStyle(.secondary)
                                            .accessibilityIdentifier("nutritionCoverage-\(metric.id)")
                                    }
                                } else {
                                    Text("Unavailable").foregroundStyle(.secondary)
                                        .accessibilityIdentifier("nutritionValue-\(metric.id)")
                                }
                            }
                        } label: {
                            Label(metric.name, systemImage: metric.systemImage)
                        }
                        if coverage.missing > 0 && !coverage.isUncertain {
                            Text(missingDetail(metric: metric, count: coverage.missing))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if coverage.isUncertain {
                            Text(coverage.isUnavailable || coverage.isPartial ? "Some nutrition unavailable; ingredient coverage unknown."
                                 : "Ingredient coverage wasn't recorded for every food.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Unavailable nutrients aren't treated as zero. Partial totals include only the available values; availability doesn't indicate accuracy.")
        }
    }

    private func missingDetail(metric: Metric, count: Int) -> String {
        let missing = (ingredientDetails ?? portions).filter {
            $0.servings.isFinite && $0.servings > 0 && $0.coverage(of: metric.id).missing > 0
        }
        if portions.count == 1, ingredientDetails == nil,
           portions[0].nutrientCoverage == nil, count == 1 {
            return "\(metric.name) isn't provided for this food."
        }
        let names = missing.map(\.name).joined(separator: ", ")
        let detail = "\(metric.name) unavailable for \(count) \(count == 1 ? "ingredient" : "ingredients")"
        if missing.contains(where: { $0.nutrientCoverage != nil }) { return detail + "." }
        return names.isEmpty ? detail + "." : detail + ": " + names + "."
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
    @State private var volumeUnit = VolumeUnit.milliliters
    @State private var saveError: String?

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
                textField("Serving Size", text: $draft.servingSize, prompt: "e.g. 1 cup, 30 g or 100 mL")
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
                LabeledContent("Serving Volume") {
                    HStack(spacing: 4) {
                        TextField("Serving Volume", value: servingVolume,
                                  format: .number.precision(.fractionLength(0...volumeUnit.fractionDigits)),
                                  prompt: Text("Optional"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .accessibilityLabel("Serving Volume in \(volumeUnit.title)")
                        Picker("Serving Volume Unit", selection: $volumeUnit) {
                            ForEach(VolumeUnit.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("servingVolumeUnit")
                    }
                }
                if let stated = draft.statedServingVolume {
                    Button("Use \(VolumeUnit.milliliters.format(milliliters: stated)) from Serving Size", systemImage: "measuringcup") {
                        draft.millilitersPerServing = stated
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    switch draft.source {
                    case .database:
                        Text("Filled in from [Open Food Facts](https://world.openfoodfacts.org), available under the [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/). Check it against the label before saving.")
                    case .notFound: Text("This barcode isn't in Open Food Facts. Scan its nutrition label or enter the details.")
                    case .label: Text("Filled in from the label. Check each amount against it, and add a name, before saving.")
                    case .manual: EmptyView()
                    }
                    Text("A serving weight enables grams and weight ounces. A serving volume enables mL and fluid ounces. U.S. and Imperial fluid ounces have different volumes; choose the one stated on the label.")
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
            } footer: {
                Text("Leave a nutrient blank when unavailable. Enter 0 only when the label states zero.")
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
        .alert("Couldn't Save Food", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func textField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }

    private var servingVolume: Binding<Double?> {
        Binding {
            draft.millilitersPerServing.map { volumeUnit.value(fromMilliliters: $0) }
        } set: { value in
            draft.millilitersPerServing = value.map { volumeUnit.milliliters(from: $0) }
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
                TextField("Unavailable", value: amount, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                    .accessibilityLabel("\(metric.name) in \(option.label)")
                Text(option.label).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let previous = food?.draft
        let saved: Food
        if let food {
            food.update(from: draft)
            saved = food
        } else {
            saved = Food(draft)
            context.insert(saved)
        }
        do {
            // A successful Save must survive the app closing immediately afterward.
            try context.save()
            onSave(saved)
        } catch {
            if let previous {
                saved.update(from: previous)
            } else {
                context.delete(saved)
            }
            saveError = error.localizedDescription
        }
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
