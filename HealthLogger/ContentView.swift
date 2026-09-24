import SwiftUI

struct ContentView: View {
    @Environment(HealthStore.self) private var health
    @Environment(WaterReminders.self) private var reminders
    @State private var authError: String?
    @State private var tab = AppTab.log
    @State private var logPath: [Metric] = []

    private enum AppTab { case log, nutrition, history, options }

    var body: some View {
        Group {
            if health.isAvailable {
                TabView(selection: $tab) {
                    Tab("Log", systemImage: "plus.circle", value: .log) { LogView(path: $logPath) }
                    Tab("Nutrition", systemImage: "fork.knife", value: .nutrition) { NutritionView() }
                    Tab("History", systemImage: "clock", value: .history) { HistoryView() }
                    Tab("Options", systemImage: "gearshape", value: .options) { OptionsView() }
                }
                .onOpenURL(perform: open)
                // Also checked on appear, for a tap that launched the app.
                .onChange(of: reminders.openedLink, initial: true) { _, link in
                    guard let link else { return }
                    open(link.url)
                    reminders.openedLink = nil
                }
                // Units and entries logged here change the reminders' text and timing.
                .onChange(of: health.changeCount) { reminders.reschedule() }
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

    /// Handles links from widgets and water reminders.
    private func open(_ url: URL) {
        switch DeepLink(url: url) {
        case .log(let metric):
            tab = .log
            logPath = [metric]
        case .nutrition:
            tab = .nutrition
        case nil:
            break
        }
    }
}
