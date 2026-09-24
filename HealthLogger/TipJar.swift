import Observation
import StoreKit
import SwiftUI

/// Optional tips to support the app, sold as consumable in-app purchases. Tips don't unlock anything.
@Observable
final class TipJar {
    enum Status: Equatable {
        case loading
        case loaded
        case failed
    }

    /// The tip product IDs, smallest first. Each needs a matching consumable in App Store Connect.
    static let productIDs = [
        "com.justinleahy.HealthLogger.tip.small",
        "com.justinleahy.HealthLogger.tip.medium",
        "com.justinleahy.HealthLogger.tip.large",
    ]

    private(set) var products: [Product] = []
    private(set) var status = Status.loading
    /// The tip being bought, so its button can show progress.
    private(set) var purchasing: Product.ID?
    /// Set after a tip goes through, to thank the user.
    var showsThanks = false

    private var updates: Task<Void, Never>?

    init() {
        // Finishes tips that complete outside a purchase call, like Ask to Buy approvals or interrupted purchases.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                self?.showsThanks = true
            }
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        status = .loading
        do {
            let products = try await Product.products(for: Self.productIDs)
            self.products = products.sorted { $0.price < $1.price }
            status = products.isEmpty ? .failed : .loaded
        } catch {
            status = .failed
        }
    }

    func purchase(_ product: Product) async {
        purchasing = product.id
        defer { purchasing = nil }
        guard case .success(let result) = try? await product.purchase(),
              case .verified(let transaction) = result else { return }
        await transaction.finish()
        showsThanks = true
    }
}

/// Lists the tips, from Options.
struct TipJarView: View {
    @Environment(TipJar.self) private var tipJar

    var body: some View {
        @Bindable var tipJar = tipJar
        List {
            Section {
                switch tipJar.status {
                case .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tips couldn't be loaded. Check your connection and try again.")
                            .foregroundStyle(.secondary)
                        Button("Try Again") { Task { await tipJar.loadProducts() } }
                    }
                case .loaded:
                    ForEach(tipJar.products) { row(for: $0) }
                }
            } header: {
                Text("Logalyst is free, with no ads or tracking. If it's useful to you, a tip helps keep it going.")
                    .textCase(nil)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.bottom, 8)
            } footer: {
                Text("Tips are one-time purchases and don't unlock any features.")
            }
        }
        .navigationTitle("Tip Jar")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tipJar.loadProducts() }
        .alert("Thank You!", isPresented: $tipJar.showsThanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your tip means a lot and helps keep Logalyst going.")
        }
    }

    private func row(for product: Product) -> some View {
        LabeledContent {
            Button {
                Task { await tipJar.purchase(product) }
            } label: {
                if tipJar.purchasing == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(tipJar.purchasing != nil)
        } label: {
            Label {
                Text(product.displayName)
                if !product.description.isEmpty {
                    Text(product.description)
                }
            } icon: {
                Image(systemName: Self.symbols[product.id] ?? "heart")
            }
        }
    }

    private static let symbols = [
        "com.justinleahy.HealthLogger.tip.small": "drop",
        "com.justinleahy.HealthLogger.tip.medium": "cup.and.saucer",
        "com.justinleahy.HealthLogger.tip.large": "fork.knife",
    ]
}
