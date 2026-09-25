import HealthKit
import Observation
import UserNotifications

/// Which days a log reminder falls on, like a custom repeat in Calendar.
struct Recurrence: Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly, monthly

        var id: Self { self }

        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .monthly: "Monthly"
            }
        }

        /// The unit counted by `interval`, e.g. "2 weeks".
        func unit(_ count: Int) -> String {
            switch self {
            case .daily: count == 1 ? "day" : "days"
            case .weekly: count == 1 ? "week" : "weeks"
            case .monthly: count == 1 ? "month" : "months"
            }
        }
    }

    /// Week of the month for a monthly-by-weekday rule: 1–4, or -1 for the last.
    static let ordinals = [1, 2, 3, 4, -1]

    var frequency = Frequency.daily
    /// Every this many days, weeks or months.
    var interval = 1
    /// Weekly: the weekdays it falls on, 1 (Sunday) through 7.
    var weekdays: Set<Int>
    /// Monthly: whether it falls on a weekday of a given week (e.g. the last Friday) rather than on dates.
    var monthlyByWeekday = false
    /// Monthly: the dates it falls on, 1–31. A date past the end of a short month falls on its last day.
    var monthDays: Set<Int>
    var weekOrdinal = 1
    var monthWeekday: Int
    /// The first day it can fall on, which also anchors "every other" counts.
    var start: Date

    init(start: Date = .now) {
        let calendar = Calendar.current
        self.start = calendar.startOfDay(for: start)
        weekdays = [calendar.component(.weekday, from: start)]
        monthDays = [calendar.component(.day, from: start)]
        monthWeekday = calendar.component(.weekday, from: start)
    }

    /// Whether there's at least one day to fall on.
    var isValid: Bool {
        switch frequency {
        case .daily: true
        case .weekly: !weekdays.isEmpty
        case .monthly: monthlyByWeekday || !monthDays.isEmpty
        }
    }

    func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let first = calendar.startOfDay(for: start)
        guard day >= first else { return false }
        switch frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: first, to: day).day ?? 0
            return days % interval == 0
        case .weekly:
            guard weekdays.contains(calendar.component(.weekday, from: day)),
                  let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
                  let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return false }
            let weeks = calendar.dateComponents([.weekOfYear], from: firstWeek, to: week).weekOfYear ?? 0
            return weeks % interval == 0
        case .monthly:
            let from = calendar.dateComponents([.year, .month], from: first)
            let to = calendar.dateComponents([.year, .month], from: day)
            let months = (to.year! - from.year!) * 12 + (to.month! - from.month!)
            guard months % interval == 0 else { return false }
            let date = calendar.component(.day, from: day)
            let length = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
            if monthlyByWeekday {
                guard calendar.component(.weekday, from: day) == monthWeekday else { return false }
                return weekOrdinal == -1 ? date + 7 > length : (date - 1) / 7 + 1 == weekOrdinal
            }
            return monthDays.contains(date) || (date == length && monthDays.contains { $0 > length })
        }
    }

    /// E.g. "Every 2 weeks on Monday and Thursday" or "Monthly on the last Friday".
    var summary: String {
        let calendar = Calendar.current
        let every = interval == 1 ? nil : "Every \(interval) \(frequency.unit(interval))"
        switch frequency {
        case .daily:
            return every ?? "Every day"
        case .weekly:
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }.filter(weekdays.contains)
            let symbols = ordered.count > 2 ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
            return "\(every ?? "Weekly") on \(ordered.map { symbols[$0 - 1] }.formatted(.list(type: .and)))"
        case .monthly:
            let on = monthlyByWeekday
                ? "the \(Self.ordinalName(weekOrdinal)) \(calendar.weekdaySymbols[monthWeekday - 1])"
                : "the \(monthDays.sorted().map(Self.ordinalDate).formatted(.list(type: .and)))"
            return "\(every ?? "Monthly") on \(on)"
        }
    }

    static func ordinalName(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: "first"
        case 2: "second"
        case 3: "third"
        case 4: "fourth"
        default: "last"
        }
    }

    /// "1st", "22nd" and so on.
    static func ordinalDate(_ day: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: day as NSNumber) ?? "\(day)"
    }
}

/// A reminder to log one metric, either at set times or when it hasn't been logged for a while.
struct LogReminder: Codable, Identifiable, Hashable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// At each of `times` on the recurrence's days.
        case times
        /// Every `intervalMinutes` without a log, between the start and end times on the recurrence's days.
        case notLogged

        var id: Self { self }

        var title: String {
            switch self {
            case .times: "At Set Times"
            case .notLogged: "If Not Logged"
            }
        }
    }

    /// Choices for how long to wait without a log, in minutes.
    static let intervalChoices = [60, 90, 120, 180, 240, 360, 480, 720]

    var id = UUID()
    var metricID: String
    var isEnabled = true
    var mode = Mode.times
    var recurrence = Recurrence()
    /// Minutes after midnight of each reminder, in `times` mode.
    var times = [9 * 60]
    /// In `times` mode, whether to skip a reminder when the metric has already been logged shortly before it.
    var skipsIfLogged = true
    var intervalMinutes = 120
    /// Minutes after midnight of the first and last possible reminder each day, in `notLogged` mode.
    var startMinute = 9 * 60
    var endMinute = 21 * 60
    /// For metrics with a daily target, whether to stop for the day once it's reached.
    var stopsAtGoal = true
    /// Notification text in place of goal progress or when the metric was last logged. Blank for the default.
    var message = ""

    init(metric: Metric) {
        metricID = metric.id
        // A target like water's is reached a bit at a time, so remind whenever it's been a while.
        if metric.hasDailyTarget { mode = .notLogged }
    }

    var metric: Metric? { Metric.metric(id: metricID) }

    var isValid: Bool {
        recurrence.isValid && (mode == .notLogged || !times.isEmpty)
    }

    /// E.g. "Every day at 8:00 AM and 8:00 PM".
    var summary: String {
        switch mode {
        case .times:
            let times = times.sorted().map { todayAt($0).formatted(date: .omitted, time: .shortened) }
            return "\(recurrence.summary) at \(times.formatted(.list(type: .and)))"
        case .notLogged:
            return "\(recurrence.summary), after \(Self.formatInterval(intervalMinutes)) without logging"
        }
    }

    /// E.g. "1 hour, 30 minutes".
    static func formatInterval(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// When to remind after `now`, soonest first. `lastLog` is when the metric was last logged, and `goalMet` whether
    /// today's goal has been reached.
    func dates(after now: Date, lastLog: Date?, goalMet: Bool, limit: Int, horizon: Int = 400) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var dates: [Date] = []
        for offset in 0..<horizon where dates.count < limit {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), recurrence.includes(day) else { continue }
            if offset == 0 && stopsAtGoal && goalMet { continue }
            let loggedToday = lastLog.map { calendar.isDate($0, inSameDayAs: day) } ?? false
            switch mode {
            case .times:
                let times = times.sorted().compactMap { calendar.date(byAdding: .minute, value: $0, to: day) }
                for (index, time) in times.enumerated() where time > now {
                    // A log answers the reminder it's closest to, so one made just after an earlier reminder
                    // doesn't also skip the next. The first of the day is answered by anything since midnight.
                    let answeredSince = index == 0 ? day
                        : times[index - 1].addingTimeInterval(time.timeIntervalSince(times[index - 1]) / 2)
                    if skipsIfLogged, let lastLog, lastLog >= answeredSince { continue }
                    dates.append(time)
                }
            case .notLogged:
                guard let start = calendar.date(byAdding: .minute, value: startMinute, to: day),
                      let end = calendar.date(byAdding: .minute, value: endMinute, to: day) else { continue }
                let step = TimeInterval(intervalMinutes * 60)
                let first = loggedToday ? max(start, lastLog!.addingTimeInterval(step)) : start
                dates += stride(from: first, through: end, by: step).filter { $0 > now }
            }
        }
        return Array(dates.prefix(limit))
    }
}

// Missing fields fall back to their defaults, so reminders saved before a field was added still load.

extension Recurrence {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try container.decodeIfPresent(Date.self, forKey: .start) ?? .now)
        frequency = try container.decodeIfPresent(Frequency.self, forKey: .frequency) ?? frequency
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? interval
        weekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? weekdays
        monthlyByWeekday = try container.decodeIfPresent(Bool.self, forKey: .monthlyByWeekday) ?? monthlyByWeekday
        monthDays = try container.decodeIfPresent(Set<Int>.self, forKey: .monthDays) ?? monthDays
        weekOrdinal = try container.decodeIfPresent(Int.self, forKey: .weekOrdinal) ?? weekOrdinal
        monthWeekday = try container.decodeIfPresent(Int.self, forKey: .monthWeekday) ?? monthWeekday
    }
}

extension LogReminder {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricID = try container.decode(String.self, forKey: .metricID)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? id
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? mode
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? recurrence
        times = try container.decodeIfPresent([Int].self, forKey: .times) ?? times
        skipsIfLogged = try container.decodeIfPresent(Bool.self, forKey: .skipsIfLogged) ?? skipsIfLogged
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? intervalMinutes
        startMinute = try container.decodeIfPresent(Int.self, forKey: .startMinute) ?? startMinute
        endMinute = try container.decodeIfPresent(Int.self, forKey: .endMinute) ?? endMinute
        stopsAtGoal = try container.decodeIfPresent(Bool.self, forKey: .stopsAtGoal) ?? stopsAtGoal
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? message
    }
}

extension Metric {
    /// Whether the metric has a daily amount to reach, like water, rather than one to stay under.
    var hasDailyTarget: Bool {
        dailyGoal.map { !$0.isLimit } ?? false
    }
}

/// Today at a number of minutes after midnight, for reminder times.
func todayAt(_ minute: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minute, to: Calendar.current.startOfDay(for: .now)) ?? .now
}

/// Local reminders to log metrics, scheduled on the iPhone. iOS also shows them on the Watch while the phone is locked.
///
/// Health can't be read at delivery time, so reminders are scheduled ahead and rescheduled whenever a reminded metric
/// changes in Health (from any app or device), the app opens, a goal changes, or a reminder changes. Tapping one opens
/// the metric's log screen, and metrics with quick-log amounts get a button that logs one without opening the app.
@Observable
final class LogReminders: NSObject, UNUserNotificationCenterDelegate {
    private(set) var reminders: [LogReminder] = []
    /// True when the user turned notifications off for the app in Settings.
    private(set) var isDenied = false
    /// Set when the user taps a reminder, so the app can open to the metric.
    var openedLink: DeepLink?

    private nonisolated static let linkKey = "link"
    private nonisolated static let metricKey = "metric"
    private static let logActionID = "log"
    private static let idPrefix = "logReminder-"
    private static let remindersKey = "logReminders"
    /// Metrics with background delivery turned on, so it can be turned off once their last reminder goes.
    private static let deliveryKey = "logRemindersBackgroundDelivery"
    /// iOS keeps at most 64 pending notifications per app.
    private static let maxPending = 60

    private let health: HealthStore
    private let center = UNUserNotificationCenter.current()
    private let observerStore = HKHealthStore()
    private let defaults = UserDefaults.standard
    private var observers: [String: HKObserverQuery] = [:]
    private var scheduling: Task<Void, Never>?

    init(health: HealthStore) {
        self.health = health
        super.init()
        if let data = defaults.data(forKey: Self.remindersKey),
           let saved = try? JSONDecoder().decode([LogReminder].self, from: data) {
            reminders = saved
        }
        migrateWaterReminders()
        // Must be set before launch finishes, so a Log tap that launched the app in the background reaches us.
        center.delegate = self
        updateObservers()
    }

    /// Adds or replaces a reminder. Asks for notification permission first if it's on.
    func save(_ reminder: LogReminder) async {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
        } else {
            reminders.append(reminder)
        }
        if reminder.isEnabled {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        didChange()
    }

    func setEnabled(_ enabled: Bool, for reminder: LogReminder) async {
        var reminder = reminder
        reminder.isEnabled = enabled
        await save(reminder)
    }

    func delete(_ reminder: LogReminder) {
        reminders.removeAll { $0.id == reminder.id }
        didChange()
    }

    /// Reads the reminders again after iCloud brought newer ones from another iPhone, and schedules them.
    func reload() {
        guard let data = defaults.data(forKey: Self.remindersKey),
              let saved = try? JSONDecoder().decode([LogReminder].self, from: data), saved != reminders else { return }
        reminders = saved
        updateObservers()
        reschedule()
    }

    private func didChange() {
        if let data = try? JSONEncoder().encode(reminders) {
            defaults.set(data, forKey: Self.remindersKey)
        }
        updateObservers()
        reschedule()
    }

    private var activeMetrics: Set<Metric> {
        Set(reminders.filter { $0.isEnabled && $0.isValid }.compactMap(\.metric))
    }

    /// The amount a reminder's Log button logs: the metric's first quick-log amount. Nil for metrics without them,
    /// such as weight, where each reading differs.
    func quickLogAmount(for metric: Metric) -> (value: Double, option: UnitOption)? {
        guard let option = health.unitOption(for: metric),
              let value = health.presets(for: metric, in: option).first else { return nil }
        return (value, option)
    }

    /// Water reminders used to have their own settings. Turns them into a log reminder, once.
    private func migrateWaterReminders() {
        let enabledKey = "waterRemindersEnabled"
        let keys = [enabledKey, "waterRemindersInterval", "waterRemindersStart", "waterRemindersEnd",
                    "waterRemindersStopAtGoal", "waterRemindersServingAmount", "waterRemindersServingUnit"]
        guard defaults.object(forKey: enabledKey) != nil else { return }
        if defaults.bool(forKey: enabledKey) {
            var reminder = LogReminder(metric: .water)
            reminder.mode = .notLogged
            reminder.intervalMinutes = defaults.object(forKey: keys[1]) as? Int ?? 120
            reminder.startMinute = defaults.object(forKey: keys[2]) as? Int ?? 9 * 60
            reminder.endMinute = defaults.object(forKey: keys[3]) as? Int ?? 21 * 60
            reminder.stopsAtGoal = defaults.object(forKey: keys[4]) as? Bool ?? true
            reminders.append(reminder)
            if let data = try? JSONEncoder().encode(reminders) {
                defaults.set(data, forKey: Self.remindersKey)
            }
        }
        keys.forEach(defaults.removeObject)
        // The old reminders would come alongside the new ones.
        Task {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("waterReminder-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
        }
    }

    // MARK: Scheduling

    /// Today's progress toward a metric's daily target.
    private struct Progress {
        let total: Double
        let goal: Double
        let option: UnitOption

        var isMet: Bool { total >= goal }
    }

    /// Replaces the pending reminders with ones based on when each metric was last logged and today's progress.
    /// Runs after any earlier call finishes.
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
        let authorized = status == .authorized || status == .provisional
        let active = reminders.filter { $0.isEnabled && $0.isValid && $0.metric != nil }
        await setBackgroundDelivery(for: authorized ? activeMetrics : [])
        guard authorized, !active.isEmpty else {
            await removePending()
            return
        }
        var lastLogs: [String: Date] = [:]
        var progress: [String: Progress] = [:]
        do {
            for metric in activeMetrics {
                lastLogs[metric.id] = try await health.latestSample(of: metric)?.startDate
                if metric.hasDailyTarget, let option = health.unitOption(for: metric),
                   let goal = NutritionGoals().goal(for: metric, in: option) {
                    let total = try await health.dailyTotals(for: metric, days: 1).last?.value(in: option) ?? 0
                    progress[metric.id] = Progress(total: total, goal: goal, option: option)
                }
            }
        } catch {
            // Health can't be read while the phone is locked. Keep what's scheduled; this runs again on unlock.
            return
        }
        guard !Task.isCancelled else { return }

        registerLogButtons(for: activeMetrics)
        let now = Date.now
        let requests = active
            .flatMap { reminder in
                reminder.dates(after: now, lastLog: lastLogs[reminder.metricID],
                               goalMet: progress[reminder.metricID]?.isMet ?? false, limit: Self.maxPending)
                    .map { (reminder, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.maxPending)
            .map { request(for: $0, at: $1, lastLog: lastLogs[$0.metricID], progress: progress[$0.metricID]) }
        await removePending()
        for request in requests {
            try? await center.add(request)
        }
        // Reminders that came before the metric's latest log have been answered, so clear them from Notification Center.
        let answered = await center.deliveredNotifications().filter { notification in
            guard notification.request.identifier.hasPrefix(Self.idPrefix),
                  let metric = notification.request.content.userInfo[Self.metricKey] as? String,
                  let lastLog = lastLogs[metric] else { return false }
            return notification.date < lastLog
        }
        center.removeDeliveredNotifications(withIdentifiers: answered.map(\.request.identifier))
    }

    /// A category per metric with a quick-log amount, whose button says the amount it logs.
    private func registerLogButtons(for metrics: Set<Metric>) {
        let categories = metrics.compactMap { metric -> UNNotificationCategory? in
            guard let amount = quickLogAmount(for: metric) else { return nil }
            // Remembered so the button logs what it said, even if the amount changes before it's tapped.
            defaults.set(amount.value, forKey: servingKey(metric))
            defaults.set(amount.option.label, forKey: servingUnitKey(metric))
            let action = UNNotificationAction(
                identifier: Self.logActionID, title: "Log \(amount.option.format(amount.value))",
                // Health can't be written while the phone is locked.
                options: [.authenticationRequired], icon: UNNotificationActionIcon(systemImageName: metric.systemImage))
            return UNNotificationCategory(identifier: Self.idPrefix + metric.id, actions: [action], intentIdentifiers: [])
        }
        center.setNotificationCategories(Set(categories))
    }

    private func servingKey(_ metric: Metric) -> String { "logReminderServing-\(metric.id)" }
    private func servingUnitKey(_ metric: Metric) -> String { "logReminderServingUnit-\(metric.id)" }

    private func request(for reminder: LogReminder, at date: Date, lastLog: Date?,
                         progress: Progress?) -> UNNotificationRequest {
        let metric = reminder.metric!
        let content = UNMutableNotificationContent()
        content.title = "Time to Log \(metric.name)"
        content.body = message(for: reminder, at: date, lastLog: lastLog, progress: progress)
        content.sound = .default
        content.threadIdentifier = Self.idPrefix + metric.id
        if quickLogAmount(for: metric) != nil {
            content.categoryIdentifier = Self.idPrefix + metric.id
        }
        content.userInfo = [Self.linkKey: DeepLink.log(metric).url.absoluteString, Self.metricKey: metric.id]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: Self.idPrefix + "\(reminder.id)-\(Int(date.timeIntervalSince1970))",
                                     content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    /// Today's reminders for a daily target say how far there is to go; later days' can't know yet. Other metrics'
    /// say when they were last logged.
    private func message(for reminder: LogReminder, at date: Date, lastLog: Date?, progress: Progress?) -> String {
        let custom = reminder.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        if let progress {
            let goal = progress.option.format(progress.goal)
            guard Calendar.current.isDateInToday(date) else { return "Your goal today is \(goal)." }
            guard !progress.isMet else { return "You've reached today's \(goal) goal. Keep it up!" }
            return "\(progress.option.format(progress.goal - progress.total)) to go to reach your \(goal) goal."
        }
        if let lastLog {
            return "Last logged \(RelativeDateTimeFormatter().localizedString(for: lastLog, relativeTo: date))."
        }
        return "You haven't logged \(reminder.metric?.name ?? "it") yet."
    }

    private func removePending() async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: Health changes

    /// The type to watch for a metric's changes. Blood pressure is saved as a pair; watching one half is enough.
    private static func observedType(for metric: Metric) -> HKSampleType? {
        metric.sampleTypes.first
    }

    /// Reschedules when a reminded metric is logged or deleted anywhere, which can skip or push back its reminders.
    /// Background delivery wakes the app for this even when it isn't running. Must run on every launch, including
    /// background ones, so HealthKit has a query to deliver pending updates to.
    private func updateObservers() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let wanted = activeMetrics
        for (id, query) in observers where !wanted.contains(where: { $0.id == id }) {
            observerStore.stop(query)
            observers[id] = nil
        }
        for metric in wanted where observers[metric.id] == nil {
            guard let type = Self.observedType(for: metric) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { return completion() }
                // HealthKit's completion handler isn't marked Sendable, but it can be called from any thread. Calling
                // it only once rescheduling is done keeps a background launch alive long enough to finish.
                nonisolated(unsafe) let completion = completion
                Task { @MainActor in
                    await self?.reschedule().value
                    completion()
                }
            }
            observerStore.execute(query)
            observers[metric.id] = query
        }
    }

    private func setBackgroundDelivery(for metrics: Set<Metric>) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let previous = Set(defaults.stringArray(forKey: Self.deliveryKey) ?? [])
        let wanted = Set(metrics.map(\.id))
        for id in previous.subtracting(wanted) {
            guard let metric = Metric.metric(id: id), let type = Self.observedType(for: metric) else { continue }
            try? await observerStore.disableBackgroundDelivery(for: type)
        }
        for metric in metrics {
            guard let type = Self.observedType(for: metric) else { continue }
            try? await observerStore.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
        defaults.set(Array(wanted), forKey: Self.deliveryKey)
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
        let info = response.notification.request.content.userInfo
        let metricID = info[Self.metricKey] as? String
        let link = info[Self.linkKey] as? String
        let action = response.actionIdentifier
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in
            await respond(to: action, metricID: metricID, link: link)
            completionHandler()
        }
    }

    private func respond(to action: String, metricID: String?, link: String?) async {
        switch action {
        case Self.logActionID:
            if let metric = metricID.flatMap(Metric.metric(id:)) { await logServing(of: metric) }
        case UNNotificationDefaultActionIdentifier:
            openedLink = link.flatMap(URL.init(string:)).flatMap(DeepLink.init(url:))
        default:
            break
        }
    }

    /// Logs the amount the reminder's button showed.
    private func logServing(of metric: Metric) async {
        guard let label = defaults.string(forKey: servingUnitKey(metric)),
              let option = metric.unitOptions.first(where: { $0.label == label }) else { return }
        let amount = defaults.double(forKey: servingKey(metric))
        do {
            try await health.saveQuantity(metric, value: amount, option: option, date: .now)
        } catch {
            let content = UNMutableNotificationContent()
            content.title = "Couldn't Log \(metric.name)"
            content.body = error.healthMessage
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        await reschedule().value
    }
}
