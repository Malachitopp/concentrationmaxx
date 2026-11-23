import Foundation

/// Failed entries and an active lockout. Persisted, so closing the app does not reset
/// the lockout.
struct UnlockGuardState: Codable, Equatable {
    var failures = 0
    var lockedUntil: Date?
}

/// "Type the password N times in a row" (PLAN.md section 3). N consecutive correct
/// entries unlock; a wrong entry goes back to step 1; five wrong entries lock the flow
/// for five minutes. Pure logic: the caller checks the password and reports the result.
struct UnlockMachine: Equatable {
    static let maxFailures = 5
    static let lockoutDuration: TimeInterval = 5 * 60

    enum Outcome: Equatable {
        /// A correct entry, with more still needed.
        case progressed(completed: Int, required: Int)
        /// The last correct entry: unlock.
        case unlocked
        /// A wrong entry. Back to step 1.
        case wrong(failuresLeft: Int)
        /// Too many wrong entries. The password is not even checked until `until`.
        case lockedOut(until: Date)
    }

    let required: Int
    private(set) var completed = 0
    private(set) var guardState: UnlockGuardState

    init(required: Int, guardState: UnlockGuardState = UnlockGuardState()) {
        self.required = max(1, required)
        self.guardState = guardState
    }

    /// The step the person is on, counting from 1 ("step 2 of 3").
    var currentStep: Int { completed + 1 }

    /// When the current lockout ends, or nil if the flow is open.
    func lockoutEnd(at now: Date) -> Date? {
        guard let until = guardState.lockedUntil, now < until else { return nil }
        return until
    }

    /// Clears a lockout whose time is up.
    mutating func refresh(at now: Date) {
        if let until = guardState.lockedUntil, now >= until {
            guardState = UnlockGuardState()
            completed = 0
        }
    }

    /// Records the result of one entry. During a lockout nothing is counted.
    mutating func record(correct: Bool, at now: Date) -> Outcome {
        refresh(at: now)
        if let until = lockoutEnd(at: now) {
            return .lockedOut(until: until)
        }
        guard correct else {
            completed = 0
            guardState.failures += 1
            if guardState.failures >= Self.maxFailures {
                let until = now.addingTimeInterval(Self.lockoutDuration)
                guardState.lockedUntil = until
                return .lockedOut(until: until)
            }
            return .wrong(failuresLeft: Self.maxFailures - guardState.failures)
        }
        completed += 1
        if completed >= required {
            completed = 0
            guardState = UnlockGuardState()
            return .unlocked
        }
        return .progressed(completed: completed, required: required)
    }

    /// Convenience for callers that can check synchronously. `isCorrect` is not called
    /// during a lockout.
    mutating func submit(at now: Date, isCorrect: () -> Bool) -> Outcome {
        refresh(at: now)
        if let until = lockoutEnd(at: now) {
            return .lockedOut(until: until)
        }
        return record(correct: isCorrect(), at: now)
    }

    /// Back to step 1 when the unlock screen closes. Failures are kept.
    mutating func restart() {
        completed = 0
    }
}

/// Keeps the guard state in UserDefaults, shared by every unlock flow (ending a block
/// early and unblocking messaging), so switching flows does not reset the count.
final class UnlockGuardStore {
    private let defaults: UserDefaults
    private let key = "unlock.guardState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UnlockGuardState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(UnlockGuardState.self, from: data) else {
            return UnlockGuardState()
        }
        return state
    }

    func save(_ state: UnlockGuardState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
}
