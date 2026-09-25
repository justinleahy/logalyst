import SwiftUI
import UIKit
import Charts

struct NutritionView: View {
    @Environment(HealthStore.self) private var health
    @Environment(NutritionGoals.self) private var goals
    @Environment(\.scenePhase) private var scenePhase

    /// Last `trendDays` of totals per metric, oldest first, so `.last` is today.
    @State private var totals: [Metric: [DailyTotal]] = [:]
    @State private var waterToday: [LoggedEntry] = []
    @State private var foodToday: [LoggedEntry] = []
    @State private var scanning = false
    @State private var scanningLabel = false
    @State private var photographingMeal = false
    @State private var trendMetric = Self.water
    @State private var editingGoals = false
    @State private var error: String?

    static let intake = Metric.metrics(in: .intake)
    static let water = Metric.water
    private static let drinkIDs: Set = ["dietaryCaffeine", "alcoholicBeverages"]
    static let food = intake.filter { $0 != water && !drinkIDs.contains($0.id) }
    static let drinks = intake.filter { drinkIDs.contains($0.id) }
    private static let trendDays = 7

    var body: some View {
        NavigationStack {
            List {
                hydrationSection
                if !waterToday.isEmpty {
                    waterLogSection
                }
                foodSection
                nutrientSection("Nutrients", metrics: Self.food)
                nutrientSection("Drinks", metrics: Self.drinks)
                trendSection
            }
            .navigationTitle("Nutrition")
            .navigationDestination(for: Metric.self) { EntryView(metric: $0) }
            .navigationDestination(for: LoggedEntry.self) { entry in
                if let metric = entry.metric { EntryView(metric: metric, editing: entry) }
            }
            .toolbar {
                Button("Goals", systemImage: "target") { editingGoals = true }
            }
            .sheet(isPresented: $editingGoals) { GoalsView() }
            .sheet(isPresented: $scanning) { ScanFoodView() }
            .sheet(isPresented: $scanningLabel) { ScanLabelView() }
            .sheet(isPresented: $photographingMeal) { MealPhotoView() }
            .refreshable { await reload() }
            .task(id: health.changeCount) { await reload() }
            // Loads that ran while the phone was locked (such as when iOS prewarms the app) failed, so retry on unlock.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                Task { await reload() }
            }
            // Totals roll over at midnight, so refresh whenever the app comes back.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reload() } }
            }
            .alert("Something Went Wrong", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var hydrationSection: some View {
        let water = Self.water
        if let option = health.unitOption(for: water) {
            let total = today(water, in: option)
            let goal = goals.goal(for: water, in: option) ?? 0
            Section("Water") {
                HStack(spacing: 20) {
                    ProgressRing(progress: goal > 0 ? total / goal : 0, tint: .cyan, systemImage: "drop.fill")
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.format(total))
                            .font(.title.bold().monospacedDigit())
                        Text("of \(option.format(goal))")
                            .foregroundStyle(.secondary)
                        GoalStatus(total: total, goal: goal, isLimit: false, option: option)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 8)
                NavigationLink("Log Water", value: water)
            }
        }
    }

    private var waterLogSection: some View {
        Section {
            ForEach(waterToday) { entry in
                NavigationLink(value: entry) {
                    HStack {
                        Text(entry.date, style: .time)
                        Spacer()
                        Text(entry.valueText).monospacedDigit()
                    }
                }
            }
            .onDelete { offsets in delete(offsets.map { waterToday[$0] }) }
        } header: {
            Text("Water Logged Today")
        } footer: {
            Text("Tap an entry to fix it, or swipe to remove it. Totals also include water other apps save to Health.")
        }
    }

    /// Today's food by meal, then the buttons to add more.
    @ViewBuilder
    private var foodSection: some View {
        ForEach(Meal.allCases) { meal in
            let entries = foodToday.filter { $0.meal == meal }
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.title)
                                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.valueText).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .logAgainActions(entry, in: health) { self.error = $0 }
                    }
                    .onDelete { offsets in delete(offsets.map { entries[$0] }) }
                } header: {
                    HStack {
                        Label(meal.title, systemImage: meal.systemImage)
                        Spacer()
                        Text(calories(of: entries)).monospacedDigit()
                    }
                }
            }
        }
        Section {
            NavigationLink {
                FoodLibraryView()
            } label: {
                Label("Add Food", systemImage: "plus.circle")
            }
            if MealPhoto.isAvailable {
                Button {
                    photographingMeal = true
                } label: {
                    Label("Photo of Meal", systemImage: "camera")
                }
            }
            Button {
                scanning = true
            } label: {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
            }
            Button {
                scanningLabel = true
            } label: {
                Label("Scan Nutrition Label", systemImage: "text.viewfinder")
            }
        } header: {
            if foodToday.isEmpty { Text("Food") }
        } footer: {
            if !foodToday.isEmpty {
                Text("Swipe left to remove a food (its nutrients are removed from Health too), or right to log it again.")
            }
        }
    }

    private func calories(of entries: [LoggedEntry]) -> String {
        let total = entries.compactMap(\.food?.calories).reduce(0, +)
        return "\(total.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    private func nutrientSection(_ title: String, metrics: [Metric]) -> some View {
        Section(title) {
            ForEach(metrics) { metric in
                if let option = health.unitOption(for: metric) {
                    NavigationLink(value: metric) {
                        NutrientRow(metric: metric, option: option, total: today(metric, in: option),
                                    goal: goals.goal(for: metric, in: option))
                    }
                }
            }
        }
    }

    private var trendSection: some View {
        Section("Last \(Self.trendDays) Days") {
            Picker("Show", selection: $trendMetric) {
                ForEach(Self.intake) { Text($0.name).tag($0) }
            }
            if let option = health.unitOption(for: trendMetric) {
                TrendChart(metric: trendMetric, option: option, days: totals[trendMetric] ?? [],
                           goal: goals.goal(for: trendMetric, in: option),
                           tint: trendMetric == Self.water ? .cyan : .accentColor)
            }
        }
    }

    // MARK: Data

    private func today(_ metric: Metric, in option: UnitOption) -> Double {
        totals[metric]?.last?.value(in: option) ?? 0
    }

    private func reload() async {
        do {
            var loaded: [Metric: [DailyTotal]] = [:]
            for metric in Self.intake {
                loaded[metric] = try await health.dailyTotals(for: metric, days: Self.trendDays)
            }
            totals = loaded
            let today = Calendar.current.startOfDay(for: .now)
            waterToday = try await health.recentEntries(of: [Self.water], includingFoods: false, since: today)
            foodToday = try await health.recentEntries(of: [], since: today)
        } catch where error.isHealthDataLocked {
            // Keep what's showing; this reloads once the phone is unlocked.
        } catch {
            self.error = error.healthMessage
        }
    }

    private func delete(_ toDelete: [LoggedEntry]) {
        Task {
            do {
                for entry in toDelete { try await health.delete(entry) }
            } catch {
                self.error = error.healthMessage
            }
        }
    }
}

// MARK: - Components

private struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let systemImage: String

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.headline.monospacedDigit())
            }
        }
        .animation(.easeOut, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress toward goal")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// "12 fl oz to go", "Goal reached", "5 g left" or "5 g over".
private struct GoalStatus: View {
    let total: Double
    let goal: Double
    let isLimit: Bool
    let option: UnitOption

    var body: some View {
        let difference = goal - total
        if isLimit {
            if difference >= 0 {
                Text("\(option.format(difference)) left").foregroundStyle(.secondary)
            } else {
                Label("\(option.format(-difference)) over", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else if difference > 0 {
            Text("\(option.format(difference)) to go").foregroundStyle(.secondary)
        } else {
            Label("Goal reached", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

private struct NutrientRow: View {
    let metric: Metric
    let option: UnitOption
    let total: Double
    let goal: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(metric.name, systemImage: metric.systemImage)
                Spacer()
                Group {
                    if let goal {
                        Text("\(option.formatNumber(total)) / \(option.format(goal))")
                    } else {
                        Text(option.format(total))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            if let goal, goal > 0, let dailyGoal = metric.dailyGoal {
                ProgressView(value: min(total, goal), total: goal)
                    .tint(dailyGoal.tint(forProgress: total / goal))
                GoalStatus(total: total, goal: goal, isLimit: dailyGoal.isLimit, option: option)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TrendChart: View {
    let metric: Metric
    let option: UnitOption
    let days: [DailyTotal]
    let goal: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let average {
                Text("Daily average: \(option.format(average))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value(metric.name, day.value(in: option)))
                        .foregroundStyle(tint)
                }
                if let goal {
                    RuleMark(y: .value(metric.dailyGoal?.isLimit == true ? "Limit" : "Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text(metric.dailyGoal?.isLimit == true ? "Limit" : "Goal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                }
            }
            .frame(height: 180)
        }
        .padding(.vertical, 8)
    }

    /// Average over the days that have anything logged, so a new user's empty week doesn't drag it down.
    private var average: Double? {
        let logged = days.filter { $0.sum != nil }.map { $0.value(in: option) }
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0, +) / Double(logged.count)
    }
}
