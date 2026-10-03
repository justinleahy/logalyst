import Foundation

/// What the meal screen asks about a food from a branded photo before it's counted.
struct ItemReview: Hashable {
    /// Whether the photo shows it, the user's description mentions it, or it may be hidden under other foods.
    var origin: MealPhoto.BrandedItem.Origin
    /// Published foods it might be, best first. It isn't counted until one is chosen (or its estimate is used).
    var choices: [FoodPortion] = []
    /// A food that may be hidden, which isn't counted until it's confirmed.
    var needsConfirmation = false
    /// How much the photo or description suggests, in the brand's standard portions, to count once it's chosen
    /// or confirmed.
    var suggestedServings: Double
    /// The on-device estimate, to use instead when no published food is right.
    var estimate: FoodPortion
    /// The lookup worked but found nothing for it.
    var notFound = false
}

/// A photo of a meal from a restaurant or brand, put together from the foods the on-device model saw and the
/// brand's published nutrition, ready to check on the meal screen.
struct BrandedMeal: Hashable {
    var brand: String
    var portions: [FoodPortion]
    var reviews: [FoodPortion.ID: ItemReview]
    /// Every published food the lookup found, to pick from when adding or replacing a food.
    var published: [PublishedFood]
    /// The brand's own nutrition pages, when nothing was found, for the user to check.
    var pages: [NutritionPage] = []
    /// Why the lookup didn't work, in which case every food is an estimate.
    var failure: LookupError?

    /// Published values are used for a clear match, scaled by the portions from the photo and description. A food
    /// matching several published ones, or that may be hidden, waits at zero for the user. Anything else falls
    /// back to a saved food with exactly its name, then to the estimate, so a saved food never replaces a published
    /// match.
    static func assemble(items: [MealPhoto.BrandedItem], brand: String,
                         lookup: Result<LookupResult, LookupError>,
                         known: [FoodPortion]) -> BrandedMeal {
        let found = (try? lookup.get())?.foods ?? [:]
        var portions: [FoodPortion] = []
        var reviews: [FoodPortion.ID: ItemReview] = [:]
        for item in items {
            var review = ItemReview(origin: item.origin, suggestedServings: item.portions, estimate: item.estimate)
            let key = LookupRequest.key(for: item.searchTerm)
            let candidates = found[key] ?? []
            var portion: FoodPortion
            switch NutritionMatcher.match(name: item.name, term: item.searchTerm, among: candidates, brand: brand) {
            case .matched(let food):
                portion = food.portion
                portion.servings = item.portions
            case .ambiguous(let foods):
                portion = item.estimate
                review.choices = foods.map(\.portion)
            case .none:
                if var saved = MealPhoto.savedFood(named: item.name, in: known) {
                    saved.servings = item.portions
                    portion = saved
                } else {
                    portion = item.estimate
                    // Only a food that was looked up (not one past the request's limit) is known not to be listed.
                    review.notFound = found[key] != nil
                }
            }
            review.needsConfirmation = item.origin == .hidden
            if !review.choices.isEmpty || review.needsConfirmation { portion.servings = 0 }
            portions.append(portion)
            reviews[portion.id] = review
        }
        var seen: Set<String> = []
        let published = found.values.joined().filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let failure: LookupError? = if case .failure(let error) = lookup { error } else { nil }
        return BrandedMeal(brand: brand, portions: portions, reviews: reviews, published: published,
                           pages: (try? lookup.get())?.pages ?? [], failure: failure)
    }

    /// The sources of the given foods, once each, in the order the foods are listed.
    static func sources(of portions: [FoodPortion]) -> [NutritionSource] {
        var seen: Set<URL> = []
        return portions.compactMap(\.source).filter { seen.insert($0.url).inserted }
    }
}
