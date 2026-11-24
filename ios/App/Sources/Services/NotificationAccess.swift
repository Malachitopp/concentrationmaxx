import Foundation
import UserNotifications

/// Permission for the "your block is over" notification (PLAN.md section 3).
@MainActor
final class NotificationAccess: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    var isAllowed: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var statusDescription: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Off (turn on in iOS Settings)"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func request() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            DiagnosticsLog.shared()?.record(.app, "Notification permission request failed: \(error.localizedDescription)")
        }
        await refresh()
    }
}
