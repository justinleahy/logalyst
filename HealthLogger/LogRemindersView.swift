import SwiftUI
import UIKit

extension Binding<Int> {
    /// Minutes after midnight as a time today, for time pickers.
    var timeOfDay: Binding<Date> {
        Binding<Date> {
            todayAt(wrappedValue)
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// The list of log reminders, from Options.
struct LogRemindersView: View {
    @Environment(LogReminders.self) private var reminders
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case add
        case edit(LogReminder)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let reminder): reminder.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(reminders.reminders) { row(for: $0) }
                    .onDelete { offsets in
                        offsets.map { reminders.reminders[$0] }.forEach(reminders.delete)
                    }
            } footer: {
                if reminders.isDenied {
                    VStack(alignment: .leading) {
                        Text("Notifications are turned off for Logalyst.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .overlay {
            if reminders.reminders.isEmpty {
                ContentUnavailableView {
                    Label("No Reminders", systemImage: "bell")
                } description: {
                    Text("Add a reminder to log a metric at set times, or when you haven't logged it for a while.")
                } actions: {
                    Button("Add Reminder") { sheet = .add }
                }
            }
        }
        .navigationTitle("Log Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Add Reminder", systemImage: "plus") { sheet = .add }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .add:
                    MetricPicker(isRoot: true) { metric in
                        LogReminderEditor(draft: LogReminder(metric: metric), isNew: true) { self.sheet = nil }
                    }
                case .edit(let reminder):
                    LogReminderEditor(draft: reminder, isNew: false) { self.sheet = nil }
                }
            }
        }
    }

    private func row(for reminder: LogReminder) -> some View {
        let enabled = Binding {
            reminder.isEnabled
        } set: { on in
            Task { await reminders.setEnabled(on, for: reminder) }
        }
        return HStack {
            // Plain, so the toggle beside it gets its own taps.
            Button { sheet = .edit(reminder) } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text(reminder.metric?.name ?? "Unknown Metric")
                        Text(reminder.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: reminder.metric?.systemImage ?? "questionmark")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("Enabled", isOn: enabled)
                .labelsHidden()
        }
    }
}

/// A searchable list of the metrics that can have reminders.
private struct MetricPicker<Destination: View>: View {
    /// When it's the first screen of the add sheet, it has a Cancel button and pushes the editor.
    var isRoot = false
    @ViewBuilder var destination: (Metric) -> Destination
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            if search.isEmpty {
                ForEach(MetricCategory.allCases) { category in
                    Section {
                        ForEach(Metric.metrics(in: category)) { row(for: $0) }
                    } header: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            } else {
                ForEach(Metric.search(search)) { row(for: $0) }
            }
        }
        .searchable(text: $search, prompt: "Search Metrics")
        .navigationTitle("Choose Metric")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Metric.self) { destination($0) }
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(for metric: Metric) -> some View {
        NavigationLink(value: metric) {
            Label(metric.name, systemImage: metric.systemImage)
        }
    }
}

/// Settings for one reminder, saved together when Done is tapped.
private struct LogReminderEditor: View {
    @State var draft: LogReminder
    let isNew: Bool
    /// Closes the sheet, which may be several screens deep.
    let close: () -> Void
    @Environment(LogReminders.self) private var reminders

    var body: some View {
        Form {
            if !isNew {
                Section {
                    NavigationLink {
                        MetricChoice(metricID: $draft.metricID)
                    } label: {
                        LabeledContent("Metric", value: draft.metric?.name ?? "Unknown")
                    }
                }
            }
            remindSection
            repeatSection
            Section {
                TextField("Message", text: $draft.message, prompt: Text(defaultMessage), axis: .vertical)
            } header: {
                Text("Message")
            } footer: {
                Text("Shown in the notification. Leave it blank to show "
                     + (hasDailyTarget ? "how far you are from today's goal." : "when you last logged \(metricName)."))
            }
            if !isNew {
                Section {
                    Button("Delete Reminder", role: .destructive) {
                        if let saved = reminders.reminders.first(where: { $0.id == draft.id }) {
                            reminders.delete(saved)
                        }
                        close()
                    }
                }
            }
        }
        .navigationTitle(draft.metric?.name ?? "Reminder")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Done") {
                    var reminder = draft
                    reminder.times = Array(Set(reminder.times)).sorted()
                    Task { await reminders.save(reminder) }
                    close()
                }
                .disabled(!draft.isValid)
            }
        }
    }

    // MARK: Remind

    private var remindSection: some View {
        Section {
            Picker("Remind Me", selection: $draft.mode) {
                ForEach(LogReminder.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            switch draft.mode {
            case .times:
                ForEach(draft.times.indices, id: \.self) { index in
                    DatePicker("Time", selection: $draft.times[index].timeOfDay, displayedComponents: .hourAndMinute)
                }
                .onDelete { draft.times.remove(atOffsets: $0) }
                .deleteDisabled(draft.times.count == 1)
                Button("Add Time", systemImage: "plus") {
                    // An hour after the last one, wrapping past midnight.
                    draft.times.append(((draft.times.last ?? 8 * 60) + 60) % (24 * 60))
                }
                Toggle("Skip If Already Logged", isOn: $draft.skipsIfLogged)
            case .notLogged:
                Picker("Remind After", selection: $draft.intervalMinutes) {
                    ForEach(LogReminder.intervalChoices, id: \.self) { Text(LogReminder.formatInterval($0)) }
                }
                DatePicker("From", selection: startMinute.timeOfDay, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $draft.endMinute.timeOfDay,
                           in: todayAt(draft.startMinute)..., displayedComponents: .hourAndMinute)
            }
            if hasDailyTarget {
                Toggle("Stop When Goal Is Met", isOn: $draft.stopsAtGoal)
            }
        } header: {
            Text("Remind Me")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                switch draft.mode {
                case .times where draft.skipsIfLogged:
                    Text("A reminder is skipped if you've already logged \(metricName) since earlier that day, "
                         + "or since about halfway from the reminder before it.")
                case .times:
                    EmptyView()
                case .notLogged:
                    Text("Reminds you between these times whenever you haven't logged \(metricName) for this long, "
                         + "on the days below.")
                }
                if let metric = draft.metric, let amount = reminders.quickLogAmount(for: metric) {
                    Text("Touch and hold a reminder to log \(amount.option.format(amount.value)) without opening the app.")
                }
            }
        }
    }

    private var metricName: String {
        draft.metric?.name ?? "it"
    }

    private var hasDailyTarget: Bool {
        draft.metric?.hasDailyTarget ?? false
    }

    private var defaultMessage: String {
        hasDailyTarget ? "Progress toward today's goal" : "When it was last logged"
    }

    /// Keeps the end time from falling before the start.
    private var startMinute: Binding<Int> {
        Binding {
            draft.startMinute
        } set: { minute in
            draft.startMinute = minute
            if draft.endMinute < minute { draft.endMinute = minute }
        }
    }

    // MARK: Repeat

    private var repeatSection: some View {
        let recurrence = $draft.recurrence
        let frequency = draft.recurrence.frequency
        return Section {
            Picker("Frequency", selection: recurrence.frequency) {
                ForEach(Recurrence.Frequency.allCases) { Text($0.title).tag($0) }
            }
            Stepper(value: recurrence.interval, in: 1...maxInterval) {
                let count = draft.recurrence.interval
                Text(count == 1 ? "Every \(frequency.unit(1))" : "Every \(count) \(frequency.unit(count))")
            }
            switch frequency {
            case .daily:
                EmptyView()
            case .weekly:
                WeekdayPicker(selection: recurrence.weekdays)
            case .monthly:
                Picker("On", selection: recurrence.monthlyByWeekday) {
                    Text("Dates").tag(false)
                    Text("Weekday").tag(true)
                }
                .pickerStyle(.segmented)
                if draft.recurrence.monthlyByWeekday {
                    Picker("Week", selection: recurrence.weekOrdinal) {
                        ForEach(Recurrence.ordinals, id: \.self) { Text(Recurrence.ordinalName($0).capitalized) }
                    }
                    Picker("Day", selection: recurrence.monthWeekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]) }
                    }
                } else {
                    MonthDayPicker(selection: recurrence.monthDays)
                }
            }
            DatePicker("Starts", selection: recurrence.start, displayedComponents: .date)
        } header: {
            Text("Repeat")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.isValid ? "\(draft.summary)." : "Choose at least one day.")
                if frequency == .monthly && !draft.recurrence.monthlyByWeekday
                    && draft.recurrence.monthDays.contains(where: { $0 > 28 }) {
                    Text("In months without that date, it falls on the last day of the month.")
                }
            }
        }
        // Keeps the interval in range when switching to a larger unit.
        .onChange(of: frequency) { draft.recurrence.interval = min(draft.recurrence.interval, maxInterval) }
    }

    private var maxInterval: Int {
        switch draft.recurrence.frequency {
        case .daily: 365
        case .weekly: 52
        case .monthly: 12
        }
    }
}

/// Picks a different metric for an existing reminder.
private struct MetricChoice: View {
    @Binding var metricID: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            ForEach(metrics) { metric in
                Button {
                    metricID = metric.id
                    dismiss()
                } label: {
                    HStack {
                        Label(metric.name, systemImage: metric.systemImage)
                        Spacer()
                        if metric.id == metricID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $search, prompt: "Search Metrics")
        .navigationTitle("Choose Metric")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metrics: [Metric] {
        Metric.search(search)
    }
}

/// A row of circles for the days of the week, in the locale's order.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let calendar = Calendar.current
        HStack {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
                DayToggle(title: calendar.veryShortWeekdaySymbols[weekday - 1],
                          accessibilityName: calendar.weekdaySymbols[weekday - 1],
                          isOn: selection.contains(weekday)) {
                    selection.formSymmetricDifference([weekday])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A grid of the dates in a month.
private struct MonthDayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(1...31, id: \.self) { day in
                DayToggle(title: "\(day)", accessibilityName: Recurrence.ordinalDate(day),
                          isOn: selection.contains(day)) {
                    selection.formSymmetricDifference([day])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DayToggle: View {
    let title: String
    let accessibilityName: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .frame(width: 36, height: 36)
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .circle)
        }
        // Plain, so each circle in the row gets its own taps and keeps its colors.
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
