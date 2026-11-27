import XCTest

final class BlockSessionTests: XCTestCase {
    private func session(start: Date = referenceNow, minutes: Double) throws -> BlockSession {
        try BlockSession.make(now: start, duration: minutes * 60, messagingBlocked: false, strictMode: true, unlockEntries: 3)
    }

    func testDurationLimits() {
        XCTAssertThrowsError(try session(minutes: 14)) { XCTAssertEqual($0 as? BlockError, .durationTooShort) }
        XCTAssertNoThrow(try session(minutes: 15))
        XCTAssertNoThrow(try session(minutes: 24 * 60))
        XCTAssertThrowsError(try session(minutes: 24 * 60 + 1)) { XCTAssertEqual($0 as? BlockError, .durationTooLong) }
    }

    func testEndIsRoundedUpToTheNextWholeMinute() throws {
        let start = referenceNow.addingTimeInterval(12.4)           // 10:00:12.4
        let block = try session(start: start, minutes: 30)
        XCTAssertEqual(block.end, referenceNow.addingTimeInterval(31 * 60))    // 10:31:00
        XCTAssertEqual(block.start, start)

        let onTheMinute = try session(start: referenceNow, minutes: 30)
        XCTAssertEqual(onTheMinute.end, referenceNow.addingTimeInterval(30 * 60))
    }

    func testUnlockEntriesAreClampedToThreeToFive() throws {
        let low = try BlockSession.make(now: referenceNow, duration: 900, messagingBlocked: false, strictMode: false, unlockEntries: 1)
        let high = try BlockSession.make(now: referenceNow, duration: 900, messagingBlocked: false, strictMode: false, unlockEntries: 9)
        XCTAssertEqual(low.unlockEntries, 3)
        XCTAssertEqual(high.unlockEntries, 5)
    }

    func testExpiryAndRemaining() throws {
        let block = try session(minutes: 15)
        XCTAssertFalse(block.isExpired(at: referenceNow))
        XCTAssertFalse(block.isExpired(at: block.end.addingTimeInterval(-1)))
        XCTAssertTrue(block.isExpired(at: block.end))
        XCTAssertTrue(block.isExpired(at: block.end.addingTimeInterval(3600)))
        XCTAssertTrue(block.isExpired(at: block.end.addingTimeInterval(-30), tolerance: 60))
        XCTAssertFalse(block.isExpired(at: block.end.addingTimeInterval(-90), tolerance: 60))

        XCTAssertEqual(block.remaining(at: referenceNow), 15 * 60)
        XCTAssertEqual(block.remaining(at: block.end.addingTimeInterval(100)), 0)
    }

    func testExtendingMakesTheBlockLongerOnly() throws {
        let block = try session(minutes: 60)
        let extended = try block.extended(by: 30 * 60, now: referenceNow.addingTimeInterval(600))
        XCTAssertEqual(extended.end, block.end.addingTimeInterval(30 * 60))
        XCTAssertEqual(extended.id, block.id)
        XCTAssertEqual(extended.start, block.start)

        XCTAssertThrowsError(try block.extended(by: 0, now: referenceNow)) { XCTAssertEqual($0 as? BlockError, .cannotShorten) }
        XCTAssertThrowsError(try block.extended(by: -600, now: referenceNow)) { XCTAssertEqual($0 as? BlockError, .cannotShorten) }
    }

    func testCannotExtendPastTwentyFourHoursOrAfterTheEnd() throws {
        let block = try session(minutes: 23 * 60)
        XCTAssertNoThrow(try block.extended(by: 60 * 60, now: referenceNow))
        XCTAssertThrowsError(try block.extended(by: 61 * 60, now: referenceNow)) { XCTAssertEqual($0 as? BlockError, .wouldExceedMaximum) }
        XCTAssertEqual(block.availableExtensions(now: referenceNow), [15, 30, 60])

        XCTAssertThrowsError(try block.extended(by: 15 * 60, now: block.end)) { XCTAssertEqual($0 as? BlockError, .alreadyEnded) }
    }

    func testScheduleWindowUsesFullDatesAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 50, second: 0))!
        let block = try session(start: start, minutes: 30)

        let window = ScheduleWindow.dateComponents(for: block, calendar: calendar)
        XCTAssertEqual(window.start.day, 23)
        XCTAssertEqual(window.start.hour, 23)
        XCTAssertEqual(window.end.day, 24)
        XCTAssertEqual(window.end.hour, 0)
        XCTAssertEqual(window.end.minute, 20)
        XCTAssertEqual(calendar.date(from: window.start), block.start)
        XCTAssertEqual(calendar.date(from: window.end), block.end)
        // The interval is the whole session, so it is never under DeviceActivity's 15 minutes.
        XCTAssertGreaterThanOrEqual(block.end.timeIntervalSince(block.start), BlockRules.minimumDuration)
    }

    func testSeriousModeIsOffUnlessAskedForAndForcesStrictMode() throws {
        let ordinary = try BlockSession.make(now: referenceNow, duration: 900, messagingBlocked: false, strictMode: false, unlockEntries: 3)
        XCTAssertFalse(ordinary.seriousMode)
        XCTAssertFalse(ordinary.strictMode)

        let serious = try BlockSession.make(now: referenceNow, duration: 900, messagingBlocked: false, strictMode: false, seriousMode: true, unlockEntries: 3)
        XCTAssertTrue(serious.seriousMode)
        XCTAssertTrue(serious.strictMode)
        XCTAssertTrue(try serious.extended(by: 900, now: referenceNow).seriousMode)
    }

    func testSeriousRecordRoundTripsThroughJSON() throws {
        let block = try BlockSession.make(now: referenceNow, duration: 3600, messagingBlocked: true, strictMode: true, seriousMode: true, unlockEntries: 3)
        let decoded = try JSONDecoder().decode(BlockSession.self, from: JSONEncoder().encode(block))
        XCTAssertEqual(decoded, block)
        XCTAssertTrue(decoded.seriousMode)
    }

    func testRecordWrittenBeforeSeriousModeIsReadAsAnOrdinaryBlock() throws {
        // What the previous build saved: no "seriousMode" key. Dates are seconds since
        // 2001-01-01, JSONEncoder's default.
        let start = referenceNow.timeIntervalSinceReferenceDate
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","start":\(Int(start)),"end":\(Int(start) + 3600),\
        "messagingBlocked":true,"strictMode":false,"unlockEntries":4}
        """
        let decoded = try JSONDecoder().decode(BlockSession.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.seriousMode)
        XCTAssertEqual(decoded.start, referenceNow)
        XCTAssertEqual(decoded.end, referenceNow.addingTimeInterval(3600))
        XCTAssertTrue(decoded.messagingBlocked)
        XCTAssertFalse(decoded.strictMode)
        XCTAssertEqual(decoded.unlockEntries, 4)
    }

    func testRecordRoundTripsThroughJSON() throws {
        let block = try BlockSession.make(now: referenceNow.addingTimeInterval(0.25), duration: 3600, messagingBlocked: true, strictMode: false, unlockEntries: 4)
        let decoded = try JSONDecoder().decode(BlockSession.self, from: JSONEncoder().encode(block))
        XCTAssertEqual(decoded, block)
    }
}
