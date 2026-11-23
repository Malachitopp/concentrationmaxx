import ManagedSettings

/// Principal class of the ShieldAction extension: handles taps on the shield's button.
/// If the block is already over (the monitor missed the end), the tap lifts it. This
/// is end path 3 of 3 (PLAN.md section 3).
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(respond(to: action))
    }

    private func respond(to action: ShieldAction) -> ShieldActionResponse {
        guard action == .primaryButtonPressed else { return .close }
        let log = DiagnosticsLog.shared()
        do {
            let engine = try BlockEngine.live(notifier: nil, log: log)
            switch engine.endIfExpired(source: .shieldAction) {
            case .ended:
                // The shields are gone; .defer makes the system look again, which
                // removes the shield and leaves the app open.
                return .defer
            case .running, .noSession, .unreadable:
                // A shield without a block record is left for the app to clear when it
                // is next opened: stay blocked rather than guess.
                return .close
            }
        } catch {
            log?.record(.shieldAction, "Shared storage is unavailable: \(error.localizedDescription)")
            return .close
        }
    }
}
