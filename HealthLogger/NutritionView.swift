import SwiftUI
import UIKit
import Charts

struct NutritionView: View {
    @Environment(HealthStore.self) private var health
    @Environment(NutritionGoals.self) private var goals
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Last `trendDays` of totals per metric, oldest first, so `.last` is today.
    @State private var totals: [Metric: [DailyTotal]] = [:]
    @State private var waterToday: [LoggedEntry] = []
    @State private var foodToday: [LoggedEntry] = []
    @State private var scanning = false
    @State private var scanningLabel = false
    @State private var photographingMeal = false
    @State private var composingMeal = false
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
                UnfinishedEditsSection { self.error = $0 }
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
                if let metric = entry.metric {
                    EntryView(metric: metric, editing: entry)
                } else if entry.food != nil {
                    LogFoodView(editing: entry)
                }
            }
            .toolbar {
                Button("Goals", systemImage: "target") { editingGoals = true }
            }
            .sheet(isPresented: $editingGoals) { GoalsView() }
            .sheet(isPresented: $scanning) { ScanFoodView() }
            .sheet(isPresented: $scanningLabel) { ScanLabelView() }
            .sheet(isPresented: $photographingMeal) { MealPhotoView() }
            .sheet(isPresented: $composingMeal) { NewMealView() }
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
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                    : AnyLayout(HStackLayout(spacing: 20))
                layout {
                    ProgressRing(progress: goal > 0 ? total / goal : 0, tint: .cyan, systemImage: "drop.fill",
                                 hasData: todayData(water)?.hasRecordedData == true)
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? 160 : 96,
                               height: dynamicTypeSize.isAccessibilitySize ? 160 : 96)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(todayData(water)?.hasRecordedData == true ? option.format(total) : "No recorded data available")
                            .font(.title.bold().monospacedDigit())
                            .fixedSize(horizontal: false, vertical: true)
                        Text("of \(option.format(goal))")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        GoalStatus(total: total, goal: goal, isLimit: false, option: option,
                                   hasData: todayData(water)?.hasRecordedData == true)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        NavigationLink(value: entry) {
                            foodRow(entry)
                        }
                        .logAgainActions(entry, in: health) { self.error = $0 }
                    }
                    .onDelete { offsets in delete(offsets.map { entries[$0] }) }
                } header: {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout())
                    layout {
                        Label(meal.title, systemImage: meal.systemImage)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Text(calories(of: entries))
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
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
            Button {
                composingMeal = true
            } label: {
                Label("New Meal", systemImage: "fork.knife.circle")
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
                Text("Tap a food to change it, swipe left to remove it (its nutrients are removed from Health too), "
                     + "or right to log it again.")
            }
        }
    }

    private func foodRow(_ entry: LoggedEntry) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
        return layout {
            VStack(alignment: .leading) {
                Text(entry.title).fixedSize(horizontal: false, vertical: true)
                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text(entry.valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calories(of entries: [LoggedEntry]) -> String {
        let foods = entries.compactMap(\.food)
        let coverage = FoodNutrition.coverage(of: "dietaryEnergyConsumed", in: foods)
        guard let total = FoodNutrition.totals(foods)["dietaryEnergyConsumed"] else { return "Calories unavailable" }
        let suffix = coverage.missing > 0 ? " · Partial" : (coverage.isUncertain ? " · Recorded" : "")
        return "\(total.formatted(.number.precision(.fractionLength(0)))) kcal\(suffix)"
    }

    private func nutrientSection(_ title: String, metrics: [Metric]) -> some View {
        Section {
            ForEach(metrics) { metric in
                if let option = health.unitOption(for: metric) {
                    NavigationLink(value: metric) {
                        NutrientRow(metric: metric, option: option, day: todayData(metric),
                                    goal: goals.goal(for: metric, in: option))
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Totals include available intake recorded in Health by all apps. Missing or unreadable data is not zero. A recorded total cannot establish that the day's intake is complete.")
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

    private func todayData(_ metric: Metric) -> DailyTotal? {
        totals[metric]?.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0 : nil }
    }

    private func today(_ metric: Metric, in option: UnitOption) -> Double {
        todayData(metric)?.value(in: option) ?? 0
    }

    private func reload() async {
        waterToday.removeAll { !Calendar.current.isDateInToday($0.date) }
        foodToday.removeAll { !Calendar.current.isDateInToday($0.date) }
        do {
            totals = try await health.dailyNutritionTotals(for: Self.intake, days: Self.trendDays)
            let today = Calendar.current.startOfDay(for: .now)
            waterToday = try await health.recentEntries(of: [Self.water], includingFoods: false, since: today)
            foodToday = try await health.recentEntries(of: [], since: today, limit: nil)
        } catch where error.isHealthDataLocked {
            // A failed query cannot establish today's intake. Retry when the phone unlocks.
            totals = [:]
        } catch {
            totals = [:]
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
    var hasData = true

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: hasData ? min(progress, 1) : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: systemImage).foregroundStyle(tint)
                Group {
                    if hasData {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                    } else {
                        Text("—")
                    }
                }
                    .font(.headline.monospacedDigit())
            }
        }
        .animation(.easeOut, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress toward goal")
        .accessibilityValue(hasData
            ? Text(progress, format: .percent.precision(.fractionLength(0)))
            : Text("Unavailable: no recorded data"))
    }
}

/// "12 fl oz to go", "Goal reached", "5 g left" or "5 g over".
private struct GoalStatus: View {
    let total: Double
    let goal: Double
    let isLimit: Bool
    let option: UnitOption
    var hasData = true
    var isPartial = false

    var body: some View {
        let difference = goal - total
        if !hasData {
            Text("Goal status unavailable").foregroundStyle(.secondary)
        } else if isPartial {
            Text("Partial total · goal status unavailable").foregroundStyle(.secondary)
        } else if isLimit {
            if difference >= 0 {
                Text("Recorded below limit · coverage may be incomplete").foregroundStyle(.secondary)
            } else {
                Label("\(option.format(-difference)) over", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        } else if difference > 0 {
            Text("\(option.format(difference)) to go").foregroundStyle(.secondary)
        } else {
            Label("Recorded goal reached", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

private struct NutrientRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: Metric
    let option: UnitOption
    let day: DailyTotal?
    let goal: Double?
    private var total: Double { day?.value(in: option) ?? 0 }
    private var hasData: Bool { day?.hasRecordedData == true }
    private var stacksAmount: Bool { dynamicTypeSize.isAccessibilitySize || !hasData }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = stacksAmount
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout())
            layout {
                Label(metric.name, systemImage: metric.systemImage)
                    .fixedSize(horizontal: false, vertical: true)
                if !stacksAmount { Spacer() }
                Group {
                    if !hasData {
                        Text("No recorded data available")
                    } else if let goal {
                        Text("\(option.formatNumber(total)) / \(option.format(goal))")
                    } else {
                        Text(option.format(total))
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let day, day.isPartial {
                Text("Partial · \(day.coverageText)").font(.caption).foregroundStyle(.secondary)
            }
            if let goal, goal > 0, let dailyGoal = metric.dailyGoal, hasData {
                ProgressView(value: min(total, goal), total: goal)
                    .tint(day?.isPartial == true || dailyGoal.isLimit ? .secondary : dailyGoal.tint(forProgress: total / goal))
                GoalStatus(total: total, goal: goal, isLimit: dailyGoal.isLimit, option: option,
                           hasData: hasData, isPartial: day?.isPartial == true)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Recorded daily average: \(option.format(average))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days.filter(\.hasRecordedData)) { day in
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value(metric.name, day.value(in: option)))
                        .foregroundStyle(day.isPartial ? tint.opacity(0.5) : tint)
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
            if days.contains(where: \.isPartial) {
                Text("Partial totals include only available nutrition.").font(.caption).foregroundStyle(.secondary)
            }
            if days.allSatisfy({ !$0.hasRecordedData }) {
                Text("No recorded data available").foregroundStyle(.secondary)
            }
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
