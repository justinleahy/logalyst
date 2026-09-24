import AppIntents
import HealthKit

// Compiled into the apps (for Siri and Shortcuts) and the widget extensions (for widget and control buttons).

/// Saves water to Health from Siri, Shortcuts, a widget button or Control Center.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Saves water to the Health app. Leave the amount empty to log a glass.")
    /// Health data can't be written while the phone is locked, and a locked phone shouldn't log on your behalf.
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Amount")
    var amount: Double?

    /// The unit label the amount is in (e.g. "mL"). The user's water unit is used when missing.
    @Parameter(title: "Unit", optionsProvider: WaterUnitOptions())
    var unit: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) \(\.$unit) of water")
    }

    init() {}

    init(amount: Double, option: UnitOption) {
        self.amount = amount
        unit = option.label
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let water = Metric.water
        let health = await HealthStore.standalone()
        let option = try health.unitOption(for: water, labeled: unit)
        let value = amount ?? option.presets.first ?? option.defaultValue
        return .result(dialog: try await health.log(water, value: value, option: option))
    }
}

struct WaterUnitOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        Metric.water.unitOptions.map(\.label)
    }
}

/// Saves a common size of water. Siri phrases can't hold an arbitrary number, but they can hold one of these,
/// so "Log 16 ounces of water in Vitals Log" works in one sentence.
struct LogWaterServingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water Serving"
    static let description = IntentDescription("Saves a common serving of water, like 16 fl oz or 500 mL, to the Health app.")
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Serving", requestValueDialog: "How much water?")
    var serving: WaterServing

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$serving) of water")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let water = Metric.water
        let health = await HealthStore.standalone()
        let option = try health.unitOption(for: water, labeled: serving.unitLabel)
        return .result(dialog: try await health.log(water, value: serving.amount, option: option))
    }
}

enum WaterServing: String, AppEnum {
    case oz8, oz12, oz16, oz20, oz24, oz32, ml250, ml330, ml500, ml750, ml1000

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Water Serving"
    // Synonyms cover how people say amounts out loud; Siri matches them as well as the title.
    static let caseDisplayRepresentations: [WaterServing: DisplayRepresentation] = [
        .oz8: DisplayRepresentation(title: "8 fl oz", synonyms: ["8 ounces", "eight ounces", "a cup", "one cup"]),
        .oz12: DisplayRepresentation(title: "12 fl oz", synonyms: ["12 ounces", "twelve ounces", "a can"]),
        .oz16: DisplayRepresentation(title: "16 fl oz", synonyms: ["16 ounces", "sixteen ounces", "two cups", "a pint"]),
        .oz20: DisplayRepresentation(title: "20 fl oz", synonyms: ["20 ounces", "twenty ounces"]),
        .oz24: DisplayRepresentation(title: "24 fl oz", synonyms: ["24 ounces", "twenty four ounces", "three cups"]),
        .oz32: DisplayRepresentation(title: "32 fl oz", synonyms: ["32 ounces", "thirty two ounces", "four cups", "a quart"]),
        .ml250: DisplayRepresentation(title: "250 mL", synonyms: ["250 milliliters", "two hundred fifty milliliters"]),
        .ml330: DisplayRepresentation(title: "330 mL", synonyms: ["330 milliliters", "three hundred thirty milliliters"]),
        .ml500: DisplayRepresentation(title: "500 mL", synonyms: ["500 milliliters", "five hundred milliliters", "half a liter"]),
        .ml750: DisplayRepresentation(title: "750 mL", synonyms: ["750 milliliters", "seven hundred fifty milliliters"]),
        .ml1000: DisplayRepresentation(title: "1 L", synonyms: ["1 liter", "one liter", "a liter", "1000 milliliters"]),
    ]

    var amount: Double {
        switch self {
        case .oz8: 8
        case .oz12: 12
        case .oz16: 16
        case .oz20: 20
        case .oz24: 24
        case .oz32: 32
        case .ml250: 250
        case .ml330: 330
        case .ml500: 500
        case .ml750: 750
        case .ml1000: 1000
        }
    }

    var unitLabel: String {
        switch self {
        case .oz8, .oz12, .oz16, .oz20, .oz24, .oz32: "fl oz"
        case .ml250, .ml330, .ml500, .ml750, .ml1000: "mL"
        }
    }
}

/// Saves a value for any metric logged as a number, like weight, blood glucose or caffeine.
struct LogMetricIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Metric"
    static let description = IntentDescription(
        "Saves a value, like your weight, blood glucose or caffeine, to the Health app. Water has its own action.")
    static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

    @Parameter(title: "Metric", requestValueDialog: "What would you like to log?")
    var metric: QuantityMetricEntity

    /// Optional so Siri can ask for it in the metric's unit once it knows the metric.
    @Parameter(title: "Value")
    var value: Double?

    /// The unit label the value is in (e.g. "lb"). The user's unit for the metric is used when missing.
    @Parameter(title: "Unit", optionsProvider: MetricUnitOptions())
    var unit: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$metric) \(\.$value) \(\.$unit)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let metric = Metric.metric(id: metric.id) else {
            throw IntentMessage("That metric isn't available.")
        }
        let health = await HealthStore.standalone()
        let option = try health.unitOption(for: metric, labeled: unit)
        guard let value else {
            throw $value.needsValueError(metric.valuePrompt(in: option))
        }
        return .result(dialog: try await health.log(metric, value: value, option: option))
    }
}

/// The chosen metric's units, so Shortcuts offers "kg" and "lb" for weight rather than a text field.
struct MetricUnitOptions: DynamicOptionsProvider {
    @IntentParameterDependency<LogMetricIntent>(\.$metric)
    var intent

    @MainActor
    func results() async throws -> [String] {
        guard let id = intent?.metric.id, let metric = Metric.metric(id: id) else { return [] }
        return metric.unitOptions.map(\.label)
    }
}

// MARK: - Helpers

/// An error whose message Siri and Shortcuts show as is.
struct IntentMessage: Error, CustomLocalizedStringResourceConvertible {
    let localizedStringResource: LocalizedStringResource

    init(_ message: LocalizedStringResource) {
        localizedStringResource = message
    }
}

extension Metric {
    /// What Siri asks when the value is missing, e.g. "What's your weight, in lb?"
    func valuePrompt(in option: UnitOption) -> IntentDialog {
        if option.unit == .count() { return "How many \(option.label)?" }
        if category == .intake { return "How much \(name.lowercased()), in \(option.label)?" }
        return "What's your \(name.lowercased()), in \(option.label)?"
    }
}

extension HealthStore {
    /// The metric's unit with this label, or the user's unit when there's no label.
    func unitOption(for metric: Metric, labeled label: String?) throws -> UnitOption {
        if let label {
            guard let option = metric.unitOptions.first(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame })
            else {
                let labels = metric.unitOptions.map(\.label).formatted(.list(type: .or))
                throw IntentMessage("\(metric.name) can be logged in \(labels), not \(label).")
            }
            return option
        }
        guard let option = unitOption(for: metric) else {
            throw IntentMessage("\(metric.name) can't be logged with a value.")
        }
        return option
    }

    /// Saves a value after checking it's in range, and says what was saved, with today's total for intake.
    func log(_ metric: Metric, value: Double, option: UnitOption) async throws -> IntentDialog {
        guard option.range.contains(value) else {
            let low = option.format(option.range.lowerBound), high = option.format(option.range.upperBound)
            throw IntentMessage("\(metric.name) must be between \(low) and \(high).")
        }
        try await saveQuantity(metric, value: value, option: option, date: .now)
        let logged = "Logged \(option.format(value)) for \(metric.name)."
        guard metric.category == .intake,
              let total = try? await dailyTotals(for: metric, days: 1).last?.value(in: option) else {
            return "\(logged)"
        }
        return "\(logged) Today's total is \(option.format(total))."
    }
}
