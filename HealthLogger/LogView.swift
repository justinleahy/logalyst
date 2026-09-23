import SwiftUI

struct LogView: View {
    @Binding var path: [Metric]
    @Environment(HealthStore.self) private var health
    @State private var search = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if search.isEmpty {
                    Section {
                        ForEach(health.favorites) { row(for: $0) }
                    } header: {
                        Label("Favorites", systemImage: "star")
                    } footer: {
                        if health.favorites.isEmpty {
                            Text("Swipe right on a metric, or touch and hold it, to add it to Favorites.")
                        }
                    }
                    ForEach(MetricCategory.allCases) { category in
                        Section {
                            ForEach(Metric.metrics(in: category)) { row(for: $0) }
                        } header: {
                            Label(category.title, systemImage: category.systemImage)
                        }
                    }
                } else {
                    ForEach(searchResults) { row(for: $0) }
                }
            }
            .overlay {
                if !search.isEmpty && searchResults.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Search Metrics")
            .navigationTitle("Log Health Data")
            // A widget link can swap the open metric; the id gives the new one fresh state.
            .navigationDestination(for: Metric.self) { EntryView(metric: $0).id($0) }
        }
    }

    private var searchResults: [Metric] {
        Metric.search(search)
    }

    private func row(for metric: Metric) -> some View {
        NavigationLink(value: metric) {
            Label(metric.name, systemImage: metric.systemImage)
        }
        .favoriteActions(for: metric)
    }
}

extension View {
    /// Swipe and context menu actions to star or unstar a metric.
    func favoriteActions(for metric: Metric) -> some View {
        modifier(FavoriteActions(metric: metric))
    }
}

private struct FavoriteActions: ViewModifier {
    let metric: Metric
    @Environment(HealthStore.self) private var health

    func body(content: Content) -> some View {
        let isFavorite = health.isFavorite(metric)
        let title = isFavorite ? "Unfavorite" : "Favorite"
        let image = isFavorite ? "star.slash" : "star"
        content
            .swipeActions(edge: .leading) {
                Button(title, systemImage: image) { health.toggleFavorite(metric) }
                    .tint(.yellow)
            }
            .contextMenu {
                Button(title, systemImage: image) { health.toggleFavorite(metric) }
            }
    }
}
