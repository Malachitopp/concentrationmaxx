import AppIntents
import FamilyControls
import Foundation

extension Notification.Name {
    /// Posted when something outside the UI (the Shortcuts action) starts a block.
    static let cmxBlockStateChanged = Notification.Name("cmx.blockStateChanged")
}

/// "Start a block" for Shortcuts (PLAN.md section 4), so one shortcut can turn on Do Not
/// Disturb (with calls still allowed) and start a block.
struct StartBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Block"
    static let description: IntentDescription? = IntentDescription("Blocks your social apps with ConcentrationMaxx for the number of minutes you choose (15 to 1440). Ending early takes your password. With Serious mode on, the block cannot be ended early at all.")
    static let openAppWhenRun = false

    @Parameter(title: "Minutes", default: 60)
    var minutes: Int

    @Parameter(title: "Also block messaging apps", default: false)
    var blockMessaging: Bool

    /// Off by default, so shortcuts made before serious mode existed keep starting
    /// ordinary blocks. The title says what it does because Shortcuts shows nothing else.
    @Parameter(title: "Serious mode (cannot be ended early)", default: false)
    var seriousMode: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Block social apps for \(\.$minutes) minutes") {
            \.$blockMessaging
            \.$seriousMode
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard BlockRules.isValidDuration(TimeInterval(minutes) * 60) else {
            throw StartBlockIntentError.invalidDuration
        }
        let settings = AppSettings()
        guard settings.onboardingCompleted else {
            throw StartBlockIntentError.notSetUp
        }
        guard ScreenTimeAccess.isApproved(AuthorizationCenter.shared.authorizationStatus) else {
            throw StartBlockIntentError.notAuthorized
        }

        let log = DiagnosticsLog.shared()
        let engine: BlockEngine
        let selections: FileSelectionStore
        do {
            engine = try BlockEngine.live(notifier: LocalEndNotifier(), log: log)
            selections = try FileSelectionStore.shared()
        } catch {
            throw StartBlockIntentError.failed(error.localizedDescription)
        }

        if let running = try? engine.currentSession(), !running.isExpired(at: Date()) {
            throw StartBlockIntentError.alreadyRunning(until: ShieldContent.endDescription(running.end, now: Date()))
        }

        let plan = BlockSetup.plan(social: selections.load(.social),
                                   messaging: selections.load(.messaging),
                                   instagram: selections.load(.instagram),
                                   reelsFreeEnabled: settings.reelsFreeEnabled,
                                   strategy: settings.instagramStrategy,
                                   reelsFreeAvailable: AppModel.reelsFreeAvailable)
        let outcome: BlockOutcome
        do {
            outcome = try engine.start(duration: TimeInterval(minutes) * 60,
                                       plan: plan,
                                       blockMessaging: blockMessaging,
                                       strictMode: settings.strictMode,
                                       seriousMode: seriousMode,
                                       unlockEntries: settings.unlockEntries)
        } catch {
            throw StartBlockIntentError.failed(error.localizedDescription)
        }
        log?.record(.intent, "Block started from Shortcuts for \(minutes) min\(seriousMode ? ", serious mode" : "")")
        NotificationCenter.default.post(name: .cmxBlockStateChanged, object: nil)

        let until = ShieldContent.endDescription(outcome.session.end, now: Date())
        let serious = outcome.session.seriousMode ? " This is a serious block: it cannot be ended early." : ""
        if let warning = outcome.warnings.first {
            return .result(dialog: "Blocked until \(until).\(serious) \(warning)")
        }
        return .result(dialog: "Blocked until \(until).\(serious)")
    }
}

enum StartBlockIntentError: Error, CustomLocalizedStringResourceConvertible {
    case invalidDuration
    case notSetUp
    case notAuthorized
    case alreadyRunning(until: String)
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .invalidDuration:
            return "A block lasts 15 to 1440 minutes."
        case .notSetUp:
            return "Open ConcentrationMaxx and finish setting it up first."
        case .notAuthorized:
            return "ConcentrationMaxx has no Screen Time access. Open the app to allow it."
        case .alreadyRunning(let until):
            return "A block is already running until \(until)."
        case .failed(let message):
            return "The block could not start: \(message)"
        }
    }
}

struct ConcentrationMaxxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBlockIntent(),
            phrases: [
                "Start a block in \(.applicationName)",
                "Block social media with \(.applicationName)",
            ],
            shortTitle: "Start Block",
            systemImageName: "lock.fill"
        )
    }
}
