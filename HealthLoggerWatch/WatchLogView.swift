import SwiftUI

struct WatchLogView: View {
    @Environment(HealthStore.self) private var health
    @State private var confirmation: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Add") {
                    ForEach(Metric.quickAdd) { metric in
                        if let option = health.unitOption(for: metric), let amount = option.presets.first {
                            Button {
                                quickAdd(metric, amount: amount, option: option)
                            } label: {
                                Label("\(metric.name) +\(option.format(amount))", systemImage: metric.systemImage)
                            }
                        }
                    }
                }
                ForEach(MetricCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(Metric.metrics(in: category, watchOnly: true)) { metric in
                            NavigationLink(value: metric) {
                                Label(metric.name, systemImage: metric.systemImage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .navigationDestination(for: Metric.self) { WatchEntryView(metric: $0) }
            .overlay(alignment: .bottom) {
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .padding(8)
                        .background(.green.opacity(0.85), in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func quickAdd(_ metric: Metric, amount: Double, option: UnitOption) {
        Task {
            do {
                try await health.saveQuantity(metric, value: amount, option: option, date: .now)
                WKHaptic.success()
                withAnimation { confirmation = "Logged \(option.format(amount))" }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { confirmation = nil }
            } catch {
                WKHaptic.failure()
            }
        }
    }
}

import WatchKit

enum WKHaptic {
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
}
