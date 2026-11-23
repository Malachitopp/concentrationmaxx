import DeviceActivity
import Foundation

/// Principal class of the DeviceActivityMonitor extension (see the NSExtension keys in
/// project.yml). The system calls it when a monitored interval starts or ends, even
/// when the app is not running. This is end path 1 of 3 (PLAN.md section 3).
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard BlockActivity.isBlockActivity(activity) else { return }
        // The schedule starts at the block's start, which is already in the past when
        // the app registers it, so this arrives right away. Nothing to do: the app
        // applied the shields itself.
        DiagnosticsLog.shared()?.record(.monitor, "Interval started")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard BlockActivity.isBlockActivity(activity) else { return }
        let log = DiagnosticsLog.shared()
        do {
            let engine = try BlockEngine.live(notifier: nil, log: log)
            // The schedule works in whole minutes, so allow a slightly early callback.
            // The engine only lifts the block once the saved end time has passed.
            engine.endIfExpired(source: .monitor, tolerance: BlockRules.monitorEndTolerance)
        } catch {
            log?.record(.monitor, "Interval ended but shared storage is unavailable: \(error.localizedDescription)")
        }
    }
}
