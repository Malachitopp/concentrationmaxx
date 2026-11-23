import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Principal class of the ShieldConfiguration extension: describes the screen the
/// system draws over a blocked app or website.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterialDark,
            backgroundColor: nil,
            icon: UIImage(systemName: "hourglass"),
            title: ShieldConfiguration.Label(text: "Blocked", color: .white),
            subtitle: nil,
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: .systemIndigo,
            secondaryButtonLabel: nil
        )
    }
}
