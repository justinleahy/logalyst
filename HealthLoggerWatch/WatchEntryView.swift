import SwiftUI

struct WatchEntryView: View {
    let metric: Metric

    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

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
            }
        }
        .navigationTitle(metric.name)
        .alert("Couldn't Save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func save(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                WKHaptic.success()
                dismiss()
            } catch {
                WKHaptic.failure()
                self.error = error.localizedDescription
            }
        }
    }
}

/// Turn the Digital Crown to adjust the value, then tap Save.
private struct QuantityEntry: View {
    let metric: Metric
    let option: UnitOption
    let onSave: (@escaping () async throws -> Void) -> Void

    @Environment(HealthStore.self) private var health
    @State private var value: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            Text(value.formatted(.number.precision(.fractionLength(option.fractionDigits))))
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .focusable()
                .digitalCrownRotation($value, from: option.range.lowerBound, through: option.range.upperBound,
                                      by: option.step, sensitivity: .low, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            Text(option.label).foregroundStyle(.secondary)
            Button("Save") {
                onSave { try await health.saveQuantity(metric, value: value, option: option, date: .now) }
            }
            .buttonStyle(.borderedProminent)
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
