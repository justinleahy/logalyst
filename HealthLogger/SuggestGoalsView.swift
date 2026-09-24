import HealthKit
import SwiftUI

/// Estimates calorie and nutrient goals from the user's body, activity and aim, then applies them on request.
struct SuggestGoalsView: View {
    @Environment(HealthStore.self) private var health
    @Environment(NutritionGoals.self) private var goals
    @Environment(\.dismiss) private var dismiss

    @AppStorage("suggestGoalsActivity") private var activity = BodyProfile.Activity.light
    @AppStorage("suggestGoalsAim") private var aim = BodyProfile.Aim.maintain
    @AppStorage("suggestGoalsUsesRestingEnergy") private var usesRestingEnergy = true
    /// Weight in the user's weight unit.
    @State private var weight: Double?
    @State private var heightCm: Double?
    @State private var feet: Int?
    @State private var inches: Int?
    @State private var age: Int?
    @State private var sex: BodyProfile.Sex?
    /// Typical daily resting energy from Apple Health, in kcal.
    @State private var restingEnergy: Double?

    private static let bodyMass = Metric.metric(id: "bodyMass")!

    var body: some View {
        Form {
            Section {
                weightRow
                heightRow
                LabeledContent("Age") {
                    HStack {
                        numberField("Age", value: $age)
                        Text("years").foregroundStyle(.secondary)
                    }
                }
                Picker("Sex", selection: $sex) {
                    Text("Not Set").tag(BodyProfile.Sex?.none)
                    ForEach(BodyProfile.Sex.allCases) { Text($0.title).tag(Optional($0)) }
                }
                if let restingEnergy {
                    Toggle(isOn: $usesRestingEnergy) {
                        VStack(alignment: .leading) {
                            Text("Use Resting Energy")
                            Text("\(Self.kcal(restingEnergy)) a day in Apple Health")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("About You")
            }
            Section("Activity") {
                Picker("Activity", selection: $activity) {
                    ForEach(BodyProfile.Activity.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.title)
                            Text(level.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Weight Goal") {
                Picker("Weight Goal", selection: $aim) {
                    ForEach(BodyProfile.Aim.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            suggestionSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Suggest Goals")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: Inputs

    private var weightOption: UnitOption? {
        health.unitOption(for: Self.bodyMass)
    }

    private var weightRow: some View {
        LabeledContent("Weight") {
            HStack {
                numberField("Weight", value: $weight, fractionDigits: 1)
                Text(weightOption?.label ?? "").foregroundStyle(.secondary)
            }
        }
    }

    /// Feet and inches for people who weigh in pounds, centimeters otherwise.
    private var usesFeetAndInches: Bool {
        weightOption?.system == .us
    }

    @ViewBuilder private var heightRow: some View {
        if usesFeetAndInches {
            LabeledContent("Height") {
                HStack {
                    numberField("0", value: $feet, width: 40)
                    Text("ft").foregroundStyle(.secondary)
                    numberField("0", value: $inches, width: 40)
                    Text("in").foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent("Height") {
                HStack {
                    numberField("Height", value: $heightCm, fractionDigits: 1)
                    Text("cm").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Height in centimeters, from whichever fields are showing.
    private var height: Double? {
        guard usesFeetAndInches else { return heightCm }
        guard let feet else { return nil }
        return Double(feet * 12 + (inches ?? 0)) * 2.54
    }

    private func numberField(_ title: String, value: Binding<Int?>, width: CGFloat = 70) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(maxWidth: width)
    }

    private func numberField(_ title: String, value: Binding<Double?>, fractionDigits: Int) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...fractionDigits)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(maxWidth: 70)
    }

    private func load() async {
        try? await health.requestProfileAuthorization()
        if weight == nil, let weightOption,
           let latest = await health.latestValue(for: Self.bodyMass, option: weightOption) {
            weight = (latest * 10).rounded() / 10
        }
        if heightCm == nil, feet == nil, let latest = await health.latestHeightCm() {
            heightCm = (latest * 10).rounded() / 10
            let totalInches = Int((latest / 2.54).rounded())
            feet = totalInches / 12
            inches = totalInches % 12
        }
        if age == nil {
            age = health.age()
        }
        if sex == nil {
            sex = health.biologicalSex().map(BodyProfile.Sex.init)
        }
        restingEnergy = await health.typicalRestingEnergy()
    }

    // MARK: Suggestion

    private var profile: BodyProfile? {
        guard let weight, let weightOption, let height, let age, let sex else { return nil }
        let weightKg = weightOption.quantity(fromDisplay: weight).doubleValue(for: .gramUnit(with: .kilo))
        guard BodyProfile.weightRange.contains(weightKg), BodyProfile.heightRange.contains(height),
              BodyProfile.adultAges.contains(age) else { return nil }
        return BodyProfile(weightKg: weightKg, heightCm: height, age: age, sex: sex, activity: activity, aim: aim,
                           measuredRestingCalories: usesRestingEnergy ? restingEnergy : nil)
    }

    @ViewBuilder private var suggestionSection: some View {
        if let profile {
            let suggestion = SuggestedGoals(profile)
            Section {
                ForEach(NutritionView.food) { metric in
                    if let amount = suggestion.amounts[metric.id] {
                        suggestionRow(metric, amount: amount)
                    }
                }
                Button("Use These Goals") {
                    goals.setGoals(suggestion.amounts)
                    dismiss()
                }
            } header: {
                Text("Suggested Goals")
            } footer: {
                Text(explanation(for: profile))
            }
        } else {
            Section("Suggested Goals") {
                Text(missingInputMessage).foregroundStyle(.secondary)
            }
        }
    }

    private var missingInputMessage: String {
        if let age, age < BodyProfile.adultAges.lowerBound {
            "Suggestions are for adults. For children and teens, ask a doctor or dietitian about goals."
        } else {
            "Enter your weight, height, age and sex to see suggested goals."
        }
    }

    private func suggestionRow(_ metric: Metric, amount: Double) -> some View {
        let option = metric.unitOptions[0]
        let current = goals.goal(for: metric, in: option)
        return HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(metric.name)
                    if metric.dailyGoal?.isLimit == true {
                        Text("Limit").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: metric.systemImage)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(option.format(amount)).monospacedDigit()
                if let current, current != amount {
                    Text("Now \(option.format(current))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted()) kcal"
    }

    private func explanation(for profile: BodyProfile) -> String {
        let kcal = Self.kcal
        let adjustment = switch profile.aim {
        case .lose: " Losing weight takes off up to \(kcal(SuggestedGoals.deficit)) a day, but never below \(kcal(profile.sex.calorieFloor))."
        case .maintain: ""
        case .gain: " Gaining weight adds \(kcal(SuggestedGoals.surplus)) a day."
        }
        let restingSource = profile.measuredRestingCalories == nil
            ? "Mifflin–St Jeor equation"
            : "Apple Health's resting energy, typical day over the last 2 weeks"
        let proteinPerKg = profile.aim == .maintain ? SuggestedGoals.maintenanceProteinPerKg : SuggestedGoals.proteinPerKg
        return """
            You burn about \(kcal(profile.restingCalories)) a day at rest (\(restingSource)) and \
            \(kcal(profile.maintenanceCalories)) with your activity.\(adjustment) Protein is \(proteinPerKg.formatted()) g per kg \
            of body weight, fat 30% of calories, carbohydrates the rest, sugar under 10% of calories, and fiber 14 g \
            per 1,000 kcal.

            These are estimates, not medical advice. If you're pregnant, breastfeeding or managing a health \
            condition, ask a doctor or dietitian about your goals.
            """
    }
}

private extension BodyProfile.Sex {
    init(_ sex: HKBiologicalSex) {
        self = switch sex {
        case .female: .female
        case .male: .male
        default: .other
        }
    }
}
