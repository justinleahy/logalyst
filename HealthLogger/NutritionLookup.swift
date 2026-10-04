import Foundation

/// A food's nutrition as a restaurant or manufacturer publishes it, found online for a photo of a meal.
struct PublishedFood: Identifiable, Hashable, Codable {
    /// The provider's identifier for the record.
    var id: String
    var name: String
    var brand: String
    /// Amount per serving keyed by metric ID, in each metric's first unit option (kcal, g, mg). Only what the source
    /// publishes: a nutrient it leaves out stays unknown rather than zero.
    var nutrients: [String: Double]
    /// What one serving weighs in grams, only when the source states it.
    var gramsPerServing: Double?
    /// One serving's volume, normalized to milliliters only from an explicit, unambiguous source unit.
    var millilitersPerServing: Double? = nil
    var source: NutritionSource

    /// What the values are for, such as "4 oz".
    nonisolated var servingBasis: String { source.servingBasis }

    /// One serving, ready to log, with its source kept alongside.
    var portion: FoodPortion {
        FoodPortion(name: name, brand: brand, servingSize: servingBasis, nutrients: nutrients,
                    gramsPerServing: gramsPerServing, millilitersPerServing: millilitersPerServing,
                    source: source)
    }

    /// The label nutrients the source doesn't give, which totals leave out.
    var unpublished: [Metric] {
        FoodNutrient.metrics.filter { $0.id != "dietaryCaffeine" && nutrients[$0.id] == nil }
    }
}

/// What a lookup found: published foods for each term, and links to the brand's own nutrition pages when no
/// foods were found at all, for the user to check themselves.
struct LookupResult: Hashable {
    var foods: [String: [PublishedFood]]
    var pages: [NutritionPage] = []
}

/// A brand's own page about its nutrition. Only linked: nothing is read from it.
struct NutritionPage: Hashable, Codable {
    var title: String
    var url: URL
}

/// What to look up in a restaurant's or brand's published nutrition: the brand and a few short food names. Only
/// the brand leaves the iPhone (to Apple Maps, to find its website); the food names are looked for in what's read
/// from the website, on the iPhone.
struct LookupRequest: Hashable {
    static let maxTerms = 12
    static let maxTermLength = 40
    static let maxBrandLength = 60

    let brand: String
    /// Short food names, such as "white rice", cleaned and without repeats.
    let terms: [String]

    /// Nil when there's no brand or nothing to look up.
    init?(brand: String, terms: [String]) {
        let brand = Self.clean(brand, maxLength: Self.maxBrandLength)
        var seen: Set<String> = []
        let terms = terms.map { Self.clean($0, maxLength: Self.maxTermLength).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(Self.maxTerms)
        guard !brand.isEmpty, !terms.isEmpty else { return nil }
        self.brand = brand
        self.terms = Array(terms)
    }

    /// The key a term's results are kept under, matching how `terms` were cleaned.
    static func key(for term: String) -> String {
        clean(term, maxLength: maxTermLength).lowercased()
    }

    /// Letters, digits and a little punctuation that appears in food and brand names ("Ben & Jerry's",
    /// "Pico de Gallo", "7-Eleven"), on one line, cut at a word to fit.
    static func clean(_ text: String, maxLength: Int) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " '&-.’"))
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.map { allowed.contains($0) ? $0 : " " }))
        var words = kept.split(whereSeparator: \.isWhitespace).map(String.init)
        while words.joined(separator: " ").count > maxLength, words.count > 1 { words.removeLast() }
        return String(words.joined(separator: " ").prefix(maxLength))
    }
}

/// Why a lookup didn't give results, with what to do about it.
enum LookupError: LocalizedError, Hashable {
    case offline
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    /// The website answered with an error or something unreadable.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Connect to the internet and try again."
        case .timedOut: "The lookup took too long. Try again in a moment."
        case .rateLimited(let wait?) where wait >= 60:
            "The website is busy. Try again in about \(Int((wait / 60).rounded(.up))) minutes."
        case .rateLimited: "The website is busy. Try again in a minute."
        case .unavailable: "The brand's website couldn't be read right now. Try again later."
        }
    }

    /// From a network error, or nil for cancellation, which isn't a failure to report.
    init?(_ error: Error) {
        if error is CancellationError { return nil }
        if let lookup = error as? LookupError {
            self = lookup
            return
        }
        guard let url = error as? URLError else {
            self = .unavailable
            return
        }
        switch url.code {
        case .cancelled: return nil
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            self = .offline
        case .timedOut: self = .timedOut
        default: self = .unavailable
        }
    }
}

/// Somewhere published nutrition can be looked up.
protocol NutritionProvider: Sendable {
    /// Published foods for each of the request's terms, keyed by the term. A term with nothing found is missing
    /// or empty.
    func foods(for request: LookupRequest) async throws -> LookupResult
}

/// Looks up published nutrition through a provider, keeping results on the iPhone for a day so the same meal
/// doesn't read the website again. Cached results keep the date they were fetched.
@MainActor
final class NutritionLookup {
    /// How long a result is reused. Published restaurant nutrition rarely changes faster than this.
    static let cacheLifetime: TimeInterval = 24 * 60 * 60
    /// Longest a lookup may take before it's given up on: finding the website, opening a few of its pages, reading
    /// a PDF and, for text that isn't a table, the on-device model. The user can stop sooner.
    static let timeout: Duration = .seconds(75)

    private let provider: NutritionProvider
    private let cacheURL: URL?
    private var cache: [String: CachedFoods]
    private let now: () -> Date

    private struct CachedFoods: Codable {
        let stored: Date
        let foods: [PublishedFood]
    }

    /// The lookup the app uses: brands' own websites, or in Debug builds, test data when asked for.
    static let shared: NutritionLookup = {
        #if DEBUG
        // Test data isn't cached, so each run gets the answer its launch arguments ask for.
        if let stub = StubNutritionProvider.fromLaunchArguments { return NutritionLookup(provider: stub, cacheURL: nil) }
        #endif
        return NutritionLookup(provider: BrandWebsiteLookup())
    }()

    init(provider: NutritionProvider, cacheURL: URL? = NutritionLookup.defaultCacheURL, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.cacheURL = cacheURL
        self.now = now
        cache = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: CachedFoods].self, from: $0) } ?? [:]
    }

    /// In Caches, so it's never backed up or synced, and the system can clear it.
    static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "NutritionLookup.json")
    }

    /// Published foods for each term, from the cache where they're fresh and otherwise from one request for the
    /// rest. Throws `LookupError`, or `CancellationError` if the task is cancelled.
    func foods(for request: LookupRequest) async throws -> LookupResult {
        prune()
        var found: [String: [PublishedFood]] = [:]
        var missing: [String] = []
        for term in request.terms {
            if let cached = cache[cacheKey(request, term)] {
                found[term] = cached.foods
            } else {
                missing.append(term)
            }
        }
        guard !missing.isEmpty,
              let remaining = LookupRequest(brand: request.brand, terms: missing) else {
            return LookupResult(foods: found)
        }
        let fetched: LookupResult
        do {
            fetched = try await withTimeout(Self.timeout) { [provider] in try await provider.foods(for: remaining) }
        } catch {
            try Task.checkCancellation()
            guard let lookupError = LookupError(error) else { throw CancellationError() }
            throw lookupError
        }
        let stored = now()
        for term in remaining.terms {
            let foods = fetched.foods[term] ?? []
            found[term] = foods
            // Only results are kept; a term nothing was found for is asked again next time.
            if !foods.isEmpty { cache[cacheKey(request, term)] = CachedFoods(stored: stored, foods: foods) }
        }
        save()
        // Pages are only for when nothing at all was found.
        return LookupResult(foods: found, pages: found.values.allSatisfy(\.isEmpty) ? fetched.pages : [])
    }

    private func cacheKey(_ request: LookupRequest, _ term: String) -> String {
        [request.brand.lowercased(), term].joined(separator: "\u{1F}")
    }

    private func prune() {
        let oldest = now().addingTimeInterval(-Self.cacheLifetime)
        cache = cache.filter { $0.value.stored > oldest }
    }

    private func save() {
        guard let cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Runs `work`, throwing `LookupError.timedOut` if it takes longer than `limit`.
private func withTimeout<T: Sendable>(_ limit: Duration,
                                      _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw LookupError.timedOut
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

// MARK: - Matching

/// How a food from a photo matches a brand's published foods.
enum NutritionMatch: Hashable {
    /// One clear match.
    case matched(PublishedFood)
    /// Several that fit about as well, or one that fits only in part, best first: the user picks.
    case ambiguous([PublishedFood])
    case none
}

/// Matches names from a photo to the names a brand publishes, by their words. "Rice" fits White Rice and Brown
/// Rice equally, so the user is asked; "White Rice" fits one. Never guesses between foods that fit equally.
nonisolated enum NutritionMatcher {
    /// A score from 0 to 1 at least this high, and clearly ahead of the next, is a match.
    static let matchScore = 0.66
    /// Ahead of the next by at least this much.
    static let margin = 0.2
    /// Below this a food isn't offered at all.
    static let candidateScore = 0.4
    static let maxChoices = 5

    static func match(name: String, term: String, among foods: [PublishedFood], brand: String) -> NutritionMatch {
        let brandWords = Set(words(brand))
        let queries = [words(name), words(term)].map { $0.filter { !brandWords.contains($0) } }.filter { !$0.isEmpty }
        struct Scored {
            let food: PublishedFood
            let score: Double
            let order: Int
        }
        var seen: Set<String> = []
        var scored: [Scored] = []
        for food in foods where seen.insert(duplicateKey(food)).inserted {
            let candidate = words(food.name).filter { !brandWords.contains($0) }
            let best = queries.map { score($0, candidate) }.max() ?? 0
            if best >= candidateScore { scored.append(Scored(food: food, score: best, order: scored.count)) }
        }
        // Best first, keeping the provider's order between equals.
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
        guard let best = scored.first else { return .none }
        let next = scored.dropFirst().first?.score ?? 0
        if best.score >= matchScore, best.score - next >= margin { return .matched(best.food) }
        return .ambiguous(scored.prefix(maxChoices).map(\.food))
    }

    /// The same food listed twice, as providers sometimes do.
    private static func duplicateKey(_ food: PublishedFood) -> String {
        words(food.name).joined(separator: " ") + "|" + food.servingBasis.lowercased() + "|"
            + food.nutrients.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// How well two names' words agree: 1 for the same words, less for words missing from either side. Words must
    /// be the same (after `words(_:)`), so "lime" isn't "limeade". A name's last word is usually what the food is
    /// ("rice" in "Cilantro-Lime White Rice"), so it counts double: "rice" fits that name and "lime" doesn't.
    static func score(_ query: [String], _ candidate: [String]) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else { return 0 }
        /// The share of a name's weight found in the other name.
        func found(_ words: [String], in other: [String]) -> Double {
            let weights = words.indices.map { $0 == words.count - 1 ? 2.0 : 1.0 }
            let matched = zip(words, weights).filter { word, _ in other.contains(word) }
            return matched.map(\.1).reduce(0, +) / weights.reduce(0, +)
        }
        let recall = found(query, in: candidate)
        let precision = found(candidate, in: query)
        guard recall > 0, precision > 0 else { return 0 }
        return 2 * precision * recall / (precision + recall)
    }

    /// Lowercased words without accents, punctuation, filler words or plural endings, with common short names
    /// spelled out ("veggies" is "vegetable").
    static func words(_ text: String) -> [String] {
        let filler: Set = ["a", "an", "the", "of", "with", "and", "or", "in", "on", "side", "serving", "portion"]
        let spelledOut = ["veggy": "vegetable", "veggie": "vegetable", "guac": "guacamole"]
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { singular(String($0)) }
            .map { spelledOut[$0] ?? $0 }
            .filter { !filler.contains($0) }
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }
}
