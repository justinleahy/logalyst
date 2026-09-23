import Foundation

enum AppGroup {
    static let id = "group.com.justinleahy.HealthLogger"

    /// Settings the widgets need to read (units, goals, favorites) live here rather than in standard defaults.
    static let defaults: UserDefaults = {
        guard let group = UserDefaults(suiteName: id) else { return .standard }
        // Earlier versions kept these in standard defaults; move them over once.
        let movedKeys = ["unitOverrides", "favoriteMetrics", "favoriteMetricsUpdated", "nutritionGoals"]
        for key in movedKeys {
            guard let value = UserDefaults.standard.object(forKey: key) else { continue }
            if group.object(forKey: key) == nil { group.set(value, forKey: key) }
            UserDefaults.standard.removeObject(forKey: key)
        }
        return group
    }()
}

/// URLs widgets use to open a particular screen in the app.
enum DeepLink: Equatable {
    case log(Metric)
    case nutrition

    private static let scheme = "healthlogger"

    var url: URL {
        switch self {
        case .log(let metric): URL(string: "\(Self.scheme)://log/\(metric.id)")!
        case .nutrition: URL(string: "\(Self.scheme)://nutrition")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host() {
        case "log":
            guard let metric = Metric.metric(id: url.lastPathComponent) else { return nil }
            self = .log(metric)
        case "nutrition":
            self = .nutrition
        default:
            return nil
        }
    }
}
