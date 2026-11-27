import Foundation

/// Who ended a block, for the diagnostics log.
enum EndSource: String {
    case monitor = "monitor extension (interval ended)"
    case app = "app (foreground check)"
    case shieldAction = "shield button"
    case endedEarly = "ended early with the password"

    var diagnosticSource: DiagnosticSource {
        switch self {
        case .monitor: return .monitor
        case .shieldAction: return .shieldAction
        case .app, .endedEarly: return .app
        }
    }
}

/// The result of checking whether the current block has run out.
enum ExpiryCheck: Equatable {
    case noSession
    case running(BlockSession)
    /// The block was over and has just been lifted.
    case ended(BlockSession)
    /// The block record exists but could not be read or removed. Nothing is lifted:
    /// the failure mode is "stays blocked until the app is opened".
    case unreadable(String)
}

/// A started or extended block, with problems that did not stop it.
struct BlockOutcome {
    var session: BlockSession
    var warnings: [String]
}

/// Starts, extends and ends blocks. The same engine runs in the app and in the
/// extensions, so all three end paths (PLAN.md section 3) share one implementation.
final class BlockEngine {
    let sessions: SessionStoring
    let shields: ShieldApplying
    let scheduler: ActivityScheduling
    let notifier: EndNotifying?
    let log: DiagnosticsLogging?
    let now: () -> Date

    init(sessions: SessionStoring,
         shields: ShieldApplying,
         scheduler: ActivityScheduling,
         notifier: EndNotifying?,
         log: DiagnosticsLogging?,
         now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.shields = shields
        self.scheduler = scheduler
        self.notifier = notifier
        self.log = log
        self.now = now
    }

    /// The engine backed by the App Group, ManagedSettings and DeviceActivity.
    static func live(notifier: EndNotifying?, log: DiagnosticsLogging?) throws -> BlockEngine {
        BlockEngine(sessions: try FileSessionStore.shared(),
                    shields: ManagedSettingsShieldController(),
                    scheduler: DeviceActivityScheduler(),
                    notifier: notifier,
                    log: log)
    }

    func currentSession() throws -> BlockSession? {
        try sessions.load()
    }

    // MARK: Starting and changing a block

    /// Starts a block. Shields go up first, then the record is saved, then the end is
    /// scheduled: if a later step fails, the result is "still blocked", never
    /// "silently unblocked" (PLAN.md section 3). A serious block cannot be ended early
    /// (see `endNow`) and is always strict.
    func start(duration: TimeInterval,
               plan: ShieldPlan,
               blockMessaging: Bool,
               strictMode: Bool,
               seriousMode: Bool = false,
               unlockEntries: Int) throws -> BlockOutcome {
        let now = self.now()
        if let existing = try sessions.load(), !existing.isExpired(at: now) {
            throw BlockError.alreadyRunning
        }
        guard !plan.socialCount.isEmpty else { throw BlockError.nothingToBlock }
        guard plan.socialCount.apps <= SelectionSummary.maximumApplications else {
            throw BlockError.tooManyApps(plan.socialCount.apps)
        }
        let messaging = blockMessaging && !plan.messagingCount.isEmpty
        if messaging, plan.messagingCount.apps > SelectionSummary.maximumApplications {
            throw BlockError.tooManyApps(plan.messagingCount.apps)
        }

        let session = try BlockSession.make(now: now,
                                            duration: duration,
                                            messagingBlocked: messaging,
                                            strictMode: strictMode,
                                            seriousMode: seriousMode,
                                            unlockEntries: unlockEntries)

        shields.applySocial(plan.social, hidingInstagram: plan.instagramHide)
        if messaging {
            shields.applyMessaging(plan.messaging)
        } else {
            shields.clearMessaging()
        }
        // The session's flag, not the setting: a serious block is strict either way.
        shields.applyStrict(session.strictMode)

        do {
            try sessions.save(session)
        } catch {
            // Without a saved record nothing could ever end this block, so undo it.
            shields.clearAll()
            log?.record(.app, "Could not save the block record, so the block was not started: \(error.localizedDescription)")
            throw BlockError.storageUnavailable(error.localizedDescription)
        }

        var warnings: [String] = []
        do {
            try scheduler.scheduleEnd(for: session)
        } catch {
            warnings.append(Self.scheduleWarning(error))
            log?.record(.app, "Could not schedule the end: \(error.localizedDescription)")
        }
        notifier?.scheduleEndNotification(for: session)
        log?.record(.app, "Block started, ends \(Self.logDate(session.end)); messaging \(messaging ? "blocked" : "open"), strict mode \(session.strictMode ? "on" : "off"), serious mode \(session.seriousMode ? "on" : "off")")
        return BlockOutcome(session: session, warnings: warnings)
    }

    /// Makes the running block longer. It can never be made shorter.
    func extend(byMinutes minutes: Int) throws -> BlockOutcome {
        let now = self.now()
        guard let session = try sessions.load(), !session.isExpired(at: now) else {
            throw BlockError.notRunning
        }
        let extended = try session.extended(by: TimeInterval(minutes) * 60, now: now)
        try sessions.save(extended)

        var warnings: [String] = []
        do {
            try scheduler.scheduleEnd(for: extended)
        } catch {
            warnings.append(Self.scheduleWarning(error))
            log?.record(.app, "Could not reschedule the end after extending: \(error.localizedDescription)")
        }
        notifier?.scheduleEndNotification(for: extended)
        log?.record(.app, "Block extended by \(minutes) min, now ends \(Self.logDate(extended.end))")
        return BlockOutcome(session: extended, warnings: warnings)
    }

    /// Unblocks the messaging apps for the rest of the block (one password entry).
    func unblockMessaging() throws -> BlockSession {
        guard var session = try sessions.load(), !session.isExpired(at: now()) else {
            throw BlockError.notRunning
        }
        guard session.messagingBlocked else { throw BlockError.messagingNotBlocked }
        session.messagingBlocked = false
        // Save first: if saving failed after lifting, the next foreground check would
        // put the messaging shield back.
        try sessions.save(session)
        shields.clearMessaging()
        log?.record(.app, "Messaging apps unblocked")
        return session
    }

    // MARK: Ending a block

    /// Ends the block now, after the password entries. A serious block that is still
    /// running is refused: it only ends on time, through `endIfExpired`.
    func endNow(source: EndSource) throws {
        // Enforced here, not only in the UI, so no caller can end a serious block early.
        // A record that cannot be read is let through: its end time is unknown, so
        // nothing else could ever lift it (the damaged-block screen).
        if let session = try? sessions.load(), session.seriousMode, !session.isExpired(at: now()) {
            log?.record(source.diagnosticSource, "Refused to end a serious block early; it runs until \(Self.logDate(session.end))")
            throw BlockError.cannotEndSeriousBlock
        }
        // The record goes first. If removing it fails, nothing has been lifted yet.
        try sessions.clear()
        shields.clearAll()
        scheduler.cancelAll()
        if source == .endedEarly {
            notifier?.cancelEndNotification()
        }
        log?.record(source.diagnosticSource, "Block ended: \(source.rawValue)")
    }

    /// End paths 1-3: lifts the block if its end time has passed. Used by the monitor
    /// extension, the app when it comes to the foreground and the shield button.
    @discardableResult
    func endIfExpired(source: EndSource, tolerance: TimeInterval = 0) -> ExpiryCheck {
        let session: BlockSession?
        do {
            session = try sessions.load()
        } catch {
            log?.record(source.diagnosticSource, "Could not read the block record: \(error.localizedDescription)")
            return .unreadable(error.localizedDescription)
        }
        guard let session else { return .noSession }
        guard session.isExpired(at: now(), tolerance: tolerance) else {
            if source == .monitor {
                log?.record(.monitor, "Interval ended, but the block runs until \(Self.logDate(session.end)); left in place")
            }
            return .running(session)
        }
        do {
            try sessions.clear()
        } catch {
            log?.record(source.diagnosticSource, "Block is over but its record could not be removed: \(error.localizedDescription)")
            return .unreadable(error.localizedDescription)
        }
        shields.clearAll()
        scheduler.cancelAll()
        log?.record(source.diagnosticSource, "Block over, shields lifted by the \(source.rawValue)")
        return .ended(session)
    }

    /// Runs when the app comes to the foreground: lifts an expired block (end path 2)
    /// and makes sure a running block is still fully in place.
    @discardableResult
    func reconcile(plan: ShieldPlan) -> ExpiryCheck {
        let check = endIfExpired(source: .app)
        switch check {
        case .noSession:
            // No block is running, so nothing may stay shielded, for example after a
            // crash between removing the record and lifting the shields.
            shields.clearAll()
        case .running(let session):
            // Put back anything that is missing. A list that cannot be read is left
            // alone rather than cleared.
            if !plan.socialCount.isEmpty {
                shields.applySocial(plan.social, hidingInstagram: plan.instagramHide)
            }
            if session.messagingBlocked {
                if !plan.messagingCount.isEmpty {
                    shields.applyMessaging(plan.messaging)
                }
            } else {
                shields.clearMessaging()
            }
            shields.applyStrict(session.strictMode)
            if !scheduler.isScheduled(session) {
                do {
                    try scheduler.scheduleEnd(for: session)
                    log?.record(.app, "The end schedule was missing and has been registered again")
                } catch {
                    log?.record(.app, "The end schedule is missing and could not be registered: \(error.localizedDescription)")
                }
            }
        case .ended, .unreadable:
            break
        }
        return check
    }

    // MARK: Helpers

    private static func scheduleWarning(_ error: Error) -> String {
        "iOS did not accept the end-of-block schedule (\(error.localizedDescription)). The block still ends on time when you open ConcentrationMaxx or tap a blocked app's button."
    }

    static func logDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
