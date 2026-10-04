import Foundation
import SwiftData
import Testing
@testable import HealthLogger

// C5: restaurant and brand nutrition lookup for meal photos. Values are Chipotle's published US nutrition facts
// (https://www.chipotle.com/content/dam/chipotle/menu/nutrition/US-Nutrition-Facts-Paper-Menu-3-2025.pdf).

private let retrieved = Date(timeIntervalSince1970: 1_791_000_000)

private let pdf = URL(string: "https://www.chipotle.com/content/dam/chipotle/menu/nutrition/US-Nutrition-Facts-Paper-Menu-3-2025.pdf")!

private func source(_ name: String, serving: String = "4 oz") -> NutritionSource {
    NutritionSource(title: "Full Nutrition Facts", url: pdf, retrieved: retrieved, market: nil, servingBasis: serving,
                    provider: "chipotle.com")
}

private func published(_ name: String, _ nutrients: [String: Double], grams: Double? = nil) -> PublishedFood {
    PublishedFood(id: "\(pdf)#\(name)", name: name, brand: "Chipotle", nutrients: nutrients,
                  gramsPerServing: grams, source: source(name))
}

private let chicken = published("Chicken", [
    "dietaryEnergyConsumed": 180, "dietaryFatTotal": 7, "dietaryFatSaturated": 3, "dietaryCholesterol": 125,
    "dietarySodium": 310, "dietaryCarbohydrates": 0, "dietaryFiber": 0, "dietarySugar": 0, "dietaryProtein": 32,
])
private let whiteRice = published("Cilantro-Lime White Rice", [
    "dietaryEnergyConsumed": 210, "dietaryFatTotal": 4, "dietaryFatSaturated": 1, "dietaryCholesterol": 0,
    "dietarySodium": 350, "dietaryCarbohydrates": 40, "dietaryFiber": 1, "dietarySugar": 0, "dietaryProtein": 4,
])
private let brownRice = published("Cilantro-Lime Brown Rice", [
    "dietaryEnergyConsumed": 210, "dietaryFatTotal": 6, "dietarySodium": 190, "dietaryCarbohydrates": 36,
    "dietaryProtein": 4,
])
private let blackBeans = published("Black Beans", [
    "dietaryEnergyConsumed": 130, "dietaryFatTotal": 1.5, "dietaryFatSaturated": 0, "dietaryCholesterol": 0,
    "dietarySodium": 210, "dietaryCarbohydrates": 22, "dietaryFiber": 7, "dietarySugar": 2, "dietaryProtein": 8,
])
private let pintoBeans = published("Pinto Beans", ["dietaryEnergyConsumed": 130, "dietaryProtein": 8])
/// Published without sugar, which must stay unknown.
private let guacamole = published("Guacamole", ["dietaryEnergyConsumed": 230, "dietaryFatTotal": 22])

private func estimate(_ name: String, _ calories: Double, servings: Double = 1) -> FoodPortion {
    FoodPortion(name: name, servingSize: "1 serving", nutrients: ["dietaryEnergyConsumed": calories,
                                                                   "dietarySugar": 1],
                servings: servings, isEstimate: true)
}

private func item(_ name: String, term: String? = nil, portions: Double = 1,
                  origin: MealPhoto.BrandedItem.Origin = .photo) -> MealPhoto.BrandedItem {
    MealPhoto.BrandedItem(name: name, searchTerm: term ?? name.lowercased(), portions: portions, origin: origin,
                          estimate: estimate(name, 999, servings: portions))
}

// MARK: - What's looked for

@MainActor
struct LookupRequestTests {
    @Test func termsAreCleanedShortenedAndNotRepeated() throws {
        let request = try #require(LookupRequest(
            brand: "  Chipotle\n", terms: ["White Rice", "white rice", "chicken!", "", "   "]))
        #expect(request.brand == "Chipotle")
        #expect(request.terms == ["white rice", "chicken"])
    }

    @Test func namesKeepTheirPunctuation() throws {
        let request = try #require(LookupRequest(brand: "Ben & Jerry's", terms: ["Cookie-Dough", "7-Eleven"]))
        #expect(request.brand == "Ben & Jerry's")
        #expect(request.terms == ["cookie-dough", "7-eleven"])
    }

    @Test func longTextIsCutAtAWordAndTermsAreLimited() throws {
        let words = "grilled chicken with extra spicy salsa verde and also some lime"
        let request = try #require(LookupRequest(brand: String(repeating: "A", count: 80),
                                                 terms: [words] + (1...20).map { "food \($0)" }))
        #expect(request.brand.count == LookupRequest.maxBrandLength)
        #expect(request.terms.count == LookupRequest.maxTerms)
        #expect(request.terms[0] == "grilled chicken with extra spicy salsa")
        #expect(request.terms.allSatisfy { $0.count <= LookupRequest.maxTermLength })
    }

    @Test(arguments: [("", ["rice"]), ("Chipotle", []), ("!!!", ["rice"]), ("Chipotle", ["???"])])
    func nothingToLookUpIsNoRequest(brand: String, terms: [String]) {
        #expect(LookupRequest(brand: brand, terms: terms) == nil)
    }

    @Test func networkErrorsSayWhatToDo() {
        #expect(LookupError(URLError(.notConnectedToInternet)) == .offline)
        #expect(LookupError(URLError(.timedOut)) == .timedOut)
        #expect(LookupError(URLError(.badServerResponse)) == .unavailable)
        #expect(LookupError(URLError(.cancelled)) == nil)
        #expect(LookupError(CancellationError()) == nil)
        #expect(LookupError.rateLimited(retryAfter: 3600).localizedDescription.contains("60 minutes"))
    }
}

// MARK: - Matching

@MainActor
struct NutritionMatcherTests {
    private let menu = [chicken, whiteRice, brownRice, blackBeans, pintoBeans, guacamole,
                        published("Chicken Al Pastor", ["dietaryEnergyConsumed": 210])]

    private func match(_ name: String, _ term: String? = nil) -> NutritionMatch {
        NutritionMatcher.match(name: name, term: term ?? name, among: menu, brand: "Chipotle")
    }

    @Test func theSameNameMatches() {
        #expect(match("Chicken") == .matched(chicken))
        #expect(match("Black Beans", "black beans") == .matched(blackBeans))
    }

    @Test func aCommonShortNameMatchesTheFullOne() {
        #expect(match("Guac") == .matched(guacamole))
        let veggies = published("Fajita Vegetables", ["dietaryEnergyConsumed": 20])
        #expect(NutritionMatcher.match(name: "Fajita Veggies", term: "fajita veggies", among: [veggies, chicken],
                                       brand: "Chipotle") == .matched(veggies))
    }

    /// A word that only begins a longer one isn't that food: a lime wedge isn't limeade.
    @Test func aWordInsideAnotherIsntAMatch() {
        let limeade = published("Tractor Watermelon Limeade", ["dietaryEnergyConsumed": 230])
        #expect(NutritionMatcher.match(name: "Lime Wedge", term: "lime", among: [limeade, whiteRice],
                                       brand: "Chipotle") == .none)
    }

    @Test func enoughWordsPickOne() {
        #expect(match("White Rice") == .matched(whiteRice))
    }

    /// Ready when: ambiguous matches can be corrected before logging. "Rice" is never guessed.
    @Test func foodsThatFitEquallyAreLeftToTheUser() {
        #expect(match("Rice") == .ambiguous([whiteRice, brownRice]))
        guard case .ambiguous(let beans) = match("Beans") else { Issue.record("Not ambiguous"); return }
        #expect(Set(beans) == [blackBeans, pintoBeans])
    }

    @Test func nothingLikeItIsNoMatch() {
        #expect(match("Lime Wedge", "lime") == .none)
        #expect(NutritionMatcher.match(name: "Chicken", term: "chicken", among: [], brand: "Chipotle") == .none)
    }

    @Test func theBrandsNameIsIgnored() {
        let named = published("Chipotle Chicken", ["dietaryEnergyConsumed": 180])
        #expect(NutritionMatcher.match(name: "Chicken", term: "chicken", among: [named], brand: "Chipotle")
                == .matched(named))
    }

    @Test func theSameFoodListedTwiceIsOneChoice() {
        var copy = chicken
        copy.id = "other"
        #expect(NutritionMatcher.match(name: "Chicken", term: "chicken", among: [chicken, copy], brand: "Chipotle")
                == .matched(chicken))
    }

    /// A word in a longer name only counts as that food when it's what the name is.
    @Test func aWordThatOnlyDescribesAFoodDoesntMatchIt() {
        #expect(NutritionMatcher.score(["lime"], NutritionMatcher.words("Cilantro-Lime White Rice"))
                < NutritionMatcher.candidateScore)
        #expect(NutritionMatcher.score(["rice"], NutritionMatcher.words("Cilantro-Lime White Rice"))
                >= NutritionMatcher.candidateScore)
    }

    @Test func wordsIgnoreCaseAccentsPluralsAndFiller() {
        #expect(NutritionMatcher.words("Fajita Veggies") == ["fajita", "vegetable"])
        #expect(NutritionMatcher.words("Side of Tomatoes") == ["tomato"])
        #expect(NutritionMatcher.words("Café Crème") == ["cafe", "creme"])
        #expect(NutritionMatcher.words("Chips & Guacamole") == ["chip", "guacamole"])
    }
}

// MARK: - Putting the meal together

@MainActor
struct BrandedMealTests {
    /// What a lookup of these terms finds: nothing for "lime".
    private let menu: [String: [PublishedFood]] = [
        "chicken": [chicken], "rice": [whiteRice, brownRice], "black beans": [blackBeans], "guac": [guacamole],
        "lime": [],
    ]

    private func assemble(_ items: [MealPhoto.BrandedItem],
                          lookup: Result<LookupResult, LookupError>? = nil,
                          known: [FoodPortion] = []) -> BrandedMeal {
        BrandedMeal.assemble(items: items, brand: "Chipotle",
                             lookup: lookup ?? .success(LookupResult(foods: menu)), known: known)
    }

    /// Ready when: a confirmed double portion scales each published nutrient exactly twice.
    @Test func aDoublePortionIsExactlyTwiceEachPublishedNutrient() throws {
        let meal = assemble([item("Chicken", portions: 2, origin: .details)])
        let portion = try #require(meal.portions.first)
        #expect(portion.source == chicken.source)
        #expect(portion.servings == 2)
        #expect(portion.amountText == "2 × 4 oz")
        for (id, value) in chicken.nutrients {
            #expect(portion.amount(of: id) == value * 2, "\(id)")
        }
        #expect(meal.reviews[portion.id]?.origin == .details)
        #expect(meal.reviews[portion.id]?.needsConfirmation == false)
    }

    /// Ready when: hidden ingredients can be corrected before logging, and nothing is logged without the review.
    @Test func aFoodThatMayBeHiddenWaitsToBeConfirmed() throws {
        let meal = assemble([item("Black Beans", origin: .hidden)])
        let portion = try #require(meal.portions.first)
        let review = try #require(meal.reviews[portion.id])
        #expect(portion.servings == 0, "Not counted until confirmed.")
        #expect(portion.source == blackBeans.source)
        #expect(review.needsConfirmation)
        #expect(review.suggestedServings == 1)
    }

    @Test func anAmbiguousFoodWaitsForAChoice() throws {
        let meal = assemble([item("Rice", origin: .hidden)])
        let portion = try #require(meal.portions.first)
        let review = try #require(meal.reviews[portion.id])
        #expect(portion.servings == 0)
        #expect(portion.isEstimate)
        #expect(review.choices.map(\.name) == ["Cilantro-Lime White Rice", "Cilantro-Lime Brown Rice"])
        #expect(review.choices.allSatisfy { $0.source != nil })
    }

    @Test func aFoodTheBrandDoesntListIsAnEstimate() throws {
        let meal = assemble([item("Lime Wedge", term: "lime")])
        let portion = try #require(meal.portions.first)
        #expect(portion.isEstimate)
        #expect(portion.source == nil)
        #expect(portion.servings == 1)
        #expect(meal.reviews[portion.id]?.notFound == true)
    }

    /// A saved food named like a published match mustn't replace it, but fills in for one that isn't published.
    @Test func aSavedFoodNeverReplacesAPublishedMatch() throws {
        let saved = [FoodPortion(name: "Chicken", nutrients: ["dietaryEnergyConsumed": 999]),
                     FoodPortion(name: "Lime Wedge", nutrients: ["dietaryEnergyConsumed": 3])]
        let meal = assemble([item("Chicken"), item("Lime Wedge", term: "lime")], known: saved)
        #expect(meal.portions[0].source == chicken.source)
        #expect(meal.portions[0].calories == 180)
        #expect(meal.portions[1].name == "Lime Wedge")
        #expect(meal.portions[1].calories == 3)
        #expect(!meal.portions[1].isEstimate)
    }

    /// Ready when: sources with missing nutrients do not produce fabricated values.
    @Test func aNutrientTheSourceDoesntGiveStaysMissing() throws {
        let meal = assemble([item("Guac")])
        let portion = try #require(meal.portions.first)
        #expect(portion.nutrients["dietarySugar"] == nil)
        #expect(portion.amount(of: "dietarySugar") == 0)
    }

    /// Ready when: offline, no-match, partial-result and rate-limit cases offer a usable fallback.
    @Test(arguments: [LookupError.offline, .timedOut, .rateLimited(retryAfter: 60), .unavailable])
    func aFailedLookupFallsBackToEstimates(error: LookupError) {
        let meal = assemble([item("Chicken", portions: 2), item("Rice", origin: .hidden)], lookup: .failure(error))
        #expect(meal.failure == error)
        #expect(meal.portions.allSatisfy { $0.isEstimate })
        #expect(meal.portions[0].servings == 2)
        #expect(meal.portions[1].servings == 0, "A food that may be hidden still waits to be confirmed.")
        #expect(meal.reviews.values.allSatisfy { !$0.notFound })
        #expect(meal.published.isEmpty)
    }

    /// A food past the request's limit of terms wasn't looked up, so it isn't said to be missing from the brand.
    @Test func aFoodThatWasntLookedUpIsntCalledUnlisted() throws {
        let meal = assemble([item("Lime Wedge", term: "lime")], lookup: .success(LookupResult(foods: ["chicken": []])))
        let portion = try #require(meal.portions.first)
        #expect(portion.isEstimate)
        #expect(meal.reviews[portion.id]?.notFound == false)
    }

    @Test func aPartialResultMatchesWhatItCan() {
        let meal = assemble([item("Chicken"), item("Lime Wedge", term: "lime")],
                            lookup: .success(LookupResult(foods: ["chicken": [chicken]])))
        #expect(meal.portions[0].source != nil)
        #expect(meal.portions[1].isEstimate)
        #expect(meal.failure == nil)
    }

    @Test func noMatchesAtAllKeepTheBrandsPages() {
        let page = NutritionPage(title: "Nutrition", url: URL(string: "https://www.chipotle.com/nutrition-calculator")!)
        let meal = assemble([item("Chicken")], lookup: .success(LookupResult(foods: [:], pages: [page])))
        #expect(meal.pages == [page])
        #expect(meal.published.isEmpty)
        #expect(meal.portions[0].isEstimate)
    }

    @Test func publishedFoodsAreOfferedOnceEachByName() {
        let meal = assemble([item("Rice"), item("White Rice")],
                            lookup: .success(LookupResult(foods: ["rice": [whiteRice, brownRice],
                                                                  "white rice": [whiteRice]])))
        #expect(meal.published.map(\.name) == ["Cilantro-Lime Brown Rice", "Cilantro-Lime White Rice"])
    }

    /// Foods from the same document list it once.
    @Test func sourcesAreListedOnceInOrder() {
        var double = chicken.portion
        double.servings = 2
        var menu = blackBeans
        menu.source.url = URL(string: "https://www.chipotle.com/nutrition-calculator")!
        let sources = BrandedMeal.sources(of: [chicken.portion, blackBeans.portion, menu.portion, double,
                                               estimate("Lime", 2)])
        #expect(sources == [chicken.source, menu.source])
    }
}

// MARK: - Keeping the source

@MainActor
struct NutritionSourceStorageTests {
    private let context = ModelContext(try! ModelContainer(
        for: Food.self, Recipe.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))

    /// Recipes made before 1.1 have no source or estimate keys, and must still load their ingredients.
    @Test func ingredientsSavedBeforeSourcesStillLoad() throws {
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Oats","brand":"","servingSize":"1 cup","nutrients":{"dietaryEnergyConsumed":150},"servings":1}]"#
        let decoded = try JSONDecoder().decode([FoodPortion].self, from: Data(old.utf8))
        #expect(decoded.first?.source == nil)
        #expect(decoded.first?.isEstimate == false)
    }

    @Test func anUnreadableSourceDoesntLoseTheIngredient() throws {
        let odd = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Chicken","brand":"","servingSize":"4 oz","nutrients":{"dietaryEnergyConsumed":180},"servings":2,"source":{"title":5},"isEstimate":"yes"}]"#
        let decoded = try JSONDecoder().decode([FoodPortion].self, from: Data(odd.utf8))
        #expect(decoded.first?.servings == 2)
        #expect(decoded.first?.source == nil)
        #expect(decoded.first?.isEstimate == false)
    }

    /// Ready when: saved meals retain their reviewed values and source/estimate context.
    @Test func aRecipeKeepsEachIngredientsSource() throws {
        var double = chicken.portion
        double.servings = 2
        let lime = estimate("Lime", 2)
        let recipe = Recipe(name: "Bowl", servings: 1, ingredients: [double, lime])
        context.insert(recipe)
        let ingredients = recipe.ingredients
        #expect(ingredients[0].source == chicken.source)
        #expect(ingredients[0].nutrients == chicken.nutrients)
        #expect(ingredients[0].servings == 2)
        #expect(ingredients[1].isEstimate)
        #expect(recipe.portion.calories == 362)
    }

    @Test func replacingAPublishedFoodWithASavedOneDropsTheSource() {
        var double = chicken.portion
        double.servings = 2
        let replaced = double.replaced(by: FoodPortion(name: "My Chicken", nutrients: ["dietaryEnergyConsumed": 150]))
        #expect(replaced.source == nil)
        #expect(!replaced.isEstimate)
        #expect(replaced.servings == 2)
    }

}

// MARK: - The cache

/// Counts requests and answers from a fixed menu, or fails.
private final class FakeProvider: NutritionProvider, @unchecked Sendable {
    var requests: [LookupRequest] = []
    var error: Error?
    var delay: Duration?

    func foods(for request: LookupRequest) async throws -> LookupResult {
        requests.append(request)
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        var found: [String: [PublishedFood]] = [:]
        for term in request.terms where term == "chicken" { found[term] = [chicken] }
        return LookupResult(foods: found)
    }
}

@MainActor
struct NutritionLookupCacheTests {
    private let request = LookupRequest(brand: "Chipotle", terms: ["chicken", "lime"])!
    private let cacheURL = FileManager.default.temporaryDirectory.appending(path: "lookup-\(UUID()).json")

    @Test func foundFoodsAreKeptForADayWithTheirFetchDate() async throws {
        let provider = FakeProvider()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let lookup = NutritionLookup(provider: provider, cacheURL: cacheURL, now: { now })
        let first = try await lookup.foods(for: request)
        #expect(first.foods["chicken"] == [chicken])
        #expect(provider.requests.map(\.terms) == [["chicken", "lime"]])

        now += 60 * 60
        let second = try await lookup.foods(for: request)
        #expect(second.foods["chicken"]?.first?.source.retrieved == retrieved, "The original fetch date.")
        #expect(provider.requests.last?.terms == ["lime"], "Only what wasn't found is asked again.")

        // Read back from the file, as after a relaunch.
        let reopened = NutritionLookup(provider: provider, cacheURL: cacheURL, now: { now })
        _ = try await reopened.foods(for: request)
        #expect(provider.requests.last?.terms == ["lime"])

        now += NutritionLookup.cacheLifetime
        _ = try await reopened.foods(for: request)
        #expect(provider.requests.last?.terms == ["chicken", "lime"], "Kept no longer than a day.")
        try? FileManager.default.removeItem(at: cacheURL)
    }

    @Test func aDifferentBrandIsAskedSeparately() async throws {
        let provider = FakeProvider()
        let lookup = NutritionLookup(provider: provider, cacheURL: nil)
        _ = try await lookup.foods(for: request)
        _ = try await lookup.foods(for: LookupRequest(brand: "chipotle", terms: ["chicken"])!)
        _ = try await lookup.foods(for: LookupRequest(brand: "Qdoba", terms: ["chicken"])!)
        #expect(provider.requests.count == 2, "The same brand in other letters is the same lookup.")
    }

    @Test func failuresBecomeLookupErrors() async {
        let provider = FakeProvider()
        provider.error = URLError(.notConnectedToInternet)
        let lookup = NutritionLookup(provider: provider, cacheURL: nil)
        await #expect(throws: LookupError.offline) { try await lookup.foods(for: request) }
        provider.error = LookupError.rateLimited(retryAfter: 30)
        await #expect(throws: LookupError.rateLimited(retryAfter: 30)) { try await lookup.foods(for: request) }
    }

    /// Ready when: cancellation offers a usable fallback. Cancelling isn't reported as a failure.
    @Test func cancellingStopsTheLookup() async {
        let provider = FakeProvider()
        provider.delay = .seconds(30)
        let lookup = NutritionLookup(provider: provider, cacheURL: nil)
        let task = Task { try await lookup.foods(for: request) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

// MARK: - Reading brands' websites

/// Lines of Chipotle's US nutrition facts PDF as PDFKit reads them, with a kids' table, a second drink size on a
/// line of its own, a value printed as "< 1", and a line the PDF misprints ("10w").
private let chipotleLines = """
    We may update this chart from time to time. For the most up-to-date nutrition information please check Chipotle.com.
    nutrition
    facts
    Portion
    Calories
    Calories From Fat
    Total Fat (g)
    Saturated Fats (g)
    Trans Fat (g)
    Cholesterol (mg)
    Sodium (mg)
    Carbohydrates (g)
    Dietary Fiber (g)
    Sugar (g)
    Protein (g)
    Flour Tortilla (taco) 1 ea 80 25 2.5 0 0 0 160 13 < 1 0 2
    Cilantro-Lime Brown Rice 4 oz 210 50 6 0 0 0 190 36 2 0 4
    Cilantro-Lime White Rice 4 oz 210 35 4 1 0 0 350 40 1 0 4
    Black Beans 4 oz 130 15 1.5 0 0 0 210 22 7 2 8
    Fajita Vegetables 2 oz 20 0 0 0 0 0 150 5 1 2 1
    Chicken 4 oz 180 60 7 3 0 125 310 0 0 0 32
    Tomatillo-Green Chili Salsa 2 fl oz 15 5 0 0 0 0 260 4 0 2 0
    Guacamole (topping/side) 4 oz 230 190 22 3.5 0 0 370 8 6 1 2
    Guacamole (large) 8 oz 460 380 44 7 0 0 740 16 12 2 4
    Tractor Watermelon Limeade 22 fl oz 230 0 0 0 0 0 5 56 0 50 0
    Barq's Root Beer 22 fl oz 280 0 0 0 0 0 130 85 0 85 0
    32 fl oz 430 0 0 0 0 0 180 120 0 120 0
    Chipotle Iced Tea 22 fl oz 10w 0 0 0 0 0 0 3 0 0 0
    kids Menu
    nutrition
    facts
    Portion
    Calories
    Calories From Fat
    Total Fat (g)
    Saturated Fats (g)
    Trans Fat (g)
    Cholesterol (mg)
    Sodium (mg)
    Carbohydrates (g)
    Dietary Fiber (g)
    Sugar (g)
    Protein (g)
    Chicken 2 oz 90 30 3 1.5 0 65 150 0 0 0 15
    """.split(separator: "\n").map(String.init)

@MainActor
struct NutritionTableTests {
    private let foods = NutritionTable.foods(
        in: NutritionDocument(url: pdf, title: "Full Nutrition Facts", lines: chipotleLines), brand: "Chipotle",
        retrieved: retrieved)

    private func food(_ name: String) -> PublishedFood? {
        foods.first { $0.name == name }
    }

    @Test func eachRowIsReadInItsColumnsOrder() throws {
        let chicken = try #require(food("Chicken"))
        #expect(chicken.nutrients == [
            "dietaryEnergyConsumed": 180, "dietaryFatTotal": 7, "dietaryFatSaturated": 3, "dietaryCholesterol": 125,
            "dietarySodium": 310, "dietaryCarbohydrates": 0, "dietaryFiber": 0, "dietarySugar": 0,
            "dietaryProtein": 32,
        ], "Calories from fat and trans fat aren't logged.")
        #expect(chicken.servingBasis == "4 oz")
        #expect(chicken.gramsPerServing == nil, "Ounces aren't taken as a weight.")
        #expect(chicken.brand == "Chipotle")
        #expect(chicken.source.url == pdf)
        #expect(chicken.source.title == "Full Nutrition Facts")
        #expect(chicken.source.provider == "chipotle.com")
        #expect(chicken.source.retrieved == retrieved)
        #expect(food("Black Beans")?.nutrients["dietaryFiber"] == 7)
        #expect(food("Tomatillo-Green Chili Salsa")?.servingBasis == "2 fl oz")
        #expect(food("Guacamole (topping/side)")?.nutrients["dietaryFatTotal"] == 22)
    }

    /// Ready when: sources with missing nutrients do not produce fabricated values.
    @Test func aValueGivenAsLessThanIsUnknown() throws {
        let tortilla = try #require(food("Flour Tortilla (taco)"))
        #expect(tortilla.nutrients["dietaryFiber"] == nil)
        #expect(tortilla.nutrients["dietaryCarbohydrates"] == 13)
        #expect(tortilla.servingBasis == "1 ea")
    }

    @Test func aMisprintedRowIsLeftOut() {
        #expect(food("Chipotle Iced Tea") == nil)
    }

    @Test func aSecondSizeOnItsOwnLineKeepsTheName() {
        let sizes = foods.filter { $0.name == "Barq's Root Beer" }
        #expect(sizes.map(\.servingBasis) == ["22 fl oz", "32 fl oz"])
        #expect(sizes.map { $0.nutrients["dietaryEnergyConsumed"] } == [280, 430])
    }

    @Test func aLaterTableIsNamedByItsTitle() throws {
        let kids = try #require(food("Chicken (Kids Menu)"))
        #expect(kids.servingBasis == "2 oz")
        #expect(kids.nutrients["dietaryEnergyConsumed"] == 90)
    }

    /// The real names match what the photo gives, and the regular serving wins over the kids' one.
    @Test func photoNamesFindTheRightRows() {
        let candidates = { (term: String) in NutritionTable.candidates(for: term, in: foods, brand: "Chipotle") }
        func match(_ term: String) -> NutritionMatch {
            NutritionMatcher.match(name: term, term: term, among: candidates(term), brand: "Chipotle")
        }
        #expect(match("chicken") == .matched(food("Chicken")!))
        #expect(match("black beans") == .matched(food("Black Beans")!))
        #expect(match("white rice") == .matched(food("Cilantro-Lime White Rice")!))
        #expect(match("fajita veggies") == .matched(food("Fajita Vegetables")!))
        #expect(match("rice") == .ambiguous([food("Cilantro-Lime Brown Rice")!, food("Cilantro-Lime White Rice")!]))
        guard case .ambiguous(let guacamole) = match("guac") else { Issue.record("Guacamole not offered"); return }
        #expect(guacamole.prefix(2).map(\.name) == ["Guacamole (topping/side)", "Guacamole (large)"])
        #expect(match("lime") == .none, "Not limeade, and not the lime in cilantro-lime rice.")
    }

    @Test func headerLabels() {
        let columns = NutritionTable.columns(in: "Portion Calories Calories From Fat Total Fat (g) Saturated Fats (g) "
                                             + "Trans Fat (g) Total Carbohydrate (g) Added Sugars (g) Sugars Protein")
        #expect(columns.map(\.column) == [.serving, .nutrient("dietaryEnergyConsumed"), .other,
                                          .nutrient("dietaryFatTotal"), .nutrient("dietaryFatSaturated"), .other,
                                          .nutrient("dietaryCarbohydrates"), .other, .nutrient("dietarySugar"),
                                          .nutrient("dietaryProtein")])
        #expect(columns[3].unit == "g")
        #expect(NutritionTable.columns(in: "Responsibly raised, marinated in our chipotle adobo, then grilled.")
            .isEmpty)
    }

    /// A column in another unit, like sodium in grams, isn't used as milligrams.
    @Test func aColumnInAnotherUnitIsLeftOut() throws {
        let lines = ["Serving", "Calories", "Total Fat (g)", "Sodium (g)", "Protein (g)", "Wrap 1 ea 300 10 1.2 12"]
        let food = try #require(NutritionTable.foods(
            in: NutritionDocument(url: pdf, title: "t", lines: lines), brand: "B", retrieved: retrieved).first)
        #expect(food.nutrients == ["dietaryEnergyConsumed": 300, "dietaryFatTotal": 10, "dietaryProtein": 12])
    }

    /// Five Guys' layout: labels wrapped over lines after a group heading, the serving as a column of grams, and
    /// each food's numbers on the line under its name (from its US nutrition and allergen guide, September 2026).
    @Test func aWrappedHeaderWithServingsInGrams() throws {
        let lines = """
            sodium.
            NUTRITION
            Calories ALLERGENS
            Serving
            Size (g)
            Calories
            From Fat
            Total Fat
            (g)
            Saturated
            Fat (g)
            Trans Fat
            (g)
            Cholesterol
            (mg)
            Sodium
            (mg) Carbs (g) Fiber (g) Sugars (g) Protein (g)
            Milk
            Eggs Wheat
            MEAT
            Bacon (2 pieces) (Supplier S)
            14 70 50 6 2 0 15 210 0 0 0 5
            Hamburger Patty
            65 302 160 17 8 1 60 50 0 0 0 16
            FRIES - COOKED IN 100% PEANUT OIL
            Little Five Guys Style
            227 526 204 23 4 0 0 531 72 8 2 8
            """.split(separator: "\n").map(String.init)
        let foods = NutritionTable.foods(in: NutritionDocument(url: pdf, title: "Guide", lines: lines),
                                         brand: "Five Guys", retrieved: retrieved)
        #expect(foods.map(\.name) == ["Bacon (2 pieces) (Supplier S)", "Hamburger Patty", "Little Five Guys Style"])
        let patty = try #require(foods.first { $0.name == "Hamburger Patty" })
        #expect(patty.servingBasis == "65 g")
        #expect(patty.gramsPerServing == 65, "A serving the source gives in grams can be weighed.")
        #expect(patty.nutrients == [
            "dietaryEnergyConsumed": 302, "dietaryFatTotal": 17, "dietaryFatSaturated": 8, "dietaryCholesterol": 60,
            "dietarySodium": 50, "dietaryCarbohydrates": 0, "dietaryFiber": 0, "dietarySugar": 0,
            "dietaryProtein": 16,
        ])
    }

    /// Panera's layout: servings as words, a note after a serving, "N/A" for caffeine, and a name wrapped above
    /// its numbers (from its nutrition guide of September 2026).
    @Test func servingsAsWordsAndWrappedNames() throws {
        let lines = """
            Serving Size
            Calories (kcal)
            Calories from
            Fat (kcal)
            Fat (g)
            Saturated Fat
            (g)
            Trans Fatty Acid
            (g)
            Cholesterol
            (mg)
            Sodium (mg)
            Carbohydrates
            (g)
            Total Dietary
            Fiber (g)
            Total Sugars (g)
            Protein (g)
            Caffeine (mg)
            Approx.
            Beverages only
            BAGELS & SPREADS
            Asiago Cheese Bagel 1 Bagel 350 80 9 4 0 15 660 55 3 5 14 N/A
            Sesame Bagel 1 Bagel 310 30 3.5 0.5 0 0 600 61 3 8 8 N/A
            Honey Walnut Cream Cheese Spread -
            1.5 oz
            1 Container 130 90 10 6 0 25 160 9 0 8 4 N/A
            BREADS
            Bread Portion - Italian Style Roll 1/2 Roll 230 25 3 0 0 0 440 42 1 1 8 N/A
            Artisan Ciabatta 2 oz (about 2 3/4 inch slice / 57g) 150 10 1.5 0 0 0 260 30 1 1 5 N/A
            """.split(separator: "\n").map(String.init)
        let foods = NutritionTable.foods(in: NutritionDocument(url: pdf, title: "Guide", lines: lines), brand: "Panera",
                                         retrieved: retrieved)
        #expect(foods.map(\.name) == ["Asiago Cheese Bagel", "Sesame Bagel", "Honey Walnut Cream Cheese Spread - 1.5 oz",
                                      "Bread Portion - Italian Style Roll", "Artisan Ciabatta"])
        #expect(foods.map(\.servingBasis) == ["1 Bagel", "1 Bagel", "1 Container", "1/2 Roll",
                                              "2 oz (about 2 3/4 inch slice / 57g)"])
        let bagel = try #require(foods.first)
        #expect(bagel.nutrients == [
            "dietaryEnergyConsumed": 350, "dietaryFatTotal": 9, "dietaryFatSaturated": 4, "dietaryCholesterol": 15,
            "dietarySodium": 660, "dietaryCarbohydrates": 55, "dietaryFiber": 3, "dietarySugar": 5,
            "dietaryProtein": 14,
        ], "Caffeine isn't given.")
        #expect(foods.last?.gramsPerServing == 57, "The weight its serving states.")
        #expect(foods[2].nutrients["dietaryEnergyConsumed"] == 130)
    }

    /// Subway's header abbreviates labels and ends with % Daily Value columns.
    @Test func abbreviatedLabelsAndDailyValues() throws {
        let lines = ["Serving Size (g)", "Calories", "Total Fat (g)", "Sat. Fat (g)", "Trans Fat (g)*", "Chol. (mg)",
                     "Sodium (mg)", "Carbohydrate(g)", "Dietary Fiber (g)", "Sugars (g)", "Added Sugars (g)",
                     "Protein(g)", "Vitamin A % DV", "Vitamin C % DV", "Calcium % DV", "Iron % DV", "SANDWICHES",
                     "6\" Sandwiches", "Deli Classics",
                     "6\" Oven-Roasted Turkey 229 470 22 7 1 55 1120 42 3 5 3 25 20 6 15 25"]
        let turkey = try #require(NutritionTable.foods(in: NutritionDocument(url: pdf, title: "Guide", lines: lines),
                                                       brand: "Subway", retrieved: retrieved).first)
        #expect(turkey.name == "6\" Oven-Roasted Turkey")
        #expect(turkey.servingBasis == "229 g")
        #expect(turkey.nutrients == [
            "dietaryEnergyConsumed": 470, "dietaryFatTotal": 22, "dietaryFatSaturated": 7, "dietaryCholesterol": 55,
            "dietarySodium": 1120, "dietaryCarbohydrates": 42, "dietaryFiber": 3, "dietarySugar": 5,
            "dietaryProtein": 25,
        ])
    }

    @Test func aNameIsJoinedToTheNumbersUnderIt() {
        #expect(NutritionTable.joinedLines(["Mini Patty", "35 163 86 9", "32 fl oz 430 0 0", "Chicken 4 oz 180 60 7"])
                == ["Mini Patty 35 163 86 9", "32 fl oz 430 0 0", "Chicken 4 oz 180 60 7"])
    }

    @Test func textWithoutATableHasNoRows() {
        let menu = ["CHICKEN* 180 cal | 4 oz", "Responsibly raised, marinated in our", "Black Beans 130 cal | 4 oz"]
        #expect(NutritionTable.foods(in: NutritionDocument(url: pdf, title: "t", lines: menu), brand: "Chipotle",
                                     retrieved: retrieved).isEmpty)
    }
}

@MainActor
struct NutritionLinksTests {
    private func link(_ text: String, _ url: String) -> NutritionLinks.Link {
        NutritionLinks.Link(text: text, url: URL(string: url)!)
    }

    /// Chipotle's home page links "Nutrition", and its calculator links the PDF once its scripts have run.
    @Test func nutritionPagesAndPDFsComeFirst() {
        let home = [link("Order Now", "https://www.chipotle.com/order"),
                    link("Careers", "https://jobs.chipotle.com/nutrition-jobs"),
                    link("NUTRITION", "https://www.chipotle.com/nutrition-calculator"),
                    link("Nutrition", "https://www.chipotle.com/nutrition-calculator#top"),
                    link("Nutrition", "https://othersite.com/chipotle-nutrition"),
                    link("Privacy Policy", "https://www.chipotle.com/privacy")]
        let next = NutritionLinks.next(from: home, site: "chipotle.com")
        #expect(next.pages.map(\.url.absoluteString) == ["https://www.chipotle.com/nutrition-calculator"])
        #expect(next.pdfs.isEmpty)

        let calculator = [link("Allergen Statement", "https://www.chipotle.com/allergens"),
                          link("Full Nutrition Facts", pdf.absoluteString),
                          link("Menu (PDF)", "https://www.chipotle.com/menu.pdf")]
        let pdfs = NutritionLinks.next(from: calculator, site: "chipotle.com").pdfs
        #expect(pdfs.map(\.url) == [pdf])
    }

    /// Another country's nutrition isn't this one's: Wendy's links its United Kingdom guide.
    @Test func anotherCountrysNutritionIsLeftOut() {
        let links = [link("Nutrition", "https://www.wendys.com/en-gb/nutrition"),
                     link("UK Nutrition (PDF)", "https://www.wendys.com/sites/default/files/2026-09/United-Kingdom-National-Nutrition-Information---9.10.2026.pdf"),
                     link("Nutrition & Allergens", "https://www.wendys.com/nutrition-allergens"),
                     link("Full Nutrition Facts", pdf.absoluteString)]
        #expect(NutritionLinks.score(links[0], region: "US") == 0)
        #expect(NutritionLinks.score(links[1], region: "US") == 0)
        #expect(NutritionLinks.score(links[1], region: "GB") > 0)
        #expect(NutritionLinks.score(links[2], region: "US") > 0)
        #expect(NutritionLinks.score(links[3], region: "US") > NutritionLinks.score(links[3], region: "CA"),
                "Chipotle's PDF is named US.")
        #expect(NutritionLinks.markets(of: links[3]) == ["US"])
    }

    /// A brand may keep its PDF with a file host, which is read like any linked document.
    @Test func aNutritionPDFElsewhereIsRead() {
        let next = NutritionLinks.next(from: [link("Nutrition Guide", "https://assets.example-cdn.net/files/nutrition.pdf"),
                                              link("Nutrition", "http://www.brand.com/nutrition")],
                                       site: "brand.com")
        #expect(next.pdfs.count == 1)
        #expect(next.pages.isEmpty, "Only the brand's own https pages are opened.")
    }
}

@MainActor
struct WebDomainTests {
    @Test func sitesAreTheirRegistrableDomain() {
        #expect(WebDomain.registrable("www.chipotle.com") == "chipotle.com")
        #expect(WebDomain.registrable("locations.chipotle.com") == "chipotle.com")
        #expect(WebDomain.registrable("www.pret.co.uk") == "pret.co.uk")
        #expect(WebDomain.isSameSite(URL(string: "https://services.chipotle.com/x")!, as: "chipotle.com"))
        #expect(!WebDomain.isSameSite(URL(string: "http://www.chipotle.com/x")!, as: "chipotle.com"))
        #expect(!WebDomain.isSameSite(URL(string: "https://chipotle.com.evil.net/")!, as: "chipotle.com"))
        #expect(WebDomain.site(of: URL(string: "http://locations.chipotle.com/ny/123")!)
                == URL(string: "https://chipotle.com/"))
    }

    /// The model's suggestion is used only when the domain is named like the brand.
    @Test(arguments: [("chipotle.com", "Chipotle", "https://chipotle.com/"),
                      ("https://www.panerabread.com/en-us/home", "Panera Bread", "https://panerabread.com/"),
                      ("benjerry.com", "Ben & Jerry's", "https://benjerry.com/"),
                      ("kindsnacks.com", "KIND", "https://kindsnacks.com/")])
    func aDomainNamedLikeTheBrandIsUsed(answer: String, brand: String, expected: String) {
        #expect(WebDomain.website(answer, for: brand) == URL(string: expected))
    }

    @Test(arguments: [("nutritionix.com", "Chipotle"), ("", "Chipotle"), ("chipotle", "Chipotle"),
                      ("I'm not sure", "Chipotle"), ("javascript:alert(1)", "Chipotle")])
    func anythingElseIsNot(answer: String, brand: String) {
        #expect(WebDomain.website(answer, for: brand) == nil)
    }

    @Test func aSiteMustBeNamedForTheBrand() {
        let site = { (host: String) in URL(string: "https://\(host)/")! }
        #expect(WebDomain.isNamed(site("chipotle.com"), like: "Chipotle"))
        #expect(WebDomain.isNamed(site("kindsnacks.com"), like: "KIND"))
        #expect(WebDomain.isNamed(site("tacobell.com"), like: "Taco Bell"))
        #expect(WebDomain.isNamed(site("five-guys.co.uk"), like: "Five Guys"))
        #expect(!WebDomain.isNamed(site("buffalokind.com"), like: "KIND"))
        #expect(!WebDomain.isNamed(site("nutritionix.com"), like: "Chipotle"))
    }

    @Test func anotherCountrysSiteIsntUsed() {
        let site = { (host: String) in URL(string: "https://\(host)/")! }
        #expect(WebDomain.isForeign(site("cavarestaurant.ca"), region: "US"))
        #expect(!WebDomain.isForeign(site("cavarestaurant.ca"), region: "CA"))
        #expect(!WebDomain.isForeign(site("cava.com"), region: "US"))
        #expect(!WebDomain.isForeign(site("pret.co.uk"), region: "GB"))
        #expect(!WebDomain.isForeign(site("brand.co"), region: "US"))
    }

    @Test func placesAreTheBrandByTheirWords() {
        #expect(WebDomain.sameBrand("Chipotle", "Chipotle Mexican Grill"))
        #expect(WebDomain.sameBrand("mcdonalds", "McDonald’s") == false, "Words must be the same.")
        #expect(WebDomain.sameBrand("McDonald's", "McDonald’s"))
        #expect(!WebDomain.sameBrand("Chipotle", "Qdoba Mexican Eats"))
    }
}

@MainActor
struct ModelRowCheckTests {
    private let document = NutritionDocument(url: pdf, title: "Menu", lines: [])

    private func line(_ text: String) -> ModelRowExtractor.Line {
        ModelRowExtractor.Line(number: 3, text: text, document: document)
    }

    private func check(_ name: String, _ serving: String, _ nutrients: [String: Double],
                       on text: String) -> PublishedFood? {
        ModelRowExtractor.verified(.init(name: name, serving: serving, nutrients: nutrients), line: line(text),
                                   brand: "Chipotle", retrieved: retrieved)
    }

    /// Only values printed on the food's own line are kept; the serving's own numbers don't count.
    @Test func onlyPrintedValuesAreKept() throws {
        let food = try #require(check("Chicken", "4 oz", ["dietaryEnergyConsumed": 180, "dietaryProtein": 32,
                                                          "dietaryFatTotal": 4, "dietarySugar": -1],
                                      on: "CHICKEN* 180 cal | 4 oz"))
        #expect(food.nutrients == ["dietaryEnergyConsumed": 180], "32 isn't printed, 4 is the serving, -1 is none.")
        #expect(food.servingBasis == "4 oz")
        #expect(food.source.provider == "chipotle.com")
    }

    /// Each value must be printed beside its own nutrient's name.
    @Test func valuesMustBeLabeled() throws {
        let line = "Little Harvest 245 g 430 kcal · Total Fat 22g · Saturated Fat 4g · Carbs 46g · Protein 12g"
        let food = try #require(check("Little Harvest", "245 g", [
            "dietaryEnergyConsumed": 430, "dietaryFatTotal": 22, "dietaryFatSaturated": 4,
            "dietaryCarbohydrates": 46, "dietaryProtein": 12, "dietarySugar": 4,
        ], on: line))
        #expect(food.nutrients == ["dietaryEnergyConsumed": 430, "dietaryFatTotal": 22, "dietaryFatSaturated": 4,
                                   "dietaryCarbohydrates": 46, "dietaryProtein": 12],
                "The 4 is saturated fat's, not sugar's.")
        // Saturated fat's number isn't total fat.
        #expect(check("Little Harvest", "245 g", ["dietaryFatTotal": 4], on: line) == nil)
    }

    /// The model's reading of a row of bare numbers can't be checked column by column, so it isn't used: here it
    /// took calories from fat (35) as total fat, as the on-device model did when tried.
    @Test func aRowOfBareNumbersIsntUsed() {
        #expect(check("Cilantro-Lime White Rice", "4 oz", ["dietaryEnergyConsumed": 210, "dietaryFatTotal": 35,
                                                           "dietaryProtein": 4],
                      on: "Cilantro-Lime White Rice 4 oz 210 35 4 1 0 0 350 40 1 0 4") == nil)
    }

    @Test func aValueCannotBelongToTheNextNutrient() throws {
        let text = "Chicken 4 oz Fat 10g Sodium 350mg"
        #expect(check("Chicken", "4 oz", ["dietarySodium": 10], on: text) == nil)
        let food = try #require(check("Chicken", "4 oz", ["dietaryFatTotal": 10, "dietarySodium": 350], on: text))
        #expect(food.nutrients == ["dietaryFatTotal": 10, "dietarySodium": 350])
        let punctuated = try #require(check("Chicken", "4 oz", ["dietaryEnergyConsumed": 180, "dietaryFatTotal": 10,
                                                                "dietarySodium": 350],
                                            on: "Chicken 4 oz Calories 180, Fat 10g, Sodium 350mg."))
        #expect(punctuated.nutrients == ["dietaryEnergyConsumed": 180, "dietaryFatTotal": 10, "dietarySodium": 350])
    }

    @Test func publishedValuesMustUseTheNutrientsUnit() throws {
        #expect(check("Chicken", "4 oz", ["dietarySodium": 0.3], on: "Chicken 4 oz Sodium 0.3 g") == nil)
        #expect(check("Chicken", "4 oz", ["dietaryCholesterol": 0.1], on: "Chicken 4 oz Cholesterol 0.1 g") == nil)
        #expect(check("Chicken", "4 oz", ["dietaryProtein": 10], on: "Chicken 4 oz Protein 10 mg") == nil)
        #expect(check("Chicken", "4 oz", ["dietaryEnergyConsumed": 430], on: "Chicken 4 oz Calories 430 kJ") == nil)
        let food = try #require(check("Chicken", "4 oz", ["dietarySodium": 300], on: "Chicken 4 oz Sodium 300 mg"))
        #expect(food.nutrients["dietarySodium"] == 300)
    }

    @Test func boundsAndNumberFragmentsAreNotExactPublishedValues() {
        for text in ["Sugar < 1 g", "Sugar ≤ 1 g", "Sugar 1–2 g", "Sugar 1 g or less", "Sugar 1/2 g"] {
            #expect(check("Chicken", "4 oz", ["dietarySugar": 1], on: "Chicken 4 oz " + text) == nil)
        }
        #expect(check("Chicken", "4 oz", ["dietarySugar": 2], on: "Chicken 4 oz Sugar 1/2 g") == nil)
        #expect(check("Chicken", "4 oz", ["dietarySugar": 2], on: "Chicken 4 oz 1 / 2 g Sugar") == nil)
        #expect(check("Chicken", "4 oz", ["dietarySugar": 2], on: "Chicken 4 oz 1–2 g Sugar") == nil)
        #expect(check("Chicken", "4 oz", ["dietarySugar": 3], on: "Chicken 4 oz Sugar 0,3 g") == nil)
    }

    @Test func valuesThatDontAddUpAreAMisreading() {
        #expect(ModelRowExtractor.addsUp(["dietaryEnergyConsumed": 210, "dietaryFatTotal": 4,
                                          "dietaryCarbohydrates": 40, "dietaryProtein": 4]))
        #expect(ModelRowExtractor.addsUp(["dietaryEnergyConsumed": 302, "dietaryFatTotal": 17,
                                          "dietaryCarbohydrates": 0, "dietaryProtein": 16]), "Five Guys' patty, as published.")
        #expect(!ModelRowExtractor.addsUp(["dietaryEnergyConsumed": 210, "dietaryFatTotal": 35,
                                           "dietaryCarbohydrates": 40, "dietaryProtein": 4]))
        #expect(ModelRowExtractor.addsUp(["dietaryEnergyConsumed": 210]))
    }

    @Test func aRowNotOnItsLineIsDropped() {
        #expect(check("Steak", "4 oz", ["dietaryEnergyConsumed": 180], on: "CHICKEN* 180 cal | 4 oz") == nil)
        #expect(check("Chicken", "6 oz", ["dietaryEnergyConsumed": 180], on: "CHICKEN* 180 cal | 4 oz") == nil)
        #expect(check("Chicken", "4 oz", ["dietaryEnergyConsumed": 200], on: "CHICKEN* 180 cal | 4 oz") == nil)
    }

    @Test func theExcerptHasOnlyLinesAboutTheFoods() {
        let document = NutritionDocument(url: pdf, title: "Menu", lines: [
            "CHICKEN* 180 cal | 4 oz", "Responsibly raised chicken, grilled.", "STEAK* 150 cal | 4 oz",
            "Fajita Veggies 20 cal | 2 oz"])
        let excerpt = ModelRowExtractor.excerpt(for: ["chicken", "fajita veggies"], in: [document])
        #expect(excerpt.map(\.text) == ["CHICKEN* 180 cal | 4 oz", "Fajita Veggies 20 cal | 2 oz"])
        #expect(excerpt.map(\.number) == [1, 4])
    }
}

/// Stands in for Apple Maps, the website and the model.
@MainActor
private final class FakeWebsite: WebsiteFinding, SiteReading, RowExtracting {
    var site: URL? = URL(string: "https://chipotle.com/")
    var documents = [NutritionDocument(url: pdf, title: "Full Nutrition Facts", lines: chipotleLines)]
    var brandsAsked: [String] = []
    var sitesRead: [URL] = []
    var extractedTerms: [[String]] = []

    func website(for brand: String) async throws -> URL? {
        brandsAsked.append(brand)
        return site
    }

    func documents(from site: URL) async throws -> SiteDocuments {
        sitesRead.append(site)
        return SiteDocuments(documents: documents,
                             nutritionPages: [NutritionPage(title: "Nutrition", url: URL(string: "https://www.chipotle.com/nutrition-calculator")!)])
    }

    func foods(for terms: [String], in documents: [NutritionDocument], brand: String,
               retrieved: Date) async throws -> [String: [PublishedFood]] {
        extractedTerms.append(terms)
        return [:]
    }
}

@MainActor
struct BrandWebsiteLookupTests {
    /// Only the brand goes to find the website; the food names are looked for in what the website gave.
    @Test func onlyTheBrandIsUsedToFindTheSite() async throws {
        let fake = FakeWebsite()
        let lookup = BrandWebsiteLookup(finder: fake, reader: fake, extractor: fake, now: { retrieved })
        let result = try await lookup.foods(for: LookupRequest(brand: "Chipotle", terms: ["chicken", "white rice", "lime"])!)
        #expect(fake.brandsAsked == ["Chipotle"])
        #expect(fake.sitesRead == [URL(string: "https://chipotle.com/")!])
        #expect(result.foods["chicken"]?.first?.name == "Chicken")
        #expect(result.foods["white rice"]?.first?.name == "Cilantro-Lime White Rice")
        #expect(result.foods["lime"] == [])
        #expect(fake.extractedTerms == [["lime"]], "Only what the tables didn't have goes to the model.")
        #expect(result.pages.isEmpty)
    }

    @Test func theWebsiteIsReadOnceADay() async throws {
        let fake = FakeWebsite()
        var now = retrieved
        let lookup = BrandWebsiteLookup(finder: fake, reader: fake, extractor: nil, now: { now })
        _ = try await lookup.foods(for: LookupRequest(brand: "Chipotle", terms: ["chicken"])!)
        _ = try await lookup.foods(for: LookupRequest(brand: "chipotle", terms: ["black beans"])!)
        #expect(fake.sitesRead.count == 1)
        now += BrandWebsiteLookup.catalogLifetime
        _ = try await lookup.foods(for: LookupRequest(brand: "Chipotle", terms: ["chicken"])!)
        #expect(fake.sitesRead.count == 2)
    }

    @Test func nothingFoundLinksTheBrandsPages() async throws {
        let fake = FakeWebsite()
        fake.documents = []
        let lookup = BrandWebsiteLookup(finder: fake, reader: fake, extractor: fake)
        let result = try await lookup.foods(for: LookupRequest(brand: "Chipotle", terms: ["chicken"])!)
        #expect(result.foods["chicken"] == [])
        #expect(result.pages.map(\.title) == ["Nutrition"])
        #expect(fake.extractedTerms.isEmpty, "Nothing to read.")
    }

    @Test func noWebsiteIsNoResult() async throws {
        let fake = FakeWebsite()
        fake.site = nil
        let lookup = BrandWebsiteLookup(finder: fake, reader: fake, extractor: fake)
        let result = try await lookup.foods(for: LookupRequest(brand: "Nowhere Diner", terms: ["pancake"])!)
        #expect(result.foods["pancake"] == [])
        #expect(result.pages.isEmpty)
        #expect(fake.sitesRead.isEmpty)
    }
}

/// Live: reads brands' real websites (needs the internet). Skipped unless run with `TEST_RUNNER_LIVE_LOOKUP=1`;
/// `TEST_RUNNER_LIVE_BRANDS` lists other brands to try, separated by commas.
@MainActor
struct LiveBrandWebsiteTests {
    private var isLive: Bool { ProcessInfo.processInfo.environment["LIVE_LOOKUP"] == "1" }

    @Test func chipotlesPublishedNutritionIsRead() async throws {
        guard isLive else { return }
        let site = try #require(try await WebsiteFinder().website(for: "Chipotle"))
        print("LIVE site:", site)
        let read = try await SiteReader().documents(from: site)
        for document in read.documents {
            print("LIVE document:", document.url, document.title, document.lines.count)
        }
        print("LIVE pages:", read.nutritionPages.map(\.url))
        let foods = read.documents.flatMap { NutritionTable.foods(in: $0, brand: "Chipotle", retrieved: .now) }
        print("LIVE foods:", foods.count)
        let chicken = try #require(foods.first { $0.name == "Chicken" })
        #expect(chicken.nutrients["dietaryEnergyConsumed"] == 180)
        #expect(chicken.nutrients["dietaryProtein"] == 32)
        #expect(chicken.servingBasis == "4 oz")
    }

    @Test func otherBrands() async throws {
        guard isLive, let brands = ProcessInfo.processInfo.environment["LIVE_BRANDS"] else { return }
        for entry in brands.split(separator: ",").map(String.init) {
            let parts = entry.split(separator: ":").map(String.init)
            let brand = parts[0]
            if parts.count > 1 {
                let result: LookupResult?
                do {
                    result = try await BrandWebsiteLookup().foods(for: LookupRequest(brand: brand, terms: [parts[1]])!)
                } catch {
                    print("LIVE \(brand) error:", error, (try? await WebsiteFinder().website(for: brand)) as Any)
                    result = nil
                }
                print("LIVE \(brand) \(parts[1]):", result?.foods.values.joined().prefix(4).map {
                    "\($0.name) \($0.servingBasis) \($0.nutrients["dietaryEnergyConsumed"] ?? -1) kcal from \($0.source.url)"
                } ?? ["failed"], "pages:", result?.pages.map(\.url.absoluteString) ?? [])
                continue
            }
            let site = try? await WebsiteFinder().website(for: brand)
            guard let site else {
                print("LIVE \(brand): no website")
                continue
            }
            let read = try? await SiteReader().documents(from: site)
            let foods = (read?.documents ?? []).flatMap { NutritionTable.foods(in: $0, brand: brand, retrieved: .now) }
            print("LIVE \(brand): \(site) documents \(read?.documents.map { "\($0.url) (\($0.lines.count) lines)" } ?? []) "
                  + "pages \(read?.nutritionPages.map(\.url.absoluteString) ?? []) foods \(foods.count) "
                  + "e.g. \(foods.prefix(3).map { "\($0.name) \($0.servingBasis) \($0.nutrients["dietaryEnergyConsumed"] ?? -1)" })")
        }
    }
}
