import SwiftUI

struct LogView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Quick Add") {
                    ForEach(Metric.quickAdd) { QuickAddRow(metric: $0) }
                }
                ForEach(MetricCategory.allCases) { category in
                    Section {
                        ForEach(Metric.metrics(in: category)) { metric in
                            NavigationLink(value: metric) {
                                Label(metric.name, systemImage: metric.systemImage)
                            }
                        }
                    } header: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            }
            .navigationTitle("Log Health Data")
            .navigationDestination(for: Metric.self) { EntryView(metric: $0) }
        }
    }
}

/// One-tap preset buttons, e.g. "+8 fl oz" of water.
private struct QuickAddRow: View {
    let metric: Metric
    @Environment(HealthStore.self) private var health
    @State private var savedCount = 0
    @State private var error: String?

    var body: some View {
        if let option = health.unitOption(for: metric) {
            HStack {
                Label(metric.name, systemImage: metric.systemImage)
                Spacer()
                ForEach(option.presets, id: \.self) { amount in
                    Button("+\(option.format(amount))") {
                        Task {
                            do {
                                try await health.saveQuantity(metric, value: amount, option: option, date: .now)
                                savedCount += 1
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.callout)
                }
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .alert("Couldn't Save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }
}
