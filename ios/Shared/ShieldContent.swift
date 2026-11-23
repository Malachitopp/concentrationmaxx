import Foundation

/// The words on the shield that covers a blocked app or website. Kept apart from the
/// ShieldConfiguration extension so it can be unit tested.
struct ShieldText: Equatable {
    var title: String
    var subtitle: String
    var primaryButton: String
}

enum ShieldContent {
    /// Why this item is shielded.
    enum Group {
        case social
        /// Only shielded through the messaging list, which one password entry lifts.
        case messaging
    }

    static func text(session: BlockSession?,
                     group: Group,
                     itemName: String?,
                     now: Date,
                     calendar: Calendar = .current,
                     locale: Locale = .current) -> ShieldText {
        guard let session else {
            return ShieldText(
                title: "Blocked by ConcentrationMaxx",
                subtitle: "Open ConcentrationMaxx to check on this block.",
                primaryButton: "Close"
            )
        }
        if session.isExpired(at: now) {
            return ShieldText(
                title: "Your block is over",
                subtitle: "Tap Unblock to remove this screen. Opening ConcentrationMaxx lifts it too.",
                primaryButton: "Unblock"
            )
        }
        let until = endDescription(session.end, now: now, calendar: calendar, locale: locale)
        switch group {
        case .messaging where session.messagingBlocked:
            return ShieldText(
                title: "Messaging blocked until \(until)",
                subtitle: "To unblock messaging apps, open ConcentrationMaxx and enter your password once.",
                primaryButton: "Close"
            )
        default:
            let name = itemName.flatMap { $0.isEmpty ? nil : $0 } ?? "This app"
            let times = session.unlockEntries == 1 ? "once" : "\(session.unlockEntries) times"
            return ShieldText(
                title: "Blocked until \(until)",
                subtitle: "\(name) stays closed while your block runs. To end it early, open ConcentrationMaxx and enter your password \(times).",
                primaryButton: "Close"
            )
        }
    }

    /// "17:30" today, "tomorrow 09:00" tomorrow, otherwise weekday and time.
    static func endDescription(_ end: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let clock = time.string(from: end)

        if calendar.isDate(end, inSameDayAs: now) {
            return clock
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(end, inSameDayAs: tomorrow) {
            return "tomorrow \(clock)"
        }
        let weekday = DateFormatter()
        weekday.locale = locale
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.setLocalizedDateFormatFromTemplate("EEE")
        return "\(weekday.string(from: end)) \(clock)"
    }
}
