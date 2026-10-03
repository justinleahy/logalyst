import SwiftData
import SwiftUI

/// The first time Logalyst opens on an iPhone: what it does and why it asks for Health access (asking only once
/// that's explained), then favorites, goals and reminders. Every step can be skipped, and the app works whatever
/// the answers. The Watch has no introduction of its own; it asks for Health access when it first opens.
struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(HealthStore.self) private var health
    @State private var step = Step.welcome
    @State private var editingGoals = false
    @State private var settingReminders = false

    private enum Step: Int, CaseIterable {
        case welcome, favorites, goals, reminders
    }

    /// Metrics people often star, offered first. Any metric can be starred later in the Log list.
    private static let suggestedFavorites = ["dietaryWater", "bodyMass", "bloodPressure", "bloodGlucose",
                                             "dietaryCaffeine", "alcoholicBeverages", "bodyTemperature",
                                             "HKCategoryTypeIdentifierHeadache", "inhalerUsage",
                                             "HKCategoryTypeIdentifierToothbrushingEvent"]
        .compactMap { Metric.metric(id: $0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .welcome: welcome
                    case .favorites: favorites
                    case .goals: goals
                    case .reminders: reminders
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: next) {
                    Text(step == .reminders ? "Done" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .welcome {
                        Button("Back", systemImage: "chevron.left") { move(by: -1) }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    if step != .reminders {
                        Button("Skip", action: onFinish)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editingGoals) { GoalsView() }
            .sheet(isPresented: $settingReminders) {
                NavigationStack {
                    LogRemindersView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { settingReminders = false }
                            }
                        }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Steps

    private var welcome: some View {
        Group {
            heading("Welcome to Logalyst", systemImage: "heart.text.square.fill")
            Text("Log what your Apple Watch can't measure, like blood pressure, weight, water, food and symptoms, "
                 + "straight into Apple Health from your iPhone and Apple Watch.")
            VStack(alignment: .leading, spacing: 8) {
                Label("Health Access", systemImage: "lock.shield").font(.headline)
                Text("Logalyst saves what you log to the Health app, and reads it back to show your history, "
                     + "today's totals and your last reading. Next, Health asks which kinds of data Logalyst can "
                     + "use. Choose any you like: the rest of the app works either way, and you can change it "
                     + "later in the Health app.")
            }
            .padding()
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
    }

    private var favorites: some View {
        Group {
            heading("Your Favorites", systemImage: "star.fill")
            Text("Favorites sit at the top of the Log list, in the Quick Log widget, and on Apple Watch. Star the "
                 + "ones you log most. You can change them any time by swiping right on a metric.")
            VStack(spacing: 0) {
                ForEach(Self.suggestedFavorites) { metric in
                    let isFavorite = health.isFavorite(metric)
                    Button {
                        health.toggleFavorite(metric)
                    } label: {
                        HStack {
                            Label(metric.name, systemImage: metric.systemImage)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isFavorite ? .isSelected : [])
                    .accessibilityHint(isFavorite ? "Removes it from Favorites" : "Adds it to Favorites")
                    Divider()
                }
            }
        }
    }

    private var goals: some View {
        Group {
            heading("Daily Goals", systemImage: "target")
            Text("The Nutrition tab tracks water, calories and nutrients against daily goals. They start at "
                 + "general guidelines for a 2,000-calorie diet. Logalyst can suggest goals from your height, "
                 + "weight, age and activity instead, or you can set your own.")
            Button("Review Goals", systemImage: "wand.and.sparkles") { editingGoals = true }
                .buttonStyle(.bordered)
        }
    }

    private var reminders: some View {
        Group {
            heading("Reminders to Log", systemImage: "bell.badge")
            Text("Get a reminder to drink water, check your blood pressure or log anything else, at set times or "
                 + "when you haven't logged for a while. You can add them any time in Options.")
            Button("Set Up Reminders", systemImage: "bell") { settingReminders = true }
                .buttonStyle(.bordered)
        }
    }

    private func heading(_ title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top)
    }

    // MARK: Moving on

    private func next() {
        switch step {
        case .welcome:
            // Asked here, once it's been explained. Declining still moves on.
            Task {
                try? await health.requestAuthorization()
                move(by: 1)
            }
        case .reminders:
            onFinish()
        default:
            move(by: 1)
        }
    }

    private func move(by offset: Int) {
        withAnimation { step = Step(rawValue: step.rawValue + offset) ?? step }
    }
}

/// Whether to show onboarding. 1.0 asked for Health access as soon as it opened and kept no record of a first
/// launch, so someone upgrading is recognized by what it left on the iPhone: Health already asked, or favorites,
/// goals or saved foods (including ones iCloud brought). They go straight to the app, as do people who finished or
/// skipped onboarding.
enum Onboarding {
    private static let finishedKey = "onboardingFinished"

    static var isFinished: Bool {
        UserDefaults.standard.bool(forKey: finishedKey)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: finishedKey)
    }

    @MainActor
    static func isNeeded(health: HealthStore, context: ModelContext) -> Bool {
        #if DEBUG
        // For UI tests, on a simulator that has used the app already.
        if UserDefaults.standard.bool(forKey: "ShowOnboarding") { return true }
        #endif
        guard !isFinished, health.isAvailable else { return false }
        let hasSettings = !health.favorites.isEmpty || !NutritionGoals.saved.isEmpty
            || ((try? context.fetchCount(FetchDescriptor<Food>())) ?? 0) > 0
        if hasSettings || health.hasAskedForAccess {
            finish()
            return false
        }
        return true
    }
}
