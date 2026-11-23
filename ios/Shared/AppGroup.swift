import Foundation

/// The App Group shared by the app and its three extensions (PLAN.md section 3).
///
/// The identifier is not hard-coded: project.yml writes it into every target's
/// Info.plist (`CMXAppGroupID`) from the `CMX_APP_GROUP` build setting, so the bundle
/// ID prefix only lives in one place.
enum AppGroup {
    static let infoPlistKey = "CMXAppGroupID"

    /// The App Group identifier from this bundle's Info.plist, or nil when the key is
    /// missing (for example inside the unit test bundle).
    static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.contains("$(") else {
            return nil
        }
        return value
    }

    /// The shared container directory, or nil when the App Group entitlement is missing
    /// or not provisioned for this build.
    static func containerURL() -> URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
