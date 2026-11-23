import FamilyControls
import ManagedSettings

/// How many apps, categories and websites a selection holds. The engine decides with
/// counts rather than tokens, because unit tests cannot create real Screen Time tokens.
struct SelectionCount: Equatable {
    var apps: Int
    var categories: Int
    var websites: Int

    static let zero = SelectionCount(apps: 0, categories: 0, websites: 0)

    init(apps: Int, categories: Int, websites: Int) {
        self.apps = apps
        self.categories = categories
        self.websites = websites
    }

    init(_ selection: FamilyActivitySelection) {
        self.init(apps: selection.applicationTokens.count,
                  categories: selection.categoryTokens.count,
                  websites: selection.webDomainTokens.count)
    }

    var isEmpty: Bool { apps == 0 && categories == 0 && websites == 0 }
}

/// What a block covers, built by the app from the saved lists and settings.
struct ShieldPlan {
    var social: FamilyActivitySelection
    var messaging: FamilyActivitySelection
    /// The person's separate Instagram pick, set only under the "Hide" strategy
    /// (PLAN.md section 6): Instagram then leaves the shield and is hidden instead.
    var instagramHide: FamilyActivitySelection?

    var socialCount: SelectionCount
    var messagingCount: SelectionCount

    init(social: FamilyActivitySelection,
         messaging: FamilyActivitySelection,
         instagramHide: FamilyActivitySelection? = nil) {
        self.social = social
        self.messaging = messaging
        self.instagramHide = instagramHide
        self.socialCount = SelectionCount(social)
        self.messagingCount = SelectionCount(messaging)
    }
}

/// Instagram's bundle ID, used by the "Hide" strategy through
/// `application.blockedApplications`, which accepts apps by bundle ID.
enum InstagramApp {
    static let bundleIdentifier = "com.burbn.instagram"
}

protocol ShieldApplying: AnyObject {
    func applySocial(_ selection: FamilyActivitySelection, hidingInstagram instagram: FamilyActivitySelection?)
    func applyMessaging(_ selection: FamilyActivitySelection)
    func clearMessaging()
    func applyStrict(_ enabled: Bool)
    func clearAll()
}

/// Applies shields through three named ManagedSettings stores, so each group can be
/// lifted on its own. Stores with the same name are shared by the app and extensions.
final class ManagedSettingsShieldController: ShieldApplying {
    private let social = ManagedSettingsStore(named: .cmxSocial)
    private let messaging = ManagedSettingsStore(named: .cmxMessaging)
    private let strict = ManagedSettingsStore(named: .cmxStrict)

    func applySocial(_ selection: FamilyActivitySelection, hidingInstagram instagram: FamilyActivitySelection?) {
        Self.shield(selection, in: social, excluding: instagram)
        if instagram != nil {
            // "Hide" strategy: Instagram is out of the shield (so the in-app web view is
            // not covered) and hidden from the home screen instead.
            social.application.blockedApplications = [Application(bundleIdentifier: InstagramApp.bundleIdentifier)]
        } else {
            social.application.blockedApplications = nil
        }
    }

    func applyMessaging(_ selection: FamilyActivitySelection) {
        Self.shield(selection, in: messaging, excluding: nil)
    }

    func clearMessaging() {
        messaging.clearAllSettings()
    }

    func applyStrict(_ enabled: Bool) {
        if enabled {
            // No deleting apps to escape, no moving the clock forward (PLAN.md section 3).
            strict.application.denyAppRemoval = true
            strict.dateAndTime.requireAutomaticDateAndTime = true
        } else {
            strict.clearAllSettings()
        }
    }

    func clearAll() {
        social.clearAllSettings()
        messaging.clearAllSettings()
        strict.clearAllSettings()
    }

    /// Shields the picked apps, categories and websites. Deliberately does not use
    /// `webContent.blockedByFilter`, which developers report as unreliable on iOS 26.
    private static func shield(_ selection: FamilyActivitySelection,
                               in store: ManagedSettingsStore,
                               excluding excluded: FamilyActivitySelection?) {
        let excludedApps = excluded?.applicationTokens ?? []
        let apps = selection.applicationTokens.subtracting(excludedApps)
        let websites = selection.webDomainTokens.subtracting(excluded?.webDomainTokens ?? [])
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: excludedApps)
        store.shield.webDomains = websites.isEmpty ? nil : websites
    }
}
