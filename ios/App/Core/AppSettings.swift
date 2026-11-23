import Foundation

/// How Instagram is blocked when the Reels-free web view is turned on
/// (PLAN.md section 6). Switchable in Settings → Advanced.
enum InstagramStrategy: String, CaseIterable, Identifiable {
    /// Instagram is shielded like every other app. iOS may then shield
    /// instagram.com inside the in-app web view too.
    case shield
    /// Instagram is taken out of the shield and hidden by bundle ID instead, which may
    /// leave instagram.com reachable. Needs Instagram picked on its own.
    case hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shield: return "Shield (default)"
        case .hide: return "Hide"
        }
    }
}

/// The person's settings, kept in the app's own UserDefaults (the extensions do not
/// need them: everything they need is in the block record).
final class AppSettings {
    enum Key: String {
        case unlockEntries = "settings.unlockEntries"
        case strictMode = "settings.strictMode"
        case reelsFreeEnabled = "settings.reelsFreeEnabled"
        case instagramStrategy = "settings.instagramStrategy"
        case onboardingCompleted = "settings.onboardingCompleted"
        case blockMessaging = "settings.blockMessaging"
        case lastDurationMinutes = "settings.lastDurationMinutes"
        case hasLaunchedBefore = "settings.hasLaunchedBefore"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Password entries needed to end a block early: 3 by default, 3-5.
    var unlockEntries: Int {
        get {
            let stored = defaults.integer(forKey: Key.unlockEntries.rawValue)
            return stored == 0 ? BlockRules.defaultUnlockEntries : Self.clampEntries(stored)
        }
        set { defaults.set(Self.clampEntries(newValue), forKey: Key.unlockEntries.rawValue) }
    }

    /// Strict mode is on by default (PLAN.md section 3).
    var strictMode: Bool {
        get { bool(.strictMode, default: true) }
        set { defaults.set(newValue, forKey: Key.strictMode.rawValue) }
    }

    /// Reels-free Instagram is off by default (PLAN.md section 6).
    var reelsFreeEnabled: Bool {
        get { bool(.reelsFreeEnabled, default: false) }
        set { defaults.set(newValue, forKey: Key.reelsFreeEnabled.rawValue) }
    }

    var instagramStrategy: InstagramStrategy {
        get {
            defaults.string(forKey: Key.instagramStrategy.rawValue).flatMap(InstagramStrategy.init(rawValue:)) ?? .shield
        }
        set { defaults.set(newValue.rawValue, forKey: Key.instagramStrategy.rawValue) }
    }

    var onboardingCompleted: Bool {
        get { bool(.onboardingCompleted, default: false) }
        set { defaults.set(newValue, forKey: Key.onboardingCompleted.rawValue) }
    }

    /// The last state of the "also block messaging apps" switch.
    var blockMessaging: Bool {
        get { bool(.blockMessaging, default: false) }
        set { defaults.set(newValue, forKey: Key.blockMessaging.rawValue) }
    }

    /// The last duration picked on the home screen.
    var lastDurationMinutes: Int {
        get {
            let stored = defaults.integer(forKey: Key.lastDurationMinutes.rawValue)
            return stored == 0 ? 60 : Self.clampMinutes(stored)
        }
        set { defaults.set(Self.clampMinutes(newValue), forKey: Key.lastDurationMinutes.rawValue) }
    }

    /// False only on the first launch after installing. Keychain items survive
    /// deleting the app, so the first launch clears what an old install left behind.
    var hasLaunchedBefore: Bool {
        get { bool(.hasLaunchedBefore, default: false) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore.rawValue) }
    }

    func reset() {
        for key in [Key.unlockEntries, .strictMode, .reelsFreeEnabled, .instagramStrategy,
                    .onboardingCompleted, .blockMessaging, .lastDurationMinutes] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    static func clampEntries(_ value: Int) -> Int {
        min(max(value, BlockRules.unlockEntriesRange.lowerBound), BlockRules.unlockEntriesRange.upperBound)
    }

    static func clampMinutes(_ value: Int) -> Int {
        let minimum = Int(BlockRules.minimumDuration / 60)
        let maximum = Int(BlockRules.maximumDuration / 60)
        return min(max(value, minimum), maximum)
    }

    private func bool(_ key: Key, default value: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) as? Bool ?? value
    }
}

/// Formats durations for the UI: "15 min", "1 h", "1 h 30 min", "24 h".
enum DurationText {
    static func minutes(_ total: Int) -> String {
        let hours = total / 60
        let minutes = total % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(minutes) min"
        }
    }

    /// A countdown such as "1:04:09" or "4:09".
    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
