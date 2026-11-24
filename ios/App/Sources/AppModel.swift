import Combine
import FamilyControls
import Foundation
import SwiftUI

/// A message shown at the top of the main screen.
struct Banner: Identifiable, Equatable {
    enum Kind {
        case error, warning, info
    }

    let id = UUID()
    var kind: Kind
    var message: String
}

/// Thrown when an account change is attempted during a block (PLAN.md section 3).
struct LockedDuringBlockError: LocalizedError {
    var errorDescription: String? { "This is not possible while a block is running." }
}

/// The app's state and the only place the UI starts, changes or ends blocks.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let screenTime: ScreenTimeAccess
    let notifications: NotificationAccess
    let account: AccountService
    let diagnostics: DiagnosticsLog?
    private var observers: Set<AnyCancellable> = []
    /// Set when the App Group container cannot be opened. Nothing can be blocked then.
    let storageProblem: String?

    private let engine: BlockEngine?
    private let selections: SelectionStoring?

    @Published private(set) var session: BlockSession? = nil
    /// Set when a block record exists but cannot be read.
    @Published private(set) var sessionProblem: String? = nil
    @Published private(set) var socialSelection = FamilyActivitySelection()
    @Published private(set) var messagingSelection = FamilyActivitySelection()
    @Published private(set) var instagramSelection = FamilyActivitySelection()
    @Published private(set) var onboardingCompleted: Bool
    @Published private(set) var unlockEntries: Int
    @Published private(set) var strictMode: Bool
    @Published private(set) var reelsFreeEnabled: Bool
    @Published private(set) var instagramStrategy: InstagramStrategy
    @Published private(set) var accountProfile: AccountProfile? = nil
    @Published private(set) var serverStatus: ServerSessionStatus = .notApplicable
    @Published var banner: Banner? = nil

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.screenTime = ScreenTimeAccess()
        self.notifications = NotificationAccess()
        self.account = AccountService(serverMode: AppConfig.current.serverMode)
        self.onboardingCompleted = settings.onboardingCompleted
        self.unlockEntries = settings.unlockEntries
        self.strictMode = settings.strictMode
        self.reelsFreeEnabled = settings.reelsFreeEnabled
        self.instagramStrategy = settings.instagramStrategy

        do {
            let directory = try SharedStorage.directory()
            let log = DiagnosticsLog(directory: directory)
            self.diagnostics = log
            self.selections = FileSelectionStore(directory: directory)
            self.engine = BlockEngine(sessions: FileSessionStore(directory: directory),
                                      shields: ManagedSettingsShieldController(),
                                      scheduler: DeviceActivityScheduler(),
                                      notifier: LocalEndNotifier(),
                                      log: log)
            self.storageProblem = nil
        } catch {
            self.diagnostics = nil
            self.selections = nil
            self.engine = nil
            self.storageProblem = error.localizedDescription
        }

        if let selections {
            socialSelection = selections.load(.social)
            messagingSelection = selections.load(.messaging)
            instagramSelection = selections.load(.instagram)
        }

        // Keychain items outlive the app, so a fresh install clears what an earlier
        // install left behind before anything reads it.
        if !settings.hasLaunchedBefore {
            account.wipeLocal()
            settings.hasLaunchedBefore = true
        }
        accountProfile = account.hasAccount ? account.profile : nil

        // A block started from Shortcuts while the app is open shows up right away.
        NotificationCenter.default.publisher(for: .cmxBlockStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appBecameActive()
            }
            .store(in: &observers)
    }

    /// Where onboarding starts: from the account step when only the account is missing
    /// (after logging out), otherwise from the welcome screen.
    var initialOnboardingStep: OnboardingView.Step {
        accountProfile == nil && !socialSelection.isEmptySelection ? .account : .welcome
    }

    var isBlockRunning: Bool { session != nil || sessionProblem != nil }

    /// Whether the Reels-free Instagram feature is compiled into this build.
    static var reelsFreeAvailable: Bool {
        #if REELS_FREE
        return true
        #else
        return false
        #endif
    }

    // MARK: Lifecycle

    /// End path 2: whenever the app comes to the foreground, an expired block is lifted
    /// and a running one is checked to be fully in place.
    func appBecameActive() {
        screenTime.refresh()
        guard let engine else { return }
        apply(engine.reconcile(plan: currentPlan()))
    }

    /// Called when the countdown reaches zero while the app is open.
    func countdownFinished() {
        appBecameActive()
    }

    private func apply(_ check: ExpiryCheck) {
        switch check {
        case .noSession:
            session = nil
            sessionProblem = nil
        case .running(let running):
            session = running
            sessionProblem = nil
        case .ended:
            session = nil
            sessionProblem = nil
            banner = Banner(kind: .info, message: "Your block is over. Everything is unblocked.")
        case .unreadable(let problem):
            session = nil
            sessionProblem = problem
        }
    }

    // MARK: Blocks

    func currentPlan() -> ShieldPlan {
        BlockSetup.plan(social: socialSelection,
                        messaging: messagingSelection,
                        instagram: instagramSelection,
                        reelsFreeEnabled: reelsFreeEnabled,
                        strategy: instagramStrategy,
                        reelsFreeAvailable: Self.reelsFreeAvailable)
    }

    /// Whether blocks hide Instagram instead of shielding it (the "Hide" strategy).
    var hidesInstagram: Bool {
        BlockSetup.hidesInstagram(reelsFreeEnabled: reelsFreeEnabled, strategy: instagramStrategy,
                                  instagramPicked: !instagramSelection.isEmptySelection,
                                  reelsFreeAvailable: Self.reelsFreeAvailable)
    }

    @discardableResult
    func startBlock(minutes: Int, blockMessaging: Bool) -> Bool {
        guard let engine else {
            show(error: storageProblem ?? "Shared storage is unavailable.")
            return false
        }
        guard screenTime.isApproved else {
            show(error: "Screen Time access is off, so apps cannot be blocked. Allow it in Settings → Screen Time access.")
            return false
        }
        settings.lastDurationMinutes = minutes
        settings.blockMessaging = blockMessaging
        do {
            let outcome = try engine.start(duration: TimeInterval(minutes) * 60,
                                           plan: currentPlan(),
                                           blockMessaging: blockMessaging,
                                           strictMode: strictMode,
                                           unlockEntries: unlockEntries)
            session = outcome.session
            sessionProblem = nil
            banner = outcome.warnings.first.map { Banner(kind: .warning, message: $0) }
            return true
        } catch {
            show(error: error)
            return false
        }
    }

    func extendBlock(minutes: Int) {
        guard let engine else { return }
        do {
            let outcome = try engine.extend(byMinutes: minutes)
            session = outcome.session
            banner = outcome.warnings.first.map { Banner(kind: .warning, message: $0) }
        } catch {
            show(error: error)
            appBecameActive()
        }
    }

    /// Ends the block. The caller has already taken the password entries.
    func endBlockEarly() {
        guard let engine else { return }
        do {
            try engine.endNow(source: .endedEarly)
            session = nil
            sessionProblem = nil
            banner = Banner(kind: .info, message: "Block ended early.")
        } catch {
            show(error: "The block could not be ended: \(error.localizedDescription)")
        }
    }

    /// Unblocks messaging apps for the rest of the block (after one password entry).
    func unblockMessaging() {
        guard let engine else { return }
        do {
            session = try engine.unblockMessaging()
            banner = Banner(kind: .info, message: "Messaging apps are unblocked until the block ends.")
        } catch {
            show(error: error)
        }
    }

    // MARK: Block lists

    /// Saves a list picked in Apple's picker. Lists are locked while a block runs.
    @discardableResult
    func save(_ selection: FamilyActivitySelection, as kind: SelectionKind) -> Bool {
        guard !isBlockRunning else {
            show(error: "Block lists are locked while a block is running.")
            return false
        }
        guard selection.applicationTokens.count <= SelectionSummary.maximumApplications else {
            show(error: BlockError.tooManyApps(selection.applicationTokens.count))
            return false
        }
        guard let selections else {
            show(error: storageProblem ?? "Shared storage is unavailable.")
            return false
        }
        do {
            try selections.save(selection, as: kind)
        } catch {
            show(error: "The list could not be saved: \(error.localizedDescription)")
            return false
        }
        switch kind {
        case .social: socialSelection = selection
        case .messaging: messagingSelection = selection
        case .instagram: instagramSelection = selection
        }
        return true
    }

    func selection(_ kind: SelectionKind) -> FamilyActivitySelection {
        switch kind {
        case .social: return socialSelection
        case .messaging: return messagingSelection
        case .instagram: return instagramSelection
        }
    }

    // MARK: Settings (locked while a block runs, PLAN.md sections 3 and 4)

    func setUnlockEntries(_ value: Int) {
        guard !isBlockRunning else { return showLockedSetting() }
        unlockEntries = AppSettings.clampEntries(value)
        settings.unlockEntries = unlockEntries
    }

    func setStrictMode(_ value: Bool) {
        guard !isBlockRunning else { return showLockedSetting() }
        strictMode = value
        settings.strictMode = value
    }

    /// Turning the Reels-free web view on during a block would loosen the block, so
    /// that is locked; turning it off is always allowed.
    func setReelsFreeEnabled(_ value: Bool) {
        if value, isBlockRunning { return showLockedSetting() }
        reelsFreeEnabled = value
        settings.reelsFreeEnabled = value
    }

    func setInstagramStrategy(_ value: InstagramStrategy) {
        guard !isBlockRunning else { return showLockedSetting() }
        instagramStrategy = value
        settings.instagramStrategy = value
    }

    func completeOnboarding() {
        onboardingCompleted = true
        settings.onboardingCompleted = true
    }

    // MARK: Account (PLAN.md sections 3 and 5)

    func createAccount(username: String, password: String, inviteCode: String) async throws {
        accountProfile = try await account.createAccount(username: username, password: password, inviteCode: inviteCode)
    }

    func logIn(username: String, password: String) async throws {
        accountProfile = try await account.logIn(username: username, password: password)
    }

    /// Changing the password is disabled during a block.
    func changePassword(current: String, new: String) async throws {
        guard !isBlockRunning else { throw LockedDuringBlockError() }
        try await account.changePassword(current: current, new: new)
        banner = Banner(kind: .info, message: "Password changed.")
        await refreshServerStatus()
    }

    /// Deleting the account is disabled during a block: it would remove the password.
    func deleteAccount(password: String) async throws {
        guard !isBlockRunning else { throw LockedDuringBlockError() }
        try await account.deleteAccount(password: password)
        accountSignedOut()
    }

    /// Logging out is disabled during a block.
    func logOut() {
        guard !isBlockRunning else { return show(error: LockedDuringBlockError()) }
        account.logOut()
        accountSignedOut()
    }

    func refreshServerStatus() async {
        serverStatus = await account.checkServerSession()
    }

    private func accountSignedOut() {
        accountProfile = nil
        serverStatus = .notApplicable
        onboardingCompleted = false
        settings.onboardingCompleted = false
    }

    // MARK: Messages

    func show(error: Error) {
        show(error: error.localizedDescription)
    }

    func show(error message: String) {
        banner = Banner(kind: .error, message: message)
    }

    private func showLockedSetting() {
        show(error: "This setting is locked while a block is running.")
    }
}
