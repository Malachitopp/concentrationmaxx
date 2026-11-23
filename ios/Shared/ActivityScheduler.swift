import DeviceActivity
import Foundation

/// Names of the DeviceActivity activities that end blocks.
enum BlockActivity {
    static let prefix = "cmx.block."

    /// One name per session and end time, so a schedule left over from before an
    /// extension can never be mistaken for the current one.
    static func name(for session: BlockSession) -> DeviceActivityName {
        DeviceActivityName(prefix + session.id.uuidString + "." + String(Int(session.end.timeIntervalSince1970)))
    }

    static func isBlockActivity(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(prefix)
    }
}

protocol ActivityScheduling: AnyObject {
    /// Registers a non-repeating schedule that ends when the session ends, replacing
    /// any earlier block schedule.
    func scheduleEnd(for session: BlockSession) throws
    func cancelAll()
    func isScheduled(_ session: BlockSession) -> Bool
}

final class DeviceActivityScheduler: ActivityScheduling {
    func scheduleEnd(for session: BlockSession) throws {
        let center = DeviceActivityCenter()
        stopBlockActivities(in: center)
        let window = ScheduleWindow.dateComponents(for: session)
        let schedule = DeviceActivitySchedule(
            intervalStart: window.start,
            intervalEnd: window.end,
            repeats: false,
            warningTime: nil
        )
        do {
            try center.startMonitoring(BlockActivity.name(for: session), during: schedule)
        } catch let error as DeviceActivityCenter.MonitoringError {
            throw ScheduleError(error)
        }
    }

    func cancelAll() {
        stopBlockActivities(in: DeviceActivityCenter())
    }

    func isScheduled(_ session: BlockSession) -> Bool {
        DeviceActivityCenter().activities.contains(BlockActivity.name(for: session))
    }

    private func stopBlockActivities(in center: DeviceActivityCenter) {
        let ours = center.activities.filter(BlockActivity.isBlockActivity)
        if !ours.isEmpty {
            center.stopMonitoring(ours)
        }
    }
}

/// A readable wrapper around DeviceActivity's monitoring errors.
struct ScheduleError: Error, LocalizedError {
    let message: String

    init(_ error: DeviceActivityCenter.MonitoringError) {
        switch error {
        case .intervalTooShort:
            message = "iOS refused the schedule because it is shorter than 15 minutes."
        case .intervalTooLong:
            message = "iOS refused the schedule because it is too long."
        case .invalidDateComponents:
            message = "iOS refused the schedule's dates."
        case .excessiveActivities:
            message = "iOS refused the schedule because the app monitors too many activities."
        case .unauthorized:
            message = "iOS refused the schedule because Screen Time access is not granted."
        @unknown default:
            message = error.localizedDescription
        }
    }

    var errorDescription: String? { message }
}
