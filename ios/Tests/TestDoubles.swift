import FamilyControls
import Foundation

/// Records what the engine asks the shield layer to do.
final class FakeShields: ShieldApplying {
    enum Call: Equatable {
        case applySocial(hidingInstagram: Bool)
        case applyMessaging
        case clearMessaging
        case applyStrict(Bool)
        case clearAll
    }

    private(set) var calls: [Call] = []

    func applySocial(_ selection: FamilyActivitySelection, hidingInstagram instagram: FamilyActivitySelection?) {
        calls.append(.applySocial(hidingInstagram: instagram != nil))
    }

    func applyMessaging(_ selection: FamilyActivitySelection) {
        calls.append(.applyMessaging)
    }

    func clearMessaging() {
        calls.append(.clearMessaging)
    }

    func applyStrict(_ enabled: Bool) {
        calls.append(.applyStrict(enabled))
    }

    func clearAll() {
        calls.append(.clearAll)
    }

    func reset() {
        calls = []
    }
}

final class FakeScheduler: ActivityScheduling {
    var scheduled: [BlockSession] = []
    var cancelCount = 0
    var error: Error?
    var registered: BlockSession?

    func scheduleEnd(for session: BlockSession) throws {
        if let error { throw error }
        scheduled.append(session)
        registered = session
    }

    func cancelAll() {
        cancelCount += 1
        registered = nil
    }

    func isScheduled(_ session: BlockSession) -> Bool {
        registered == session
    }
}

final class FakeNotifier: EndNotifying {
    var scheduledEnds: [Date] = []
    var cancelCount = 0

    func scheduleEndNotification(for session: BlockSession) {
        scheduledEnds.append(session.end)
    }

    func cancelEndNotification() {
        cancelCount += 1
    }
}

final class FakeLog: DiagnosticsLogging {
    var entries: [(DiagnosticSource, String)] = []

    func record(_ source: DiagnosticSource, _ message: String) {
        entries.append((source, message))
    }
}

struct TestError: Error, LocalizedError, Equatable {
    var message = "test failure"
    var errorDescription: String? { message }
}

extension ShieldPlan {
    /// Real Screen Time tokens cannot be created in tests, so plans carry counts.
    static func testPlan(socialApps: Int = 3, messagingApps: Int = 2, hideInstagram: Bool = false) -> ShieldPlan {
        var plan = ShieldPlan(social: FamilyActivitySelection(),
                              messaging: FamilyActivitySelection(),
                              instagramHide: hideInstagram ? FamilyActivitySelection() : nil)
        plan.socialCount = SelectionCount(apps: socialApps, categories: 0, websites: 0)
        plan.messagingCount = SelectionCount(apps: messagingApps, categories: 0, websites: 0)
        return plan
    }
}

/// A fixed point in time: 2026-11-23 10:00:00 UTC.
let referenceNow = Date(timeIntervalSince1970: 1_795_428_000)
