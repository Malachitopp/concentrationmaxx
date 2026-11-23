import ManagedSettings

/// Names of the ManagedSettings stores the app and its extensions share.
/// Each group of restrictions lives in its own store so it can be cleared on its own
/// (PLAN.md section 3: "unblocking messaging is clear one store").
extension ManagedSettingsStore.Name {
    /// Shields for the social apps, categories and websites.
    static let cmxSocial = ManagedSettingsStore.Name("cmx.social")
    /// Shields for the messaging apps.
    static let cmxMessaging = ManagedSettingsStore.Name("cmx.messaging")
    /// Strict-mode restrictions (no app removal, automatic date and time).
    static let cmxStrict = ManagedSettingsStore.Name("cmx.strict")

    static let cmxAll: [ManagedSettingsStore.Name] = [.cmxSocial, .cmxMessaging, .cmxStrict]
}
