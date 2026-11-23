import XCTest

final class UnlockMachineTests: XCTestCase {
    private let start = referenceNow

    func testThreeCorrectEntriesInARowUnlock() {
        var machine = UnlockMachine(required: 3)
        XCTAssertEqual(machine.currentStep, 1)
        XCTAssertEqual(machine.record(correct: true, at: start), .progressed(completed: 1, required: 3))
        XCTAssertEqual(machine.currentStep, 2)
        XCTAssertEqual(machine.record(correct: true, at: start), .progressed(completed: 2, required: 3))
        XCTAssertEqual(machine.currentStep, 3)
        XCTAssertEqual(machine.record(correct: true, at: start), .unlocked)
        XCTAssertEqual(machine.currentStep, 1)
    }

    func testAWrongEntryGoesBackToStepOne() {
        var machine = UnlockMachine(required: 3)
        _ = machine.record(correct: true, at: start)
        _ = machine.record(correct: true, at: start)
        XCTAssertEqual(machine.record(correct: false, at: start), .wrong(failuresLeft: 4))
        XCTAssertEqual(machine.currentStep, 1)
        XCTAssertEqual(machine.guardState.failures, 1)
        // It takes three more correct entries, not one.
        XCTAssertEqual(machine.record(correct: true, at: start), .progressed(completed: 1, required: 3))
    }

    func testFiveWrongEntriesLockForFiveMinutes() {
        var machine = UnlockMachine(required: 3)
        for left in (1...4).reversed() {
            XCTAssertEqual(machine.record(correct: false, at: start), .wrong(failuresLeft: left))
        }
        let until = start.addingTimeInterval(UnlockMachine.lockoutDuration)
        XCTAssertEqual(machine.record(correct: false, at: start), .lockedOut(until: until))
        XCTAssertEqual(machine.lockoutEnd(at: start.addingTimeInterval(299)), until)

        // During the lockout the password is not even checked, and entries do not count.
        var checked = false
        let during = machine.submit(at: start.addingTimeInterval(120)) {
            checked = true
            return true
        }
        XCTAssertEqual(during, .lockedOut(until: until))
        XCTAssertFalse(checked)
        XCTAssertEqual(machine.record(correct: true, at: start.addingTimeInterval(200)), .lockedOut(until: until))

        // Afterwards the flow opens again with a fresh count.
        XCTAssertNil(machine.lockoutEnd(at: until))
        XCTAssertEqual(machine.record(correct: false, at: until), .wrong(failuresLeft: 4))
    }

    func testFailuresCountAcrossCorrectEntriesUntilAnUnlock() {
        var machine = UnlockMachine(required: 3)
        _ = machine.record(correct: false, at: start)
        _ = machine.record(correct: true, at: start)
        _ = machine.record(correct: false, at: start)
        XCTAssertEqual(machine.guardState.failures, 2)
        for _ in 0..<2 { _ = machine.record(correct: true, at: start) }
        XCTAssertEqual(machine.record(correct: true, at: start), .unlocked)
        XCTAssertEqual(machine.guardState, UnlockGuardState())
    }

    func testOneEntryForMessaging() {
        var machine = UnlockMachine(required: 1)
        XCTAssertEqual(machine.record(correct: true, at: start), .unlocked)
        XCTAssertEqual(UnlockMachine(required: 0).required, 1)
    }

    func testClosingTheScreenRestartsButKeepsFailures() {
        var machine = UnlockMachine(required: 3)
        _ = machine.record(correct: false, at: start)
        _ = machine.record(correct: true, at: start)
        machine.restart()
        XCTAssertEqual(machine.currentStep, 1)
        XCTAssertEqual(machine.guardState.failures, 1)
    }

    func testLockoutSurvivesRestartingTheApp() {
        let suite = "cmx.tests.unlock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UnlockGuardStore(defaults: defaults)
        XCTAssertEqual(store.load(), UnlockGuardState())

        var machine = UnlockMachine(required: 3, guardState: store.load())
        for _ in 0..<5 { _ = machine.record(correct: false, at: start) }
        store.save(machine.guardState)

        let reopened = UnlockMachine(required: 3, guardState: UnlockGuardStore(defaults: defaults).load())
        XCTAssertEqual(reopened.lockoutEnd(at: start.addingTimeInterval(60)), start.addingTimeInterval(UnlockMachine.lockoutDuration))
    }
}
