import SwiftUI

struct WatchEntryView: View {
    let metric: Metric

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    /// A save is in flight, so another tap doesn't log the entry twice.
    @State private var isSaving = false

    var body: some View {
        Group {
            switch metric.kind {
            case .quantity:
                if let option = health.unitOption(for: metric) {
                    QuantityEntry(metric: metric, option: option, onSave: save)
                }
            case .bloodPressure:
                BloodPressureEntry(onSave: save)
            case .symptom:
                List(Severity.allCases) { severity in
                    Button(severity.title) {
                        save { try await health.saveSymptom(metric, severity: severity, start: .now, end: .now) }
                    }
                }
            case .timedEvent:
                List(TimedEvent.presets, id: \.self) { duration in
                    Button(TimedEvent.format(duration, width: .wide)) {
                        save { try await health.saveTimedEvent(metric, duration: duration, end: .now) }
                    }
                }
            case .sexualActivity:
                List(Protection.allCases) { protection in
                    Button(protection == .unspecified ? "Log" : "Protection \(protection.title)") {
                        save { try await health.saveSexualActivity(protection: protection, date: .now) }
                    }
                }
            }
        }
        .disabled(isSaving)
        .navigationTitle(metric.name)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func save(_ work: @escaping () async throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await work()
                WKHaptic.success()
                dismiss()
            } catch {
                WKHaptic.failure()
                self.error = error.healthMessage
                isSaving = false
            }
        }
    }
}

/// Turn the Digital Crown to adjust the value, or tap a preset to fill it in, then tap Save.
private struct QuantityEntry: View {
    let metric: Metric
    let option: UnitOption
    let onSave: (@escaping () async throws -> Void) -> Void

    @Environment(HealthStore.self) private var health
    @State private var value: Double = 0

    var body: some View {
        // The presets for the unit the Watch enters in, edited on the iPhone (or the built-in ones), smallest first.
        let presets = health.presets(for: metric, in: option)
        // Scrolls on the smallest watches when there are more than a row of presets.
        ScrollView {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value.formatted(.number.precision(.fractionLength(option.fractionDigits))))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .focusable()
                        .digitalCrownRotation($value, from: option.range.lowerBound, through: option.range.upperBound,
                                              by: option.step, sensitivity: .low, isContinuous: false,
                                              isHapticFeedbackEnabled: true)
                        .accessibilityValue(option.format(value))
                    Text(option.label(for: value)).foregroundStyle(.secondary)
                }
                if !presets.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(presets, id: \.self) { amount in
                            // Fills in the amount without saving, so it can still be turned or checked first.
                            Button(option.formatNumber(amount)) { value = amount }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.mini)
                                .tint(value == amount ? .accentColor : nil)
                                .accessibilityLabel(option.format(amount))
                                .accessibilityAddTraits(value == amount ? .isSelected : [])
                        }
                    }
                }
                Button("Save") {
                    onSave { try await health.saveQuantity(metric, value: value, option: option, date: .now) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            value = option.defaultValue
            if metric.category != .intake, let last = await health.latestValue(for: metric, option: option) {
                value = min(max(last, option.range.lowerBound), option.range.upperBound)
            }
        }
    }
}

/// Tap a number to select it, then turn the Digital Crown.
private struct BloodPressureEntry: View {
    let onSave: (@escaping () async throws -> Void) -> Void

    @Environment(HealthStore.self) private var health
    @State private var systolic = BloodPressure.defaultSystolic
    @State private var diastolic = BloodPressure.defaultDiastolic
    @FocusState private var focused: Field?

    private enum Field { case systolic, diastolic }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                number($systolic, field: .systolic, range: BloodPressure.systolicRange)
                Text("/").font(.title2)
                number($diastolic, field: .diastolic, range: BloodPressure.diastolicRange)
            }
            Text("mmHg").foregroundStyle(.secondary)
            Button("Save") {
                let (sys, dia) = (systolic, diastolic)
                onSave { try await health.saveBloodPressure(systolic: sys, diastolic: dia, date: .now) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(systolic <= diastolic)
        }
        .task {
            focused = .systolic
            if let last = await health.latestBloodPressure() {
                systolic = last.systolic
                diastolic = last.diastolic
            }
        }
    }

    private func number(_ value: Binding<Double>, field: Field, range: ClosedRange<Double>) -> some View {
        Text("\(Int(value.wrappedValue))")
            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            .padding(.horizontal, 6)
            .background(focused == field ? Color.accentColor.opacity(0.3) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .focusable()
            .focused($focused, equals: field)
            .digitalCrownRotation(value, from: range.lowerBound, through: range.upperBound, by: 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture { focused = field }
    }
}
