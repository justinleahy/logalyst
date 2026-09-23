import SwiftUI

struct ContentView: View {
    @Environment(HealthStore.self) private var health
    @State private var authError: String?

    var body: some View {
        Group {
            if health.isAvailable {
                TabView {
                    Tab("Log", systemImage: "plus.circle") { LogView() }
                    Tab("History", systemImage: "clock") { HistoryView() }
                }
            } else {
                ContentUnavailableView("Health Unavailable", systemImage: "heart.slash",
                                       description: Text("Health data isn't available on this device."))
            }
        }
        .task {
            do { try await health.requestAuthorization() }
            catch { authError = error.localizedDescription }
        }
        .alert("Couldn't Request Health Access", isPresented: .constant(authError != nil)) {
            Button("OK") { authError = nil }
        } message: {
            Text(authError ?? "")
        }
    }
}
