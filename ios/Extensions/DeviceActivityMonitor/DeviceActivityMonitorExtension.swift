import DeviceActivity
import ManagedSettings

/// Principal class of the DeviceActivityMonitor extension (see the NSExtension keys in
/// project.yml). The system calls it when a monitored interval starts or ends.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
