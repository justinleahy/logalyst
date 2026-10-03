import SwiftUI
import SwiftData

/// Picks saved foods, one serving each to start (or a serving's weight, for a food whose serving is just a weight),
/// searching My Foods or making a new one. Used to add recipe ingredients and to add or replace foods in a meal.
/// With `allowsMultiple`, foods are checked off and then added together in the order they were picked.
struct FoodPicker: View {
    let title: String
    var allowsMultiple = false
    /// The button that adds the checked foods, when picking several.
    var confirmTitle = "Add"
    let onPick: ([FoodPortion]) -> Void

    @Query(sort: \Food.name) private var foods: [Food]
    @State private var search = ""
    @State private var creating = false
    /// Checked foods, in the order they were picked.
    @State private var selection: [Food] = []

    var body: some View {
        List(visibleFoods) { food in
            let isSelected = selection.contains { $0 === food }
            Button {
                pick(food)
            } label: {
                HStack {
                    // Colors rather than levels, which a button would take from its tint.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).foregroundStyle(Color.primary)
                        if !food.summary.isEmpty {
                            Text(food.summary).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                    if allowsMultiple {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .overlay {
            if foods.isEmpty {
                ContentUnavailableView {
                    Label("No Foods Yet", systemImage: "fork.knife")
                } description: {
                    Text("Your saved foods show up here. Create one to add it.")
                } actions: {
                    Button("New Food") { creating = true }
                }
            } else if visibleFoods.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search My Foods")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Food", systemImage: "plus") { creating = true }
            }
            if allowsMultiple {
                ToolbarItem(placement: .confirmationAction) {
                    Button(selection.isEmpty ? confirmTitle : "\(confirmTitle) (\(selection.count))") {
                        onPick(selection.map(\.portion))
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                FoodEditor { food in
                    creating = false
                    if allowsMultiple {
                        selection.append(food)
                    } else {
                        onPick([food.portion])
                    }
                }
                .cancelButton { creating = false }
            }
        }
    }

    private func pick(_ food: Food) {
        guard allowsMultiple else {
            onPick([food.portion])
            return
        }
        if let index = selection.firstIndex(where: { $0 === food }) {
            selection.remove(at: index)
        } else {
            selection.append(food)
        }
    }

    private var visibleFoods: [Food] {
        search.isEmpty ? foods : foods.filter {
            $0.name.localizedStandardContains(search) || $0.brand.localizedStandardContains(search)
        }
    }
}

/// Starts a meal from several saved foods, without making a recipe first, then opens it to adjust and log.
/// Works without Photo of Meal, which needs Apple Intelligence.
struct NewMealView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Picked] = []

    private struct Picked: Hashable {
        let foods: [FoodPortion]
    }

    var body: some View {
        NavigationStack(path: $path) {
            FoodPicker(title: "New Meal", allowsMultiple: true, confirmTitle: "Next") { foods in
                path = [Picked(foods: foods)]
            }
            .cancelButton { dismiss() }
            .navigationDestination(for: Picked.self) { picked in
                LogMealView(title: "New Meal", portions: picked.foods) { dismiss() }
            }
        }
    }
}
