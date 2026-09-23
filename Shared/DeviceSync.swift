import WatchConnectivity

/// Starred metric IDs plus when they last changed, so the newer copy wins when devices disagree.
struct FavoritesState: Sendable, Equatable {
    let ids: [String]
    let updated: Date
}

/// Keeps favorites in step between the iPhone and Watch apps through the WatchConnectivity application
/// context, which always holds the latest state and is delivered even if the other app isn't running.
nonisolated final class DeviceSync: NSObject, WCSessionDelegate, Sendable {
    private static let idsKey = "favoriteIDs"
    private static let updatedKey = "favoritesUpdated"

    /// Called with the other device's state (nil if it hasn't sent any) after activation and on every update.
    private let onReceive: @MainActor @Sendable (FavoritesState?) -> Void

    init(onReceive: @escaping @MainActor @Sendable (FavoritesState?) -> Void) {
        self.onReceive = onReceive
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ state: FavoritesState) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        // Throws when the counterpart app isn't installed; it'll pick up the state on its next activation.
        try? session.updateApplicationContext([Self.idsKey: state.ids, Self.updatedKey: state.updated])
    }

    private func deliver(_ context: [String: Any]) {
        let state: FavoritesState? = if let ids = context[Self.idsKey] as? [String],
                                        let updated = context[Self.updatedKey] as? Date {
            FavoritesState(ids: ids, updated: updated)
        } else {
            nil
        }
        Task { @MainActor in onReceive(state) }
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
