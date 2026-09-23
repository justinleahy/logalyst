import SwiftUI
import HealthKit

struct EntryView: View {
    let metric: Metric

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now
    @State private var endDate = Date.now
    @State private var hasDuration = false
    @State private var option: UnitOption?
    @State private var value: Double?
    @State private var systolic: Double?
    @State private var diastolic: Double?
    @State private var severity = Severity.mild
    @State private var mealTime = BloodGlucoseMealTime.unspecified
    @State private var error: String?
    @State private var saved = false
    @FocusState private var focusedField: Field?

    private enum Field { case value, systolic, diastolic }

    var body: some View {
        Form {
            switch metric.kind {
            case .quantity(let id, let options):
                quantitySection(options: options, isGlucose: id == .bloodGlucose)
            case .bloodPressure:
                bloodPressureSection
            case .symptom:
                symptomSection
            }

            Section {
                DatePicker(isSymptom && hasDuration ? "Started" : "Date & Time", selection: $date,
                           in: ...Date.now)
                if isSymptom {
                    Toggle("Has Duration", isOn: $hasDuration)
                    if hasDuration {
                        DatePicker("Ended", selection: $endDate, in: date...Date.now)
                    }
                }
            }
        }
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(!isValid)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await prefill() }
    }

    // MARK: Sections

    @ViewBuilder
    private func quantitySection(options: [UnitOption], isGlucose: Bool) -> some View {
        if let option {
            Section {
                HStack {
                    TextField(option.format(option.defaultValue), value: $value,
                              format: .number.precision(.fractionLength(0...option.fractionDigits)))
                        .keyboardType(option.fractionDigits > 0 ? .decimalPad : .numberPad)
                        .font(.title2.monospacedDigit())
                        .focused($focusedField, equals: .value)
                    Text(option.label).foregroundStyle(.secondary)
                }
                if options.count > 1 {
                    Picker("Unit", selection: unitBinding) {
                        ForEach(options, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                if isGlucose {
                    Picker("Meal Time", selection: $mealTime) {
                        ForEach(BloodGlucoseMealTime.allCases) { Text($0.title).tag($0) }
                    }
                }
            } footer: {
                Text("Valid range: \(option.format(option.range.lowerBound)) – \(option.format(option.range.upperBound))")
            }
            if !option.presets.isEmpty {
                Section("Presets") {
                    HStack {
                        ForEach(option.presets, id: \.self) { amount in
                            Button(option.format(amount)) { value = amount }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var bloodPressureSection: some View {
        Section {
            HStack {
                Text("Systolic")
                TextField("\(Int(BloodPressure.defaultSystolic))", value: $systolic, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit())
                    .focused($focusedField, equals: .systolic)
                Text("mmHg").foregroundStyle(.secondary)
            }
            HStack {
                Text("Diastolic")
                TextField("\(Int(BloodPressure.defaultDiastolic))", value: $diastolic, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit())
                    .focused($focusedField, equals: .diastolic)
                Text("mmHg").foregroundStyle(.secondary)
            }
        } footer: {
            Text("Systolic (top number) must be higher than diastolic (bottom number).")
        }
    }

    private var symptomSection: some View {
        Section("Severity") {
            Picker("Severity", selection: $severity) {
                ForEach(Severity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    // MARK: Logic

    private var isSymptom: Bool {
        if case .symptom = metric.kind { true } else { false }
    }

    /// Switching units converts the typed value so it still means the same amount.
    private var unitBinding: Binding<UnitOption?> {
        Binding {
            option
        } set: { newOption in
            if let old = option, let new = newOption, let current = value {
                let converted = new.displayValue(from: old.quantity(fromDisplay: current))
                value = (converted / new.step).rounded() * new.step
            }
            option = newOption
        }
    }

    private var isValid: Bool {
        switch metric.kind {
        case .quantity:
            guard let option, let value else { return false }
            return option.range.contains(value)
        case .bloodPressure:
            guard let systolic, let diastolic else { return false }
            return BloodPressure.systolicRange.contains(systolic)
                && BloodPressure.diastolicRange.contains(diastolic)
                && systolic > diastolic
        case .symptom:
            return true
        }
    }

    private func prefill() async {
        switch metric.kind {
        case .quantity:
            guard option == nil, let preferred = health.unitOption(for: metric) else { return }
            option = preferred
            // Measurements like weight benefit from starting at the last reading; intake doesn't.
            if metric.category == .body || metric.category == .vitals {
                value = await health.latestValue(for: metric, option: preferred)
            }
            focusedField = .value
        case .bloodPressure:
            if let last = await health.latestBloodPressure() {
                systolic = last.systolic
                diastolic = last.diastolic
            }
            focusedField = .systolic
        case .symptom:
            break
        }
    }

    private func save() {
        Task {
            do {
                switch metric.kind {
                case .quantity:
                    guard let option, let value else { return }
                    try await health.saveQuantity(metric, value: value, option: option, date: date, mealTime: mealTime)
                case .bloodPressure:
                    guard let systolic, let diastolic else { return }
                    try await health.saveBloodPressure(systolic: systolic, diastolic: diastolic, date: date)
                case .symptom:
                    try await health.saveSymptom(metric, severity: severity, start: date,
                                                 end: hasDuration ? endDate : date)
                }
                saved.toggle()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
