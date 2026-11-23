import XCTest

final class BlockEngineTests: XCTestCase {
    private var sessions: InMemorySessionStore!
    private var shields: FakeShields!
    private var scheduler: FakeScheduler!
    private var notifier: FakeNotifier!
    private var log: FakeLog!
    private var now = referenceNow
    private var engine: BlockEngine!

    override func setUp() {
        super.setUp()
        sessions = InMemorySessionStore()
        shields = FakeShields()
        scheduler = FakeScheduler()
        notifier = FakeNotifier()
        log = FakeLog()
        now = referenceNow
        engine = BlockEngine(sessions: sessions, shields: shields, scheduler: scheduler,
                             notifier: notifier, log: log, now: { [unowned self] in self.now })
    }

    @discardableResult
    private func startHour(messaging: Bool = true, strict: Bool = true, plan: ShieldPlan = .testPlan()) throws -> BlockSession {
        try engine.start(duration: 3600, plan: plan, blockMessaging: messaging, strictMode: strict, unlockEntries: 3).session
    }

    // MARK: Starting

    func testStartAppliesShieldsThenSavesThenSchedules() throws {
        let session = try startHour()
        XCTAssertEqual(shields.calls, [.applySocial(hidingInstagram: false), .applyMessaging, .applyStrict(true)])
        XCTAssertEqual(sessions.session, session)
        XCTAssertEqual(scheduler.scheduled, [session])
        XCTAssertEqual(notifier.scheduledEnds, [session.end])
        XCTAssertTrue(session.messagingBlocked)
        XCTAssertTrue(session.strictMode)
        XCTAssertEqual(session.end, referenceNow.addingTimeInterval(3600))
    }

    func testStartWithoutMessagingClearsTheMessagingStore() throws {
        let session = try startHour(messaging: false, strict: false)
        XCTAssertFalse(session.messagingBlocked)
        XCTAssertEqual(shields.calls, [.applySocial(hidingInstagram: false), .clearMessaging, .applyStrict(false)])
    }

    func testMessagingSwitchIsIgnoredWhenNoMessagingAppsArePicked() throws {
        let session = try startHour(messaging: true, plan: .testPlan(messagingApps: 0))
        XCTAssertFalse(session.messagingBlocked)
        XCTAssertTrue(shields.calls.contains(.clearMessaging))
    }

    func testHideStrategyIsPassedToTheShields() throws {
        try startHour(plan: .testPlan(hideInstagram: true))
        XCTAssertEqual(shields.calls.first, .applySocial(hidingInstagram: true))
    }

    func testCannotStartWithNothingPickedOrTooManyApps() {
        XCTAssertThrowsError(try startHour(plan: .testPlan(socialApps: 0))) {
            XCTAssertEqual($0 as? BlockError, .nothingToBlock)
        }
        XCTAssertThrowsError(try startHour(plan: .testPlan(socialApps: 51))) {
            XCTAssertEqual($0 as? BlockError, .tooManyApps(51))
        }
        XCTAssertTrue(shields.calls.isEmpty)
        XCTAssertNil(sessions.session)
    }

    func testCannotStartWhileABlockIsRunning() throws {
        try startHour()
        shields.reset()
        XCTAssertThrowsError(try startHour()) { XCTAssertEqual($0 as? BlockError, .alreadyRunning) }
        XCTAssertTrue(shields.calls.isEmpty)
    }

    func testAnExpiredRecordDoesNotPreventANewBlock() throws {
        let first = try startHour()
        now = first.end.addingTimeInterval(5)
        let second = try startHour()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(sessions.session, second)
    }

    func testStartIsUndoneWhenTheRecordCannotBeSaved() {
        sessions.saveError = TestError()
        XCTAssertThrowsError(try startHour()) { error in
            guard case .storageUnavailable? = error as? BlockError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(shields.calls.last, .clearAll)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testScheduleFailureLeavesTheBlockRunningWithAWarning() throws {
        scheduler.error = TestError(message: "refused")
        let outcome = try engine.start(duration: 3600, plan: .testPlan(), blockMessaging: false, strictMode: true, unlockEntries: 3)
        XCTAssertEqual(sessions.session, outcome.session)
        XCTAssertEqual(outcome.warnings.count, 1)
        XCTAssertFalse(shields.calls.contains(.clearAll))
    }

    // MARK: Extending and unblocking messaging

    func testExtendSavesReschedulesAndRenotifies() throws {
        let session = try startHour()
        now = referenceNow.addingTimeInterval(1200)
        let outcome = try engine.extend(byMinutes: 30)
        XCTAssertEqual(outcome.session.end, session.end.addingTimeInterval(1800))
        XCTAssertEqual(sessions.session, outcome.session)
        XCTAssertEqual(scheduler.scheduled.last, outcome.session)
        XCTAssertEqual(notifier.scheduledEnds.last, outcome.session.end)
    }

    func testExtendFailsWhenNoBlockIsRunning() throws {
        XCTAssertThrowsError(try engine.extend(byMinutes: 15)) { XCTAssertEqual($0 as? BlockError, .notRunning) }
        let session = try startHour()
        now = session.end
        XCTAssertThrowsError(try engine.extend(byMinutes: 15)) { XCTAssertEqual($0 as? BlockError, .notRunning) }
    }

    func testUnblockMessagingClearsOnlyTheMessagingStore() throws {
        try startHour()
        shields.reset()
        let updated = try engine.unblockMessaging()
        XCTAssertFalse(updated.messagingBlocked)
        XCTAssertEqual(sessions.session?.messagingBlocked, false)
        XCTAssertEqual(shields.calls, [.clearMessaging])
        XCTAssertThrowsError(try engine.unblockMessaging()) { XCTAssertEqual($0 as? BlockError, .messagingNotBlocked) }
    }

    func testUnblockMessagingKeepsShieldsWhenTheRecordCannotBeSaved() throws {
        try startHour()
        shields.reset()
        sessions.saveError = TestError()
        XCTAssertThrowsError(try engine.unblockMessaging())
        XCTAssertTrue(shields.calls.isEmpty)
    }

    // MARK: Ending

    func testEndNowLiftsEverything() throws {
        try startHour()
        shields.reset()
        try engine.endNow(source: .endedEarly)
        XCTAssertNil(sessions.session)
        XCTAssertEqual(shields.calls, [.clearAll])
        XCTAssertEqual(scheduler.cancelCount, 1)
        XCTAssertEqual(notifier.cancelCount, 1)
    }

    func testEndIfExpiredLeavesARunningBlockAlone() throws {
        let session = try startHour()
        shields.reset()
        now = session.end.addingTimeInterval(-120)
        XCTAssertEqual(engine.endIfExpired(source: .monitor, tolerance: BlockRules.monitorEndTolerance), .running(session))
        XCTAssertTrue(shields.calls.isEmpty)
        XCTAssertNotNil(sessions.session)
    }

    func testMonitorCallbackShortlyBeforeTheEndStillEndsTheBlock() throws {
        let session = try startHour()
        shields.reset()
        now = session.end.addingTimeInterval(-30)
        XCTAssertEqual(engine.endIfExpired(source: .monitor, tolerance: BlockRules.monitorEndTolerance), .ended(session))
        XCTAssertEqual(shields.calls, [.clearAll])
        XCTAssertNil(sessions.session)
        // The end notification still fires at the end time.
        XCTAssertEqual(notifier.cancelCount, 0)
    }

    func testEachEndPathLiftsAnExpiredBlock() throws {
        for source in [EndSource.monitor, .app, .shieldAction] {
            setUp()
            let session = try startHour()
            shields.reset()
            now = session.end.addingTimeInterval(1)
            XCTAssertEqual(engine.endIfExpired(source: source), .ended(session), "\(source)")
            XCTAssertEqual(shields.calls, [.clearAll], "\(source)")
            XCTAssertNil(sessions.session, "\(source)")
            XCTAssertEqual(scheduler.cancelCount, 1, "\(source)")
        }
    }

    func testUnreadableRecordIsNeverTreatedAsNoBlock() throws {
        try startHour()
        shields.reset()
        sessions.loadError = TestError(message: "corrupt")
        now = referenceNow.addingTimeInterval(7200)
        XCTAssertEqual(engine.endIfExpired(source: .monitor), .unreadable("corrupt"))
        XCTAssertTrue(shields.calls.isEmpty)
        XCTAssertEqual(engine.reconcile(plan: .testPlan()), .unreadable("corrupt"))
        XCTAssertTrue(shields.calls.isEmpty)
    }

    func testRecordThatCannotBeRemovedKeepsTheShields() throws {
        let session = try startHour()
        shields.reset()
        sessions.clearError = TestError(message: "locked")
        now = session.end.addingTimeInterval(1)
        XCTAssertEqual(engine.endIfExpired(source: .monitor), .unreadable("locked"))
        XCTAssertTrue(shields.calls.isEmpty)
    }

    // MARK: Foreground reconciliation (end path 2)

    func testReconcileWithNoBlockClearsLeftoverShields() {
        XCTAssertEqual(engine.reconcile(plan: .testPlan()), .noSession)
        XCTAssertEqual(shields.calls, [.clearAll])
    }

    func testReconcileReappliesARunningBlockAndItsSchedule() throws {
        let session = try startHour()
        shields.reset()
        scheduler.registered = nil
        XCTAssertEqual(engine.reconcile(plan: .testPlan()), .running(session))
        XCTAssertEqual(shields.calls, [.applySocial(hidingInstagram: false), .applyMessaging, .applyStrict(true)])
        XCTAssertEqual(scheduler.registered, session)
    }

    func testReconcileRespectsUnblockedMessaging() throws {
        try startHour()
        _ = try engine.unblockMessaging()
        shields.reset()
        _ = engine.reconcile(plan: .testPlan())
        XCTAssertEqual(shields.calls, [.applySocial(hidingInstagram: false), .clearMessaging, .applyStrict(true)])
    }

    func testReconcileNeverClearsShieldsBecauseAListIsUnreadable() throws {
        try startHour()
        shields.reset()
        _ = engine.reconcile(plan: .testPlan(socialApps: 0, messagingApps: 0))
        XCTAssertEqual(shields.calls, [.applyStrict(true)])
    }

    func testReconcileEndsAnExpiredBlock() throws {
        let session = try startHour()
        shields.reset()
        now = session.end.addingTimeInterval(60)
        XCTAssertEqual(engine.reconcile(plan: .testPlan()), .ended(session))
        XCTAssertEqual(shields.calls, [.clearAll])
    }
}
