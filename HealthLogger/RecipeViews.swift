import SwiftUI
import SwiftData

/// Creates or edits a recipe: a name, how many servings it makes, and servings of saved foods.
struct RecipeEditor: View {
    let recipe: Recipe?
    let onSave: (Recipe) -> Void

    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var servings: Double
    @State private var ingredients: [FoodPortion]
    @State private var addingIngredient = false

    init(recipe: Recipe? = nil, ingredients: [FoodPortion] = [], onSave: @escaping (Recipe) -> Void) {
        self.recipe = recipe
        self.onSave = onSave
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.servings ?? 1)
        _ingredients = State(initialValue: recipe?.ingredients ?? ingredients)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Name", text: $name, prompt: Text("Required"))
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Makes")
                    Spacer()
                    TextField("1", value: $servings, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                    Text(servings == 1 ? "serving" : "servings").foregroundStyle(.secondary)
                    Stepper("Servings", value: $servings, in: 1...50, step: 1)
                        .labelsHidden()
                }
            }
            Section {
                ForEach($ingredients) { PortionRow(portion: $0, zeroText: "None") }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                Button("Add Ingredient", systemImage: "plus.circle") { addingIngredient = true }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Amounts are in servings of each food, or by weight for foods with a serving weight. "
                     + "Swipe to remove one.")
            }
            if servings > 0 {
                NutritionTotals(portions: [perServing], title: "Nutrition per Serving")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!isValid)
            }
        }
        .sheet(isPresented: $addingIngredient) {
            NavigationStack {
                FoodPicker(title: "Add Ingredient") { picked in
                    ingredients += picked
                    addingIngredient = false
                }
                .cancelButton { addingIngredient = false }
            }
        }
    }

    private var used: [FoodPortion] {
        ingredients.filter { $0.servings > 0 }
    }

    private var perServing: FoodPortion {
        FoodPortion(name: name, nutrients: Recipe.perServing(used, servings: servings))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && servings > 0 && !used.isEmpty
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespaces)
        let saved: Recipe
        if let recipe {
            recipe.name = name
            recipe.servings = servings
            recipe.ingredients = used
            saved = recipe
        } else {
            saved = Recipe(name: name, servings: servings, ingredients: used)
            context.insert(saved)
        }
        onSave(saved)
    }
}
