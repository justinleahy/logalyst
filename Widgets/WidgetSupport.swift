import HealthKit
import SwiftUI

/// Health data can't be read while the device is locked, so widgets fall back to what they last showed.
enum WidgetCache {
    static func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = AppGroup.defaults.data(forKey: cacheKey(key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        AppGroup.defaults.set(data, forKey: cacheKey(key))
    }

    private static func cacheKey(_ key: String) -> String { "widgetCache.\(key)" }
}

extension Date {
    /// When a widget should reload: in half an hour, or at midnight if sooner, so daily totals reset on time.
    static var nextWidgetRefresh: Date {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        return min(Date.now.addingTimeInterval(30 * 60), midnight)
    }
}

extension HealthStore {
    /// Keeps missing data distinct from zero and stores coverage alongside the numeric snapshot.
    func todayAmount(of metric: Metric, in option: UnitOption) async -> RecordedDailyAmount {
        let key = "recordedTotal.\(metric.id)"
        do {
            let day = try await dailyTotals(for: metric, days: 1).last
            let isToday = day.map { Calendar.current.isDateInToday($0.day) } ?? false
            let amount = RecordedDailyAmount(day: day?.day ?? .now, unitLabel: option.label,
                value: isToday && day?.hasRecordedData == true ? day?.value(in: option) : nil,
                missingIngredientCount: isToday ? (day?.missingIngredientCount ?? 0) : 0)
            WidgetCache.save(amount, key: key)
            return amount
        } catch {
            if var cached = WidgetCache.load(RecordedDailyAmount.self, key: key),
               cached.unitLabel == option.label, Calendar.current.isDateInToday(cached.day) {
                cached.isStale = true
                return cached
            }
            return RecordedDailyAmount(day: .now, unitLabel: option.label, value: nil, isStale: true)
        }
    }

    /// Today's total of an intake metric in the given unit, from every source in Health. While Health is
    /// locked, this is the last total a widget read (or zero once the day has rolled over).
    func todayTotal(of metric: Metric, in option: UnitOption) async -> Double {
        let key = "total.\(metric.id)"
        do {
            let total = try await dailyTotals(for: metric, days: 1).last?.value(in: option) ?? 0
            WidgetCache.save(DailyAmount(day: .now, unitLabel: option.label, value: total), key: key)
            return total
        } catch {
            guard let cached = WidgetCache.load(DailyAmount.self, key: key), cached.unitLabel == option.label else {
                return 0
            }
            return cached.todayValue
        }
    }
}

/// A day's total in a particular unit, cached by unit label so a unit change can't misread it.
struct DailyAmount: Codable, Hashable {
    var day: Date
    var unitLabel: String
    var value: Double

    /// The amount if it's for today, or zero once the day has rolled over.
    var todayValue: Double {
        Calendar.current.isDateInToday(day) ? value : 0
    }
}

extension View {
    /// Widgets don't pick up the global accent color on their own.
    func widgetTint() -> some View {
        tint(Color("AccentColor"))
    }

    /// Hides a health reading, or progress that reveals one, while the system hides sensitive widget data: on a
    /// locked iPhone or during Always On, as the user chose in Settings. Shows `placeholder` instead, such as the
    /// metric's symbol, so the widget still says what it's for. Labels like the metric's name stay visible.
    func healthPrivate(@ViewBuilder placeholder: () -> some View = { EmptyView() }) -> some View {
        modifier(HealthPrivate(placeholder: placeholder()))
    }
}

private struct HealthPrivate<Placeholder: View>: ViewModifier {
    let placeholder: Placeholder
    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        if redactionReasons.contains(.privacy) {
            placeholder
        } else {
            // Still marked, in case the system redacts without telling this view.
            content.privacySensitive()
        }
    }
}

/// A widget's recorded total, which may be absent, partial, or last read before Health became unavailable.
struct RecordedDailyAmount: Codable, Hashable {
    var day: Date
    var unitLabel: String
    var value: Double?
    var missingIngredientCount = 0
    var isStale = false

    var status: String {
        if value == nil { return "No data available" }
        if isStale { return missingIngredientCount > 0 ? "Last recorded · Partial" : "Last recorded" }
        if missingIngredientCount > 0 { return "Partial" }
        return "Recorded"
    }
}
