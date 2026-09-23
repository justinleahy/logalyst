import SwiftUI

struct WatchLogView: View {
    @Environment(HealthStore.self) private var health
    @State private var path: [Metric] = []
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if search.isEmpty {
                    let favorites = health.favorites.filter(\.onWatch)
                    if !favorites.isEmpty {
                        Section("Favorites") {
                            ForEach(favorites) { row(for: $0) }
                        }
                    }
                    ForEach(MetricCategory.allCases) { category in
                        Section(category.title) {
                            ForEach(Metric.metrics(in: category, watchOnly: true)) { row(for: $0) }
                        }
                    }
                } else {
                    let results = Metric.search(search, watchOnly: true)
                    ForEach(results) { row(for: $0) }
                    if results.isEmpty {
                        Text("No Results").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Log")
            // A complication link can swap the open metric; the id gives the new one fresh state.
            .navigationDestination(for: Metric.self) { WatchEntryView(metric: $0).id($0) }
        }
        // Complications link straight to a metric's entry screen.
        .onOpenURL { url in
            if case .log(let metric) = DeepLink(url: url) { path = [metric] }
        }
    }

    private func row(for metric: Metric) -> some View {
        let isFavorite = health.isFavorite(metric)
        return NavigationLink(value: metric) {
            Label(metric.name, systemImage: metric.systemImage)
        }
        .swipeActions(edge: .leading) {
            Button(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star") {
                health.toggleFavorite(metric)
            }
            .tint(.yellow)
        }
    }
}

import WatchKit

enum WKHaptic {
    static func success() { WKInterfaceDevice.current().play(.success) }
    static func failure() { WKInterfaceDevice.current().play(.failure) }
}
