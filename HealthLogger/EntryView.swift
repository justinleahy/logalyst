import SwiftUI
import HealthKit

struct EntryView: View {
    let metric: Metric
    /// An entry to change. Health can't edit a sample, so saving logs the new values and then deletes this one.
    var editing: LoggedEntry?

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
    @State private var duration = TimedEvent.defaultDuration
    @State private var protection = Protection.unspecified
    @State private var mealTime = BloodGlucoseMealTime.unspecified
    @State private var error: String?
    @State private var saved = false
    /// The edit saved but the original couldn't be deleted, so leave after the alert rather than save it twice.
    @State private var closeAfterError = false
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
            case .timedEvent:
                durationSection
            case .sexualActivity:
                protectionSection
            }

            Section {
                DatePicker(dateLabel, selection: $date,
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
        .alert(closeAfterError ? "Couldn't Remove Original" : "Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") {
                error = nil
                if closeAfterError { dismiss() }
            }
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
            presetsSection(option: option)
        }
    }

    /// Tap a preset to fill it in. Presets can be added from the typed amount and removed by touch and hold.
    @ViewBuilder
    private func presetsSection(option: UnitOption) -> some View {
        let presets = health.presets(for: metric, in: option)
        let canAdd = value.map { health.canAddPreset($0, for: metric, in: option) } ?? false
        let canReset = health.hasCustomPresets(for: metric, in: option) && !option.presets.isEmpty
        if !presets.isEmpty || canAdd || canReset {
            Section {
                if !presets.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(presets, id: \.self) { amount in
                                Button(option.format(amount)) { value = amount }
                                    .buttonStyle(.bordered)
                                    .contextMenu {
                                        // The whole row lifts with the menu, so name the preset being removed.
                                        Button("Remove \(option.format(amount))", systemImage: "trash",
                                               role: .destructive) {
                                            health.removePreset(amount, for: metric, in: option)
                                        }
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if canAdd, let value {
                    Button("Save \(option.format(option.rounded(value))) as Preset", systemImage: "plus.circle") {
                        health.addPreset(value, for: metric, in: option)
                    }
                }
                if canReset {
                    Button("Restore Default Presets", systemImage: "arrow.counterclockwise") {
                        health.resetPresets(for: metric, in: option)
                    }
                }
            } header: {
                Text("Presets")
            } footer: {
                if !presets.isEmpty {
                    Text("Touch and hold a preset to remove it.")
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

    private var durationSection: some View {
        Section("Duration") {
            Stepper(value: $duration, in: TimedEvent.range, step: TimedEvent.step) {
                Text(TimedEvent.format(duration, width: .wide))
                    .font(.title3.monospacedDigit())
            }
            HStack {
                ForEach(TimedEvent.presets, id: \.self) { preset in
                    Button(TimedEvent.format(preset)) { duration = preset }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var protectionSection: some View {
        Section("Protection") {
            Picker("Protection", selection: $protection) {
                ForEach(Protection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: Logic

    private var dateLabel: String {
        switch metric.kind {
        case .symptom where hasDuration: "Started"
        case .timedEvent: "Finished"
        default: "Date & Time"
        }
    }

    private var isSymptom: Bool {
        if case .symptom = metric.kind { true } else { false }
    }

    /// Switching units converts the typed value so it still means the same amount.
    private var unitBinding: Binding<UnitOption?> {
        Binding {
            option
        } set: { newOption in
            if let old = option, let new = newOption, let current = value {
                let converted = new.displayValue(current, from: old)
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
        case .symptom, .timedEvent, .sexualActivity:
            return true
        }
    }

    private func prefill() async {
        if let editing {
            prefill(from: editing.sample)
            return
        }
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
        case .symptom, .timedEvent, .sexualActivity:
            break
        }
    }

    /// Fills the form with a logged entry's values, in the unit the app shows it in.
    private func prefill(from sample: HKSample) {
        date = sample.startDate
        switch metric.kind {
        case .quantity:
            guard let preferred = health.unitOption(for: metric),
                  let quantity = (sample as? HKQuantitySample)?.quantity else { return }
            option = preferred
            value = preferred.displayValue(from: quantity)
            let storedMealTime = sample.metadata?[HKMetadataKeyBloodGlucoseMealTime] as? Int
            mealTime = BloodGlucoseMealTime.allCases.first { $0.healthKitValue?.rawValue == storedMealTime } ?? .unspecified
            focusedField = .value
        case .bloodPressure:
            if let correlation = sample as? HKCorrelation, let values = health.bloodPressureValues(correlation) {
                systolic = values.systolic
                diastolic = values.diastolic
            }
            focusedField = .systolic
        case .symptom:
            if let category = sample as? HKCategorySample {
                severity = Severity(healthKitValue: category.value) ?? .mild
            }
            hasDuration = sample.endDate > sample.startDate
            endDate = sample.endDate
        case .timedEvent:
            // Timed events are entered by when they finished.
            date = sample.endDate
            duration = sample.endDate.timeIntervalSince(sample.startDate)
        case .sexualActivity:
            protection = Protection(metadata: sample.metadata)
        }
    }

    private func save() {
        Task {
            do {
                try await saveEntry()
            } catch {
                self.error = error.healthMessage
                return
            }
            // Deleting only after the new entry saved means a failure can leave a duplicate, never lose the entry.
            if let editing {
                do {
                    try await health.delete(editing)
                } catch {
                    closeAfterError = true
                    self.error = "The new entry was saved, but the original is still in Health, so History shows both. "
                        + "Swipe to delete the one you don't want.\n\n\(error.healthMessage)"
                    return
                }
            }
            saved.toggle()
            dismiss()
        }
    }

    private func saveEntry() async throws {
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
        case .timedEvent:
            try await health.saveTimedEvent(metric, duration: duration, end: date)
        case .sexualActivity:
            try await health.saveSexualActivity(protection: protection, date: date)
        }
    }
}
