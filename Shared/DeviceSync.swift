import WatchConnectivity

/// Starred metric IDs plus when they last changed, so the newer copy wins when devices disagree.
struct FavoritesState: Sendable, Equatable {
    let ids: [String]
    let updated: Date
}

/// What the other device last sent. Each part is nil if it hasn't sent one.
struct RemoteState: Sendable {
    var favorites: FavoritesState?
    /// Daily goal amounts keyed by metric ID. Only the iPhone sends these, since goals are set there.
    var goals: [String: Double]?
    /// Edited presets keyed by metric ID then unit label. Only the iPhone sends these, since presets are edited there.
    var presets: [String: [String: [Double]]]?
}

/// Keeps favorites, goals and presets in step between the iPhone and Watch apps through the WatchConnectivity application
/// context, which always holds the latest state and is delivered even if the other app isn't running.
nonisolated final class DeviceSync: NSObject, WCSessionDelegate, Sendable {
    private static let idsKey = "favoriteIDs"
    private static let updatedKey = "favoritesUpdated"
    private static let goalsKey = "nutritionGoals"
    private static let presetsKey = "customPresets"

    /// Called with the other device's state after activation and on every update.
    private let onReceive: @MainActor @Sendable (RemoteState) -> Void

    init(onReceive: @escaping @MainActor @Sendable (RemoteState) -> Void) {
        self.onReceive = onReceive
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ state: FavoritesState) {
        update([Self.idsKey: state.ids, Self.updatedKey: state.updated])
    }

    func send(goals: [String: Double]) {
        update([Self.goalsKey: goals])
    }

    func send(presets: [String: [String: [Double]]]) {
        update([Self.presetsKey: presets])
    }

    /// Merges values into the context this device last sent. Each update replaces the whole context, so sending
    /// favorites alone would otherwise drop the goals and presets, and vice versa.
    private func update(_ values: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        let context = session.applicationContext.merging(values) { $1 }
        guard !(context as NSDictionary).isEqual(to: session.applicationContext) else { return }
        // Throws when the counterpart app isn't installed; it'll pick up the state on its next activation.
        try? session.updateApplicationContext(context)
    }

    private func deliver(_ context: [String: Any]) {
        var state = RemoteState(goals: context[Self.goalsKey] as? [String: Double],
                                presets: context[Self.presetsKey] as? [String: [String: [Double]]])
        if let ids = context[Self.idsKey] as? [String], let updated = context[Self.updatedKey] as? Date {
            state.favorites = FavoritesState(ids: ids, updated: updated)
        }
        Task { @MainActor [state] in onReceive(state) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        deliver(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        deliver(context)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Happens when the user switches to another watch; reactivate to talk to the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The Watch app may have just been installed, so offer it the current state.
    func sessionWatchStateDidChange(_ session: WCSession) {
        deliver(session.receivedApplicationContext)
    }
    #endif
}
