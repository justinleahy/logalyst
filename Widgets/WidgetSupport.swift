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
}
