import HealthKit

/// Top-level grouping shown in the log screens.
enum MetricCategory: String, CaseIterable, Identifiable {
    case vitals, body, intake, symptoms

    var id: Self { self }

    var title: String {
        switch self {
        case .vitals: "Vitals"
        case .body: "Body Measurements"
        case .intake: "Intake"
        case .symptoms: "Symptoms & Events"
        }
    }

    var systemImage: String {
        switch self {
        case .vitals: "waveform.path.ecg"
        case .body: "figure"
        case .intake: "fork.knife"
        case .symptoms: "bandage"
        }
    }
}

/// One way of entering a quantity (e.g. kg vs lb). Ranges, steps and presets are in display units.
struct UnitOption: Hashable {
    enum System { case metric, us, both }

    let unit: HKUnit
    let label: String
    let system: System
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    var fractionDigits = 0
    /// Multiplier from the HealthKit value to the displayed value (percent types are stored as 0–1).
    var scale: Double = 1
    var presets: [Double] = []
    /// Label to use when the value is exactly 1 (e.g. "drink" vs "drinks").
    var singularLabel: String?

    func displayValue(from quantity: HKQuantity) -> Double {
        quantity.doubleValue(for: unit) * scale
    }

    func quantity(fromDisplay value: Double) -> HKQuantity {
        HKQuantity(unit: unit, doubleValue: value / scale)
    }

    func format(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
        if label == "%" { return "\(number)%" }
        return "\(number) \(value == 1 ? singularLabel ?? label : label)"
    }
}

enum MetricKind: Hashable {
    case quantity(HKQuantityTypeIdentifier, [UnitOption])
    case bloodPressure
    case symptom(HKCategoryTypeIdentifier)
}

struct Metric: Identifiable, Hashable {
    let id: String
    let name: String
    let category: MetricCategory
    let systemImage: String
    let kind: MetricKind
    /// Whether the metric is offered on Apple Watch (long-tail items stay phone-only).
    var onWatch = true

    static func == (lhs: Metric, rhs: Metric) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var unitOptions: [UnitOption] {
        if case .quantity(_, let options) = kind { options } else { [] }
    }

    /// The HealthKit types this metric writes.
    var sampleTypes: [HKSampleType] {
        switch kind {
        case .quantity(let id, _): [HKQuantityType(id)]
        case .bloodPressure: [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
        case .symptom(let id): [HKCategoryType(id)]
        }
    }

    /// The type used to read this metric back as a single entry.
    var historyType: HKSampleType {
        switch kind {
        case .quantity(let id, _): HKQuantityType(id)
        case .bloodPressure: HKCorrelationType(.bloodPressure)
        case .symptom(let id): HKCategoryType(id)
        }
    }
}

// MARK: - Blood pressure

enum BloodPressure {
    static let unit = HKUnit.millimeterOfMercury()
    static let systolicRange = 60.0...250.0
    static let diastolicRange = 30.0...150.0
    static let defaultSystolic = 120.0
    static let defaultDiastolic = 80.0
}

// MARK: - Symptom severity

enum Severity: Int, CaseIterable, Identifiable {
    case mild, moderate, severe, present, notPresent

    var id: Self { self }

    var title: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        case .present: "Present"
        case .notPresent: "Not Present"
        }
    }

    var healthKitValue: HKCategoryValueSeverity {
        switch self {
        case .mild: .mild
        case .moderate: .moderate
        case .severe: .severe
        case .present: .unspecified
        case .notPresent: .notPresent
        }
    }

    init?(healthKitValue raw: Int) {
        guard let value = HKCategoryValueSeverity(rawValue: raw),
              let match = Severity.allCases.first(where: { $0.healthKitValue == value }) else { return nil }
        self = match
    }
}

// MARK: - Catalog

extension Metric {
    static let all: [Metric] = vitals + body + intake + symptoms

    static func metric(for type: HKSampleType) -> Metric? {
        all.first { $0.historyType == type }
    }

    static func metrics(in category: MetricCategory, watchOnly: Bool = false) -> [Metric] {
        all.filter { $0.category == category && (!watchOnly || $0.onWatch) }
    }

    /// Metrics with one-tap preset amounts, shown in the Quick Add section.
    static var quickAdd: [Metric] {
        all.filter { $0.unitOptions.contains { !$0.presets.isEmpty } }
    }

    // MARK: Vitals

    private static let vitals: [Metric] = [
        Metric(id: "bloodPressure", name: "Blood Pressure", category: .vitals,
               systemImage: "heart.text.square", kind: .bloodPressure),
        Metric(id: "bloodGlucose", name: "Blood Glucose", category: .vitals, systemImage: "drop",
               kind: .quantity(.bloodGlucose, [
                   UnitOption(unit: .gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci)),
                              label: "mg/dL", system: .us, range: 20...600, step: 1, defaultValue: 100),
                   UnitOption(unit: .moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose).unitDivided(by: .liter()),
                              label: "mmol/L", system: .metric, range: 1.1...33.3, step: 0.1, defaultValue: 5.5,
                              fractionDigits: 1),
               ])),
        Metric(id: "bodyTemperature", name: "Body Temperature", category: .vitals, systemImage: "thermometer.medium",
               kind: .quantity(.bodyTemperature, [
                   UnitOption(unit: .degreeCelsius(), label: "°C", system: .metric,
                              range: 34...43, step: 0.1, defaultValue: 36.8, fractionDigits: 1),
                   UnitOption(unit: .degreeFahrenheit(), label: "°F", system: .us,
                              range: 93...109.4, step: 0.1, defaultValue: 98.2, fractionDigits: 1),
               ])),
    ]

    // MARK: Body

    private static let body: [Metric] = [
        Metric(id: "bodyMass", name: "Weight", category: .body, systemImage: "scalemass",
               kind: .quantity(.bodyMass, massOptions(defaultKg: 70))),
        Metric(id: "bodyFatPercentage", name: "Body Fat", category: .body, systemImage: "percent",
               kind: .quantity(.bodyFatPercentage, [
                   UnitOption(unit: .percent(), label: "%", system: .both,
                              range: 2...70, step: 0.1, defaultValue: 20, fractionDigits: 1, scale: 100),
               ])),
        Metric(id: "leanBodyMass", name: "Lean Body Mass", category: .body, systemImage: "figure.strengthtraining.traditional",
               kind: .quantity(.leanBodyMass, massOptions(defaultKg: 55)), onWatch: false),
        Metric(id: "waistCircumference", name: "Waist Circumference", category: .body, systemImage: "ruler",
               kind: .quantity(.waistCircumference, [
                   UnitOption(unit: .meterUnit(with: .centi), label: "cm", system: .metric,
                              range: 40...200, step: 0.5, defaultValue: 85, fractionDigits: 1),
                   UnitOption(unit: .inch(), label: "in", system: .us,
                              range: 15...80, step: 0.5, defaultValue: 34, fractionDigits: 1),
               ]), onWatch: false),
    ]

    private static func massOptions(defaultKg: Double) -> [UnitOption] {
        [
            UnitOption(unit: .gramUnit(with: .kilo), label: "kg", system: .metric,
                       range: 20...300, step: 0.1, defaultValue: defaultKg, fractionDigits: 1),
            UnitOption(unit: .pound(), label: "lb", system: .us,
                       range: 44...660, step: 0.1, defaultValue: (defaultKg * 2.20462).rounded(), fractionDigits: 1),
        ]
    }

    // MARK: Intake

    private static let intake: [Metric] = [
        Metric(id: "dietaryWater", name: "Water", category: .intake, systemImage: "waterbottle",
               kind: .quantity(.dietaryWater, [
                   UnitOption(unit: .literUnit(with: .milli), label: "mL", system: .metric,
                              range: 10...5000, step: 50, defaultValue: 250, presets: [250, 500]),
                   UnitOption(unit: .fluidOunceUS(), label: "fl oz", system: .us,
                              range: 1...170, step: 1, defaultValue: 8, presets: [8, 16]),
               ])),
        Metric(id: "dietaryCaffeine", name: "Caffeine", category: .intake, systemImage: "cup.and.saucer",
               kind: .quantity(.dietaryCaffeine, [
                   UnitOption(unit: .gramUnit(with: .milli), label: "mg", system: .both,
                              range: 1...1000, step: 5, defaultValue: 95, presets: [64, 95]),
               ])),
        Metric(id: "alcoholicBeverages", name: "Alcoholic Drinks", category: .intake, systemImage: "wineglass",
               kind: .quantity(.numberOfAlcoholicBeverages, [
                   UnitOption(unit: .count(), label: "drinks", system: .both,
                              range: 1...20, step: 1, defaultValue: 1, presets: [1], singularLabel: "drink"),
               ])),
        Metric(id: "dietaryEnergyConsumed", name: "Calories", category: .intake, systemImage: "flame",
               kind: .quantity(.dietaryEnergyConsumed, [
                   UnitOption(unit: .kilocalorie(), label: "kcal", system: .both,
                              range: 1...5000, step: 10, defaultValue: 500),
               ]), onWatch: false),
        grams(.dietaryProtein, id: "dietaryProtein", name: "Protein", image: "fish", defaultValue: 25),
        grams(.dietaryCarbohydrates, id: "dietaryCarbohydrates", name: "Carbohydrates", image: "carrot", defaultValue: 40),
        grams(.dietaryFatTotal, id: "dietaryFatTotal", name: "Total Fat", image: "drop.halffull", defaultValue: 15),
        grams(.dietarySugar, id: "dietarySugar", name: "Sugar", image: "cube", defaultValue: 10),
        grams(.dietaryFiber, id: "dietaryFiber", name: "Fiber", image: "leaf", defaultValue: 5),
    ]

    private static func grams(_ id: HKQuantityTypeIdentifier, id key: String, name: String,
                              image: String, defaultValue: Double) -> Metric {
        Metric(id: key, name: name, category: .intake, systemImage: image,
               kind: .quantity(id, [
                   UnitOption(unit: .gram(), label: "g", system: .both,
                              range: 0.1...1000, step: 1, defaultValue: defaultValue, fractionDigits: 1),
               ]), onWatch: false)
    }

    // MARK: Symptoms & events

    private static let symptoms: [Metric] = [
        Metric(id: "inhalerUsage", name: "Inhaler Use", category: .symptoms, systemImage: "aqi.medium",
               kind: .quantity(.inhalerUsage, [
                   UnitOption(unit: .count(), label: "puffs", system: .both,
                              range: 1...10, step: 1, defaultValue: 1, presets: [1], singularLabel: "puff"),
               ])),
    ] + [
        (HKCategoryTypeIdentifier.headache, "Headache", "brain.head.profile"),
        (.nausea, "Nausea", "face.dashed"),
        (.fatigue, "Fatigue", "battery.25percent"),
        (.dizziness, "Dizziness", "tornado"),
        (.abdominalCramps, "Abdominal Cramps", "figure.core.training"),
        (.bloating, "Bloating", "circle.dashed"),
        (.heartburn, "Heartburn", "flame"),
        (.coughing, "Coughing", "wind"),
        (.soreThroat, "Sore Throat", "mouth"),
        (.runnyNose, "Runny Nose", "nose"),
        (.sinusCongestion, "Sinus Congestion", "allergens"),
        (.fever, "Fever", "thermometer.high"),
        (.chills, "Chills", "snowflake"),
        (.shortnessOfBreath, "Shortness of Breath", "lungs.fill"),
        (.lowerBackPain, "Lower Back Pain", "figure.walk"),
        (.generalizedBodyAche, "Body & Muscle Ache", "figure.cooldown"),
        (.diarrhea, "Diarrhea", "toilet"),
        (.vomiting, "Vomiting", "exclamationmark.triangle"),
    ].map { id, name, image in
        Metric(id: id.rawValue, name: name, category: .symptoms, systemImage: image, kind: .symptom(id))
    }
}
