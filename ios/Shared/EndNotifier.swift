import Foundation
import UserNotifications

protocol EndNotifying: AnyObject {
    func scheduleEndNotification(for session: BlockSession)
    func cancelEndNotification()
}

/// A local notification at the end time tells the person the block is over
/// (PLAN.md section 3). Its wording allows for the monitor having missed the end.
final class LocalEndNotifier: EndNotifying {
    static let identifier = "cmx.block.end"

    func scheduleEndNotification(for session: BlockSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        let interval = session.end.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your block is over"
        content.body = "Your apps unlock on their own. If one still shows the block screen, open ConcentrationMaxx once."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)) { error in
            if let error {
                DiagnosticsLog.shared()?.record(.app, "Could not schedule the end notification: \(error.localizedDescription)")
            }
        }
    }

    func cancelEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
