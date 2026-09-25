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
    @State private var recentFoods: [FoodPortion] = []
    @State private var recentMeals: [RecentMeal] = []
    /// Recent foods and meals logged a moment ago with their quick-log button, to show a checkmark.
    @State private var justLogged: Set<String> = []
    @State private var error: String?

    private static let recentFoodLimit = 8
    private static let recentMealLimit = 3
    private static let recentDays = 30

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
        let since = Calendar.current.date(byAdding: .day, value: -Self.recentDays, to: .now)!
        // Recents are a shortcut, so if Health can't be read (such as while locked) just keep what's showing.
        guard let entries = try? await health.recentEntries(of: [], since: since, limit: 500) else { return }

        var foods: [FoodPortion] = []
        for case let food? in entries.map(\.food) where !foods.contains(where: { $0.isSameFood(as: food) }) {
            foods.append(food)
            if foods.count == Self.recentFoodLimit { break }
        }
        recentFoods = foods

        // Meals of two or more foods, newest first, skipping repeats of the same foods at the same meal.
        let calendar = Calendar.current
        var meals: [RecentMeal] = []
        var seen: Set<String> = []
        let groups = Dictionary(grouping: entries.filter { $0.food != nil && $0.meal != nil }) {
            MealKey(day: calendar.startOfDay(for: $0.date), meal: $0.meal!)
        }
        for key in groups.keys.sorted(by: { $0.day != $1.day ? $0.day > $1.day : $0.meal.sortOrder > $1.meal.sortOrder }) {
            let entries = groups[key]!.sorted { $0.date < $1.date }
            guard entries.count >= 2 else { continue }
            let meal = RecentMeal(day: key.day, meal: key.meal, foods: entries.compactMap(\.food))
            guard seen.insert(meal.id).inserted else { continue }
            meals.append(meal)
            if meals.count == Self.recentMealLimit { break }
        }
        recentMeals = meals
    }

    private struct MealKey: Hashable {
        let day: Date
        let meal: Meal
    }
}

/// The foods eaten at one meal on one day.
private struct RecentMeal: Identifiable {
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

private extension Meal {
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

    /// "Brand · 2 × 1 cup · 300 kcal", skipping whatever is missing.
    var summary: String {
        let count = servings.formatted(.number.precision(.fractionLength(0...2)))
        let amount = if servingSize.isEmpty {
            servings == 1 ? "1 serving" : "\(count) servings"
        } else {
            servings == 1 ? servingSize : "\(count) × \(servingSize)"
        }
        return [brand, amount, formatCalories(calories)].filter { !$0.isEmpty }.joined(separator: " · ")
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

/// Logs one food, by the serving.
struct LogFoodView: View {
    /// Marks the saved food or recipe this came from, if any, as just logged so it moves up its list.
    private let markLogged: () -> Void
    /// Called after saving; pops this screen when nil.
    var onSaved: (() -> Void)?

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var portion: FoodPortion
    @State private var meal = Meal(at: .now)
    /// Once the user picks a meal, changing the time no longer changes it.
    @State private var mealChosen = false
    @State private var date = Date.now
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved = false

    init(food: Food, onSaved: (() -> Void)? = nil) {
        self.init(food.portion, food: food, onSaved: onSaved)
    }

    init(_ portion: FoodPortion, food: Food? = nil, onSaved: (() -> Void)? = nil) {
        self.init(portion, onSaved: onSaved) { food?.lastLogged = .now }
    }

    init(recipe: Recipe, onSaved: (() -> Void)? = nil) {
        self.init(recipe.portion, onSaved: onSaved) { recipe.lastLogged = .now }
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
                HStack {
                    Text("Servings")
                    Spacer()
                    TextField("1", value: $portion.servings, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 60)
                    Stepper("Servings", value: $portion.servings, in: 0.5...20, step: 0.5)
                        .labelsHidden()
                }
            } header: {
                if !portion.brand.isEmpty { Text(portion.brand) }
            }
            NutritionTotals(portions: [portion])
            MealAndTimeSection(meal: $meal, mealChosen: $mealChosen, date: $date)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(portion.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Log", action: save).disabled(isSaving || portion.servings <= 0)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await health.saveFoods([portion], meal: meal, date: date)
                markLogged()
                saved.toggle()
                if let onSaved { onSaved() } else { dismiss() }
            } catch {
                self.error = error.healthMessage
            }
        }
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
                ForEach($portions) { PortionRow(portion: $0, zeroText: "Left out") }
            } header: {
                Text("Foods")
            } footer: {
                Text([note, "Set a food to 0 servings to leave it out."].compactMap { $0 }.joined(separator: " "))
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

    private func save() {
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

/// A food in a list of several, with its servings to change. At zero servings it shows `zeroText`.
struct PortionRow: View {
    @Binding var portion: FoodPortion
    let zeroText: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(portion.name)
                    .foregroundStyle(portion.servings > 0 ? .primary : .secondary)
                Text(portion.servings > 0 ? portion.summary : zeroText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", value: $portion.servings, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 44)
                .accessibilityLabel("Servings of \(portion.name)")
            Stepper("Servings of \(portion.name)", value: $portion.servings, in: 0...50, step: 0.5)
                .labelsHidden()
        }
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
            } footer: {
                switch draft.source {
                case .database: Text("Filled in from Open Food Facts. Check it against the label before saving.")
                case .notFound: Text("This barcode isn't in Open Food Facts. Scan its nutrition label or enter the details.")
                case .label: Text("Filled in from the label. Check each amount against it, and add a name, before saving.")
                case .manual: EmptyView()
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
