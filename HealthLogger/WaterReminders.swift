import HealthKit
import Observation
import UserNotifications

/// Local reminders to drink water, scheduled on the iPhone. iOS also shows them on the Watch while the phone is locked.
///
/// Reminders come every `interval` between the start and end times, counted from the last water logged today, so a
/// drink pushes the next one back. They stop for the day once the water goal is met, and each has a button that logs
/// a glass without opening the app. Health can't be read at delivery time, so the next few days are scheduled ahead
/// and rescheduled whenever water changes in Health (from any app or device), the app opens, or a setting changes.
@Observable
final class WaterReminders: NSObject, UNUserNotificationCenterDelegate {
    /// How often to remind, in minutes, for the settings picker.
    static let intervals = [60, 90, 120, 180, 240]

    var isEnabled: Bool {
        didSet { save(isEnabled, forKey: Keys.enabled) }
    }
    /// Minutes without water before a reminder.
    var interval: Int {
        didSet { save(interval, forKey: Keys.interval) }
    }
    /// Minutes after midnight of the first and last possible reminder each day.
    var startMinute: Int {
        didSet {
            if endMinute < startMinute { endMinute = startMinute }
            save(startMinute, forKey: Keys.start)
        }
    }
    var endMinute: Int {
        didSet { save(endMinute, forKey: Keys.end) }
    }
    var stopsAtGoal: Bool {
        didSet { save(stopsAtGoal, forKey: Keys.stopsAtGoal) }
    }
    /// True when the user turned notifications off for the app in Settings.
    private(set) var isDenied = false
    /// Set when the user taps a reminder, so the app can open to the Nutrition tab.
    var openedLink: DeepLink?

    private enum Keys {
        static let enabled = "waterRemindersEnabled"
        static let interval = "waterRemindersInterval"
        static let start = "waterRemindersStart"
        static let end = "waterRemindersEnd"
        static let stopsAtGoal = "waterRemindersStopAtGoal"
        /// The amount and unit on the Log button, so tapping it logs what the button said.
        static let servingAmount = "waterRemindersServingAmount"
        static let servingUnit = "waterRemindersServingUnit"
    }

    private nonisolated static let categoryID = "waterReminder"
    private static let logActionID = "logWater"
    private static let idPrefix = "waterReminder-"
    /// iOS keeps at most 64 pending notifications per app.
    private static let maxPending = 60
    private static let maxDays = 7

    private let health: HealthStore
    private let center = UNUserNotificationCenter.current()
    private let observerStore = HKHealthStore()
    private let defaults = UserDefaults.standard
    private var scheduling: Task<Void, Never>?

    init(health: HealthStore) {
        self.health = health
        isEnabled = defaults.bool(forKey: Keys.enabled)
        interval = defaults.object(forKey: Keys.interval) as? Int ?? 120
        startMinute = defaults.object(forKey: Keys.start) as? Int ?? 9 * 60
        endMinute = defaults.object(forKey: Keys.end) as? Int ?? 21 * 60
        stopsAtGoal = defaults.object(forKey: Keys.stopsAtGoal) as? Bool ?? true
        super.init()
        // Must be set before launch finishes, so a Log tap that launched the app in the background reaches us.
        center.delegate = self
        observeWater()
    }

    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        reschedule()
    }

    /// Turning reminders on asks for notification permission, and turns them back off if it's refused.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        guard enabled else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        if granted {
            // The reschedule from turning it on ran before permission was given.
            reschedule()
        } else {
            isEnabled = false
        }
    }

    // MARK: Scheduling

    /// Replaces the pending reminders with ones based on today's water. Runs after any earlier call finishes.
    @discardableResult
    func reschedule() -> Task<Void, Never> {
        let previous = scheduling
        previous?.cancel()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await schedule()
        }
        scheduling = task
        return task
    }

    private func schedule() async {
        let status = await center.notificationSettings().authorizationStatus
        isDenied = status == .denied
        guard isEnabled, status == .authorized || status == .provisional else {
            await removePending()
            await setBackgroundDelivery(false)
            return
        }
        await setBackgroundDelivery(true)
        let water = Metric.water
        guard let option = health.unitOption(for: water) else { return }
        let goal = NutritionGoals().goal(for: water, in: option)
        let total: Double
        let lastDrink: Date?
        do {
            total = try await health.dailyTotals(for: water, days: 1).last?.value(in: option) ?? 0
            lastDrink = try await health.latestSample(of: water)?.startDate
        } catch {
            // Health can't be read while the phone is locked. Keep what's scheduled; this runs again on unlock.
            return
        }
        guard !Task.isCancelled else { return }

        let serving = health.presets(for: water, in: option).first ?? option.defaultValue
        defaults.set(serving, forKey: Keys.servingAmount)
        defaults.set(option.label, forKey: Keys.servingUnit)
        let logAction = UNNotificationAction(
            identifier: Self.logActionID, title: "Log \(option.format(serving))",
            // Health can't be written while the phone is locked.
            options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: "drop.fill"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [logAction], intentIdentifiers: []),
        ])

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        let requests = reminderDates(total: total, goal: goal, lastDrink: lastDrink).map { date in
            let content = UNMutableNotificationContent()
            content.title = "Time for Some Water"
            content.body = message(isToday: date < tomorrow, total: total, goal: goal, option: option)
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = Self.categoryID
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return UNNotificationRequest(identifier: Self.idPrefix + "\(Int(date.timeIntervalSince1970))", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
        await removePending()
        for request in requests {
            try? await center.add(request)
        }
        // Reminders that came before the latest drink have been answered, so clear them from Notification Center.
        if let lastDrink {
            let answered = await center.deliveredNotifications()
                .filter { $0.request.identifier.hasPrefix(Self.idPrefix) && $0.date < lastDrink }
            center.removeDeliveredNotifications(withIdentifiers: answered.map(\.request.identifier))
        }
    }

    /// When to remind over the next few days: every `interval` from the start time, or from the last drink today.
    private func reminderDates(total: Double, goal: Double?, lastDrink: Date?) -> [Date] {
        let calendar = Calendar.current
        let now = Date.now
        let step = TimeInterval(interval * 60)
        var dates: [Date] = []
        for offset in 0..<Self.maxDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let start = calendar.date(byAdding: .minute, value: startMinute, to: day),
                  let end = calendar.date(byAdding: .minute, value: endMinute, to: day) else { continue }
            var first = start
            if offset == 0 {
                if stopsAtGoal, let goal, total >= goal { continue }
                if let lastDrink, calendar.isDate(lastDrink, inSameDayAs: now) {
                    first = max(start, lastDrink.addingTimeInterval(step))
                }
            }
            dates += stride(from: first, through: end, by: step).filter { $0 > now }
            if dates.count >= Self.maxPending { break }
        }
        return Array(dates.prefix(Self.maxPending))
    }

    /// Today's reminders say how far there is to go. Later days' can't know yet.
    private func message(isToday: Bool, total: Double, goal: Double?, option: UnitOption) -> String {
        guard let goal else { return "Remember to drink some water." }
        guard isToday else { return "Your goal today is \(option.format(goal))." }
        guard total < goal else { return "You've reached today's \(option.format(goal)) goal. Keep it up!" }
        return "\(option.format(goal - total)) to go to reach your \(option.format(goal)) goal."
    }

    private func removePending() async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: Health changes

    /// Reschedules when water is logged or deleted anywhere, which also pushes back the next reminder. Background
    /// delivery wakes the app for this even when it isn't running. Must run on every launch, including background
    /// ones, so HealthKit has a query to deliver pending updates to.
    private func observeWater() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: HKQuantityType(.dietaryWater), predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { return completion() }
            // HealthKit's completion handler isn't marked Sendable, but it can be called from any thread. Calling it
            // only once rescheduling is done keeps a background launch alive long enough to finish.
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in
                if let self, self.isEnabled { await self.reschedule().value }
                completion()
            }
        }
        observerStore.execute(query)
    }

    private func setBackgroundDelivery(_ enabled: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.dietaryWater)
        if enabled {
            try? await observerStore.enableBackgroundDelivery(for: type, frequency: .immediate)
        } else {
            try? await observerStore.disableBackgroundDelivery(for: type)
        }
    }

    // MARK: Responding

    // These use completion handlers, not the async versions: UIKit requires the handler to be called on the main
    // thread, and the async versions call it from a background thread once they return, which crashes.

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.notification.request.content.categoryIdentifier == Self.categoryID else { return completionHandler() }
        let action = response.actionIdentifier
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in
            await respond(to: action)
            completionHandler()
        }
    }

    private func respond(to action: String) async {
        switch action {
        case Self.logActionID:
            await logServing()
        case UNNotificationDefaultActionIdentifier:
            openedLink = .nutrition
        default:
            break
        }
    }

    /// Logs the amount the reminder's button showed.
    private func logServing() async {
        let water = Metric.water
        guard let label = defaults.string(forKey: Keys.servingUnit),
              let option = water.unitOptions.first(where: { $0.label == label }) else { return }
        let amount = defaults.double(forKey: Keys.servingAmount)
        do {
            try await health.saveQuantity(water, value: amount, option: option, date: .now)
        } catch {
            let content = UNMutableNotificationContent()
            content.title = "Couldn't Log Water"
            content.body = error.healthMessage
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        await reschedule().value
    }
}
