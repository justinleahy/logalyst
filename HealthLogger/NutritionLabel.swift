import Foundation
import CoreGraphics
import Vision

/// Nutrition read from a photo of a nutrition facts label, in each metric's first unit (kcal, g, mg).
struct NutritionLabel {
    /// A line of text Vision found, with its bounds in normalized image coordinates (origin at the bottom left).
    struct TextLine {
        let text: String
        let box: CGRect
        /// Rise over run of the text's baseline, nonzero when the photo is tilted.
        var slope: Double = 0
    }

    var nutrients: [String: Double] = [:]
    /// As printed, e.g. "2/3 cup (55g)". Empty if the label doesn't say.
    var servingSize = ""

    /// Reads the text in a photo of a label. Nil if it doesn't look like one.
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation) async throws -> NutritionLabel? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction "fixes" amounts like 0g into words, so read the characters as they are.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: image, orientation: orientation)
        let lines = observations.compactMap { observation -> TextLine? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let (left, right) = (observation.bottomLeft, observation.bottomRight)
            let run = right.x - left.x
            return TextLine(text: text, box: observation.boundingBox.cgRect,
                            slope: run > 0 ? (right.y - left.y) / run : 0)
        }
        return NutritionLabel(lines: lines)
    }

    /// Parses recognized text. Nil unless at least two nutrients were found, since anything less is
    /// more likely a stray word than a label.
    init?(lines: [TextLine]) {
        let rows = Self.rows(from: lines)
        var salt: Double?
        for row in rows {
            if servingSize.isEmpty, let serving = Self.servingSize(in: row) {
                servingSize = serving
                continue
            }
            // Labels list each nutrient once, and the first mention is the amount; later ones are footnotes
            // like "2,000 calories a day" or the old "Total Fat Less than 65g" table.
            guard let rule = Self.rules.first(where: { $0.matches(row) }), rule.id != Self.transFatID else { continue }
            if rule.id == Self.saltID {
                if salt == nil { salt = rule.amount(in: row) }
            } else if nutrients[rule.id] == nil, let amount = rule.amount(in: row) {
                nutrients[rule.id] = amount
            }
        }
        // European labels give salt instead of sodium; salt is 40% sodium by weight.
        if nutrients["dietarySodium"] == nil, let salt {
            nutrients["dietarySodium"] = (salt * 400).rounded()
        }
        if servingSize.isEmpty, let per100 = rows.lazy.compactMap(Self.per100).first {
            servingSize = per100
        }
        guard nutrients.count >= 2 else { return nil }
    }

    // MARK: Rows

    /// Joins lines that sit side by side (Vision often splits a name from its amount), top to bottom,
    /// lowercased, with common misreads fixed.
    private static func rows(from lines: [TextLine]) -> [String] {
        // Undo a tilted photo, so an amount at the far right still lines up with its name. The typical
        // slope of the longer lines is the tilt; short ones like "230" are too narrow to measure.
        let slopes = lines.filter { $0.box.width > 0.2 }.map(\.slope).sorted()
        let tilt = slopes.isEmpty ? 0 : slopes[slopes.count / 2]
        let level = lines.map { line in
            TextLine(text: line.text, box: line.box.offsetBy(dx: 0, dy: -tilt * line.box.midX))
        }
        var rows: [[TextLine]] = []
        for line in level.sorted(by: { $0.box.maxY > $1.box.maxY }) {
            if let index = rows.firstIndex(where: { $0.contains { sameRow($0.box, line.box) } }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            clean(row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " "))
        }
    }

    /// Whether two boxes overlap vertically by at least half the shorter one, so a tall "230" next to
    /// "Calories" still counts as one row.
    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    private static func clean(_ text: String) -> String {
        var text = text.lowercased()
        // Letter O read in place of zero, as in "Og" or "1O mg" (but not "8oz").
        text = text.replacing(#/(\d)o(?!z)/#) { "\($0.output.1)0" }
        text = text.replacing(#/\bo(\s?m?g\b)/#) { "0\($0.output.1)" }
        // Fraction slash read as a bar, as in "2|3 cup".
        text = text.replacing(#/(\d)\s?\|\s?(\d)/#) { "\($0.output.1)/\($0.output.2)" }
        // Thousands separators, as in "2,000", and decimal commas, as in "3,5 g".
        text = text.replacing(#/(\d),(\d{3})(?!\d)/#) { "\($0.output.1)\($0.output.2)" }
        text = text.replacing(#/(\d),(\d{1,2})(?!\d)/#) { "\($0.output.1).\($0.output.2)" }
        return text
    }

    // MARK: Serving size

    private static func servingSize(in row: String) -> String? {
        if let match = row.firstMatch(of: #/serving size\s*:?\s*(.+)/#) {
            return tidy(String(match.output.1))
        }
        // Canadian labels: "Per 1 cup (250 mL)".
        if let match = row.firstMatch(of: #/^per\s+(\d.*)/#), !row.contains(#/^per\s+100\s*(g|ml)\b/#) {
            return tidy(String(match.output.1))
        }
        return nil
    }

    /// "100 g" for a label that only gives amounts per 100 g (or mL).
    private static func per100(_ row: String) -> String? {
        guard let match = row.firstMatch(of: #/per\s+100\s*(g|ml)\b/#) else { return nil }
        return match.output.1 == "g" ? "100 g" : "100 mL"
    }

    /// Trims stray punctuation and puts back the capital in "mL", which `clean` lowercased.
    private static func tidy(_ serving: String) -> String {
        serving.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters.subtracting(["(", ")"])))
            .replacing(#/(\d)\s?ml\b/#) { "\($0.output.1) mL" }
    }

    // MARK: Nutrients

    private static let saltID = "salt"
    /// Matched only so its row isn't taken for total fat; Health has no trans fat type.
    private static let transFatID = "transFat"

    private enum Unit { case kilocalories, grams, milligrams }

    private struct Rule {
        let id: String
        let names: Regex<Substring>
        var excluding: Regex<Substring>?
        let unit: Unit

        func matches(_ row: String) -> Bool {
            guard row.contains(names) else { return false }
            if let excluding, row.contains(excluding) { return false }
            return true
        }

        /// The first amount after the nutrient's name, converted to this rule's unit. Percent daily values
        /// are skipped (but not an amount before the "% Daily Value" heading), and "<1g" counts as half.
        func amount(in row: String) -> Double? {
            guard let name = row.firstRange(of: names) else { return nil }
            let rest = row[name.upperBound...]
            let amounts = rest.matches(of: #/(<\s*|less than\s+)?(\d+(?:\.\d+)?)\s*(kcal|kj|cal|mg|mcg|µg|g)?(?!\d)(\s*%(?!\s*[a-z]))?/#)
                .filter { $0.output.4 == nil }
                .compactMap { match -> (value: Double, unit: Substring?)? in
                    guard var value = Double(match.output.2) else { return nil }
                    if match.output.1 != nil { value /= 2 }
                    return (value, match.output.3)
                }
            if unit == .kilocalories {
                // "Energy 1046 kJ / 250 kcal": prefer kilocalories, then convert kilojoules.
                if let kcal = amounts.first(where: { $0.unit == "kcal" || $0.unit == "cal" }) { return kcal.value }
                if let kj = amounts.first(where: { $0.unit == "kj" }) { return (kj.value / 4.184).rounded() }
                return amounts.first(where: { $0.unit == nil })?.value
            }
            guard let amount = amounts.first(where: { $0.unit != "kcal" && $0.unit != "kj" && $0.unit != "cal" })
            else { return nil }
            let grams: Double = switch amount.unit {
            case "mg": amount.value / 1000
            case "mcg", "µg": amount.value / 1_000_000
            case "g": amount.value
            // No unit printed (or it wasn't read): assume the one labels use for this nutrient.
            default: unit == .milligrams ? amount.value / 1000 : amount.value
            }
            let value = unit == .milligrams ? grams * 1000 : grams
            return (value * 10).rounded() / 10
        }
    }

    /// Checked in order, so the more specific names (saturated fat) come before the general ones (fat).
    private static let rules: [Rule] = [
        Rule(id: "dietaryEnergyConsumed", names: #/\bcalories\b|\bcalorie\b|\benergy\b|\bénergie\b/#,
             excluding: #/from fat|a day|per day|\bdiet\b/#, unit: .kilocalories),
        Rule(id: "dietaryFatSaturated", names: #/saturated|saturates|\bsat\.?\s+fat|saturés/#, unit: .grams),
        Rule(id: transFatID, names: #/\btrans\b/#, unit: .grams),
        Rule(id: "dietaryFatTotal", names: #/\bfat\b|\blipides\b/#,
             excluding: #/poly|mono|from fat/#, unit: .grams),
        Rule(id: "dietaryCholesterol", names: #/cholest/#, unit: .milligrams),
        Rule(id: "dietarySodium", names: #/sodium/#, unit: .milligrams),
        Rule(id: saltID, names: #/\bsalt\b|\bsel\b/#, unit: .grams),
        Rule(id: "dietaryFiber", names: #/fiber|fibre/#, unit: .grams),
        Rule(id: "dietarySugar", names: #/\bsugars?\b|\bsucres\b/#,
             excluding: #/added|\bincl|alcohol|ajoutés/#, unit: .grams),
        Rule(id: "dietaryCarbohydrates", names: #/carbohydrate|\bcarbs?\b|glucides/#, unit: .grams),
        Rule(id: "dietaryProtein", names: #/protein|protéines/#, unit: .grams),
        Rule(id: "dietaryCaffeine", names: #/caffeine/#, unit: .milligrams),
    ]
}
