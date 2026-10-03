import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(HealthStore.self) private var health
    @Environment(LogReminders.self) private var reminders
    @Environment(NutritionGoals.self) private var goals
    @Environment(\.modelContext) private var modelContext
    @State private var authError: String?
    /// The first time the app opens on this iPhone.
    @State private var onboarding = false
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
                .onChange(of: IntentNavigation.shared.link, initial: true) { _, link in
                    guard let link else { return }
                    open(link.url)
                    IntentNavigation.shared.link = nil
                }
                // Units and entries logged here change the reminders' text and timing.
                .onChange(of: health.changeCount) { reminders.reschedule() }
                // Edits left unfinished while Health couldn't be read (such as while locked) can finish now.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                    Task { await health.finishPendingEdits() }
                }
            } else {
                ContentUnavailableView("Health Unavailable", systemImage: "heart.slash",
                                       description: Text("Health data isn't available on this device."))
            }
        }
        .task {
            #if DEBUG
            if ScreenshotData.isRequested { Onboarding.finish() }
            #endif
            // Onboarding asks for Health access itself, once it's explained what for.
            if Onboarding.isNeeded(health: health, context: modelContext) {
                onboarding = true
            } else {
                await requestHealthAccess()
            }
            // An edit the app was closed in the middle of is finished now.
            await health.finishPendingEdits()
            #if DEBUG
            await ScreenshotData.seed(health: health, goals: goals, context: modelContext)
            #endif
        }
        .fullScreenCover(isPresented: $onboarding, onDismiss: {
            Onboarding.finish()
            // Asks now if onboarding was skipped before it did; otherwise this shows nothing.
            Task { await requestHealthAccess() }
        }) {
            OnboardingView { onboarding = false }
        }
        .alert("Couldn't Request Health Access", isPresented: .constant(authError != nil)) {
            Button("OK") { authError = nil }
        } message: {
            Text(authError ?? "")
        }
    }

    private func requestHealthAccess() async {
        do { try await health.requestAuthorization() }
        catch { authError = error.localizedDescription }
    }

    /// Handles links from widgets, controls and reminders.
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
