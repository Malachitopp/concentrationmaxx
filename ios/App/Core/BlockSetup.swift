import FamilyControls
import Foundation

/// Builds what a block covers from the saved lists and settings. Used by the app and by
/// the Shortcuts action, so both start exactly the same block.
enum BlockSetup {
    static func plan(social: FamilyActivitySelection,
                     messaging: FamilyActivitySelection,
                     instagram: FamilyActivitySelection,
                     reelsFreeEnabled: Bool,
                     strategy: InstagramStrategy,
                     reelsFreeAvailable: Bool) -> ShieldPlan {
        ShieldPlan(social: social,
                   messaging: messaging,
                   instagramHide: hidesInstagram(reelsFreeEnabled: reelsFreeEnabled, strategy: strategy,
                                                 instagramPicked: !instagram.isEmptySelection,
                                                 reelsFreeAvailable: reelsFreeAvailable) ? instagram : nil)
    }

    /// The "Hide" strategy only applies when the Reels-free feature is compiled in,
    /// switched on, set to Hide, and Instagram has been picked on its own.
    static func hidesInstagram(reelsFreeEnabled: Bool,
                               strategy: InstagramStrategy,
                               instagramPicked: Bool,
                               reelsFreeAvailable: Bool) -> Bool {
        reelsFreeAvailable && reelsFreeEnabled && strategy == .hide && instagramPicked
    }
}
