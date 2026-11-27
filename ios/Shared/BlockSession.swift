import Foundation

/// A running block. The app saves it in the App Group so the app and its three
/// extensions agree on when the block ends (PLAN.md section 3).
struct BlockSession: Codable, Equatable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    /// Whether the messaging apps are blocked right now. Starts as the
    /// "also block messaging" switch and becomes false after "Unblock messaging apps".
    var messagingBlocked: Bool
    var strictMode: Bool
    /// A serious block cannot be ended early: no password gets out of it, and it runs
    /// until `end`. Fixed when the block starts. A serious block is always strict.
    var seriousMode: Bool = false
    /// Password entries needed to end this block early. Fixed when the block starts,
    /// because the setting can only change while no block is running.
    var unlockEntries: Int

    enum CodingKeys: String, CodingKey {
        case id, start, end, messagingBlocked, strictMode, seriousMode, unlockEntries
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// True once the end time has passed. `tolerance` lets a callback that arrives a
    /// little before the end (the monitor's schedule works in whole minutes) count.
    func isExpired(at now: Date, tolerance: TimeInterval = 0) -> Bool {
        now >= end.addingTimeInterval(-tolerance)
    }

    func remaining(at now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }
}

extension BlockSession {
    /// Records written before serious mode existed have no `seriousMode` key. They are
    /// read as ordinary blocks, so a block that is running across an app update stays
    /// readable instead of turning into a damaged record.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  start: try container.decode(Date.self, forKey: .start),
                  end: try container.decode(Date.self, forKey: .end),
                  messagingBlocked: try container.decode(Bool.self, forKey: .messagingBlocked),
                  strictMode: try container.decode(Bool.self, forKey: .strictMode),
                  seriousMode: try container.decodeIfPresent(Bool.self, forKey: .seriousMode) ?? false,
                  unlockEntries: try container.decode(Int.self, forKey: .unlockEntries))
    }
}

/// Platform and product rules for block timing.
enum BlockRules {
    /// DeviceActivitySchedule rejects intervals shorter than 15 minutes.
    static let minimumDuration: TimeInterval = 15 * 60
    /// Sessions run 15 minutes to 24 hours (PLAN.md section 3).
    static let maximumDuration: TimeInterval = 24 * 60 * 60
    /// Rounding the end up to a whole minute adds less than this.
    static let roundingAllowance: TimeInterval = 60
    /// Duration presets on the home screen, in minutes.
    static let presetMinutes = [15, 30, 60, 120, 240]
    /// Ways to extend a running block, in minutes.
    static let extensionMinutes = [15, 30, 60, 120]
    /// How early the monitor's interval-end callback may arrive and still end the block.
    static let monitorEndTolerance: TimeInterval = 60
    /// Password entries needed to end a block early: 3 by default, 3-5 in Settings.
    static let unlockEntriesRange = 3...5
    static let defaultUnlockEntries = 3

    static func isValidDuration(_ duration: TimeInterval) -> Bool {
        duration >= minimumDuration && duration <= maximumDuration
    }

    /// Rounds a date up to the next whole minute. The reference date sits on a minute
    /// boundary and every current time zone offset is a whole number of minutes, so
    /// this matches the minute shown on the clock.
    static func roundedUpToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.up) * 60)
    }
}

enum BlockError: Error, Equatable, LocalizedError {
    case durationTooShort
    case durationTooLong
    case alreadyRunning
    case notRunning
    case alreadyEnded
    case cannotShorten
    case wouldExceedMaximum
    case nothingToBlock
    case tooManyApps(Int)
    case messagingNotBlocked
    case cannotEndSeriousBlock
    case storageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .cannotEndSeriousBlock:
            return "This is a serious block. It cannot be ended early and runs until its end time."
        case .durationTooShort:
            return "A block has to last at least 15 minutes."
        case .durationTooLong:
            return "A block can last at most 24 hours."
        case .alreadyRunning:
            return "A block is already running."
        case .notRunning:
            return "No block is running."
        case .alreadyEnded:
            return "This block has already ended."
        case .cannotShorten:
            return "A running block can be extended but not shortened."
        case .wouldExceedMaximum:
            return "A block can last at most 24 hours in total."
        case .nothingToBlock:
            return "Pick the social apps to block first (Settings → Block lists)."
        case .tooManyApps(let count):
            return "iOS can shield at most 50 individual apps, and this list has \(count). Pick categories for larger sets."
        case .messagingNotBlocked:
            return "Messaging apps are not blocked."
        case .storageUnavailable(let detail):
            return "The app's shared storage is unavailable (\(detail)). The build may be missing its App Group entitlement."
        }
    }
}

extension BlockSession {
    /// Creates a session that starts at `now`. The end is rounded up to the next whole
    /// minute, so "Blocked until 17:31" is exact and the schedule ends on a minute.
    /// A serious block is always strict: without strict mode, deleting the app or
    /// moving the clock forward would end a block that is meant to have no way out.
    static func make(
        id: UUID = UUID(),
        now: Date,
        duration: TimeInterval,
        messagingBlocked: Bool,
        strictMode: Bool,
        seriousMode: Bool = false,
        unlockEntries: Int
    ) throws -> BlockSession {
        guard duration >= BlockRules.minimumDuration else { throw BlockError.durationTooShort }
        guard duration <= BlockRules.maximumDuration else { throw BlockError.durationTooLong }
        let entries = min(max(unlockEntries, BlockRules.unlockEntriesRange.lowerBound), BlockRules.unlockEntriesRange.upperBound)
        return BlockSession(
            id: id,
            start: now,
            end: BlockRules.roundedUpToMinute(now.addingTimeInterval(duration)),
            messagingBlocked: messagingBlocked,
            strictMode: strictMode || seriousMode,
            seriousMode: seriousMode,
            unlockEntries: entries
        )
    }

    /// Returns the session extended by `extra` seconds. A block can be made longer,
    /// never shorter, and never longer than 24 hours in total.
    func extended(by extra: TimeInterval, now: Date) throws -> BlockSession {
        guard !isExpired(at: now) else { throw BlockError.alreadyEnded }
        guard extra > 0 else { throw BlockError.cannotShorten }
        let newEnd = BlockRules.roundedUpToMinute(end.addingTimeInterval(extra))
        // Rounding the end up adds less than a minute, so anything under 24 h + 1 min
        // is a block of at most 24 hours.
        guard newEnd.timeIntervalSince(start) < BlockRules.maximumDuration + BlockRules.roundingAllowance else {
            throw BlockError.wouldExceedMaximum
        }
        var copy = self
        copy.end = newEnd
        return copy
    }

    /// The extension presets (in minutes) that still fit within the 24-hour cap.
    func availableExtensions(now: Date) -> [Int] {
        BlockRules.extensionMinutes.filter { minutes in
            (try? extended(by: TimeInterval(minutes * 60), now: now)) != nil
        }
    }
}

/// Builds the date components for the block's DeviceActivitySchedule.
enum ScheduleWindow {
    static let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    /// The interval runs from the session's start (in the past is fine) to its end.
    /// Full dates are used so that blocks crossing midnight are scheduled correctly,
    /// and starting at the session start keeps the interval at 15 minutes or more even
    /// when the schedule is registered again close to the end, after an extension.
    static func dateComponents(for session: BlockSession, calendar: Calendar = .current) -> (start: DateComponents, end: DateComponents) {
        (calendar.dateComponents(components, from: session.start),
         calendar.dateComponents(components, from: session.end))
    }
}
