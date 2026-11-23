import XCTest

final class ShieldContentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let locale = Locale(identifier: "en_GB")

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func session(endingAt end: Date, messaging: Bool = false, entries: Int = 3) -> BlockSession {
        BlockSession(id: UUID(), start: end.addingTimeInterval(-3600), end: end,
                     messagingBlocked: messaging, strictMode: true, unlockEntries: entries)
    }

    private func text(_ session: BlockSession?, group: ShieldContent.Group = .social, name: String? = "Instagram", now: Date) -> ShieldText {
        ShieldContent.text(session: session, group: group, itemName: name, now: now, calendar: calendar, locale: locale)
    }

    func testRunningBlockShowsTheEndTimeAndTheWayOut() {
        let shield = text(session(endingAt: date(23, 17, 30)), now: date(23, 16, 45))
        XCTAssertEqual(shield.title, "Blocked until 17:30")
        XCTAssertTrue(shield.subtitle.contains("Instagram"))
        XCTAssertTrue(shield.subtitle.contains("3 times"))
        XCTAssertEqual(shield.primaryButton, "Close")
    }

    func testEndTomorrowAndLater() {
        XCTAssertEqual(ShieldContent.endDescription(date(24, 9, 0), now: date(23, 22, 0), calendar: calendar, locale: locale),
                       "tomorrow 09:00")
        XCTAssertEqual(ShieldContent.endDescription(date(25, 9, 0), now: date(23, 22, 0), calendar: calendar, locale: locale),
                       "Wed 09:00")
    }

    func testMessagingShieldOffersOnePasswordEntry() {
        let shield = text(session(endingAt: date(23, 17, 30), messaging: true), group: .messaging, now: date(23, 17, 0))
        XCTAssertEqual(shield.title, "Messaging blocked until 17:30")
        XCTAssertTrue(shield.subtitle.contains("once"))
    }

    func testMessagingItemAfterMessagingWasUnblockedFallsBackToTheSocialText() {
        let shield = text(session(endingAt: date(23, 17, 30), messaging: false), group: .messaging, now: date(23, 17, 0))
        XCTAssertEqual(shield.title, "Blocked until 17:30")
    }

    func testExpiredBlockOffersToUnblock() {
        let shield = text(session(endingAt: date(23, 17, 30)), now: date(23, 17, 31))
        XCTAssertEqual(shield.title, "Your block is over")
        XCTAssertEqual(shield.primaryButton, "Unblock")
    }

    func testMissingRecordAndMissingName() {
        XCTAssertEqual(text(nil, now: date(23, 12, 0)).title, "Blocked by ConcentrationMaxx")
        let unnamed = text(session(endingAt: date(23, 17, 30)), name: nil, now: date(23, 12, 0))
        XCTAssertTrue(unnamed.subtitle.hasPrefix("This app"))
    }
}
