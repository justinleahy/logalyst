import SwiftUI

/// Picks a food for a meal: from My Foods, or for a meal from a branded photo, from the brand's published foods too.
struct MealFoodPicker: View {
    let title: String
    /// The meal's brand and the published foods its lookup found, if it's from a branded photo.
    let branded: BrandedMeal?
    var allowsMultiple = false
    let onPick: ([FoodPortion]) -> Void

    @State private var showingBrand = true

    var body: some View {
        if let branded {
            Group {
                if showingBrand {
                    PublishedFoodPicker(title: title, brand: branded.brand, found: branded.published) { onPick([$0]) }
                } else {
                    FoodPicker(title: title, allowsMultiple: allowsMultiple, onPick: onPick)
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Foods From", selection: $showingBrand) {
                    Text(branded.brand).tag(true)
                    Text("My Foods").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(.bar)
            }
        } else {
            FoodPicker(title: title, allowsMultiple: allowsMultiple, onPick: onPick)
        }
    }
}

/// A brand's published foods: the ones already found for the meal, filtered as the user types, and more from what
/// the brand publishes when they tap Search.
struct PublishedFoodPicker: View {
    let title: String
    let brand: String
    /// Foods the meal's lookup found.
    let found: [PublishedFood]
    let onPick: (FoodPortion) -> Void

    @State private var search = ""
    @State private var searched: [PublishedFood] = []
    @State private var lookup: Task<Void, Never>?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(visible) { food in
                    Button {
                        onPick(food.portion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).foregroundStyle(Color.primary)
                            Text(food.portion.choiceDetail).font(.caption).foregroundStyle(Color.secondary)
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let message { Text(message) }
                    Text(search.isEmpty
                         ? "Type a food, then tap Search to find it in the nutrition \(brand) publishes."
                         : "Tap Search to find “\(cleanSearch)” in the nutrition \(brand) publishes on its website.")
                }
            }
        }
        .overlay {
            if lookup != nil {
                ProgressView("Looking Up…")
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "No \(brand) Foods Yet" : "No Results", systemImage: "magnifyingglass")
                } description: {
                    Text(search.isEmpty ? "Search for one of \(brand)'s foods."
                         : "Tap Search to find “\(cleanSearch)” in what \(brand) publishes.")
                }
            }
        }
        .searchable(text: $search, prompt: "Search \(brand)")
        .onSubmit(of: .search) { lookUp() }
        .onChange(of: search) { message = nil }
        .onDisappear { lookup?.cancel() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cleanSearch: String {
        LookupRequest.clean(search, maxLength: LookupRequest.maxTermLength)
    }

    /// Foods found online first, then the meal's, once each, matching what's typed.
    private var visible: [PublishedFood] {
        var seen: Set<String> = []
        let all = (searched + found).filter { seen.insert($0.id).inserted }
        let words = NutritionMatcher.words(search)
        guard !words.isEmpty else { return all }
        return all.filter { NutritionMatcher.score(words, NutritionMatcher.words($0.name)) > 0 }
    }

    private func lookUp() {
        guard lookup == nil, let request = LookupRequest(brand: brand, terms: [search]) else { return }
        message = nil
        lookup = Task {
            defer { lookup = nil }
            do {
                let result = try await NutritionLookup.shared.foods(for: request)
                let foods = result.foods.values.joined()
                searched = Array(foods) + searched
                if foods.isEmpty { message = "Nothing was found for “\(request.terms[0])” at \(brand)." }
            } catch let error as LookupError {
                message = error.localizedDescription
            } catch {}
        }
    }
}
