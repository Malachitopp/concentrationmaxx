import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Principal class of the ShieldConfiguration extension: the "Blocked until 17:30"
/// screen the system draws over a blocked app or website. It only reads the shared
/// block record; the system expects an answer quickly.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(itemName: application.localizedDisplayName,
             group: group(application: application.token, category: nil, webDomain: nil))
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(itemName: application.localizedDisplayName,
             group: group(application: application.token, category: category.token, webDomain: nil))
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(itemName: webDomain.domain,
             group: group(application: nil, category: nil, webDomain: webDomain.token))
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(itemName: webDomain.domain,
             group: group(application: nil, category: category.token, webDomain: webDomain.token))
    }

    // MARK: -

    private lazy var session: BlockSession? = try? FileSessionStore.shared().load()
    private lazy var selections: FileSelectionStore? = try? FileSelectionStore.shared()

    /// An item counts as "messaging" only when it is in the messaging list and not in
    /// the social list, because unblocking messaging would not free a social app.
    private func group(application: ApplicationToken?,
                       category: ActivityCategoryToken?,
                       webDomain: WebDomainToken?) -> ShieldContent.Group {
        guard let selections else { return .social }
        let messaging = selections.load(.messaging)
        let social = selections.load(.social)
        func inMessaging() -> Bool {
            if let application, messaging.applicationTokens.contains(application) { return true }
            if let webDomain, messaging.webDomainTokens.contains(webDomain) { return true }
            if let category, messaging.categoryTokens.contains(category) { return true }
            return false
        }
        func inSocial() -> Bool {
            if let application, social.applicationTokens.contains(application) { return true }
            if let webDomain, social.webDomainTokens.contains(webDomain) { return true }
            if let category, social.categoryTokens.contains(category) { return true }
            return false
        }
        return inMessaging() && !inSocial() ? .messaging : .social
    }

    private func make(itemName: String?, group: ShieldContent.Group) -> ShieldConfiguration {
        let text = ShieldContent.text(session: session, group: group, itemName: itemName, now: Date())
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: UIColor(red: 0.08, green: 0.09, blue: 0.20, alpha: 0.85),
            icon: UIImage(systemName: "hourglass"),
            title: ShieldConfiguration.Label(text: text.title, color: .white),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: UIColor(white: 0.85, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: text.primaryButton, color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.42, green: 0.26, blue: 0.80, alpha: 1),
            secondaryButtonLabel: nil
        )
    }
}
