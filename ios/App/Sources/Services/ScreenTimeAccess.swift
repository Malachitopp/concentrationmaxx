import Combine
import FamilyControls
import Foundation

/// Screen Time (Family Controls) authorisation for this iPhone's own user:
/// `requestAuthorization(for: .individual)` (PLAN.md section 3).
@MainActor
final class ScreenTimeAccess: ObservableObject {
    @Published private(set) var status: AuthorizationStatus
    @Published private(set) var lastError: String?
    @Published private(set) var isRequesting = false

    private var cancellable: AnyCancellable?

    init() {
        status = AuthorizationCenter.shared.authorizationStatus
        cancellable = AuthorizationCenter.shared.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.status = status
            }
    }

    var isApproved: Bool { Self.isApproved(status) }

    /// A short description for Settings → Advanced.
    var statusDescription: String {
        if isApproved { return "Allowed" }
        switch status {
        case .notDetermined: return "Not requested yet"
        case .denied: return "Not allowed"
        default: return status.description
        }
    }

    static func isApproved(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *) {
            return status == .approvedWithDataAccess
        }
        return false
    }

    func request() async {
        guard !isRequesting else { return }
        isRequesting = true
        lastError = nil
        defer { isRequesting = false }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            lastError = Self.message(for: error)
            DiagnosticsLog.shared()?.record(.app, "Screen Time authorisation failed: \(error.localizedDescription)")
        }
        status = AuthorizationCenter.shared.authorizationStatus
        if !isApproved, lastError == nil {
            lastError = "Screen Time access was not granted. ConcentrationMaxx cannot block apps without it."
        }
    }

    func refresh() {
        status = AuthorizationCenter.shared.authorizationStatus
    }

    static func message(for error: Error) -> String {
        guard let error = error as? FamilyControlsError else {
            return error.localizedDescription
        }
        switch error {
        case .restricted:
            return "A restriction on this iPhone (for example a work or school profile) does not allow Screen Time access."
        case .unavailable:
            return "Screen Time access is unavailable right now. Check that Screen Time is on (Settings → Screen Time) and try again."
        case .invalidAccountType:
            return "Sign in to iCloud on this iPhone to allow Screen Time access."
        case .invalidArgument:
            return "iOS rejected the request. Please try again."
        case .authorizationConflict:
            return "Another app already manages Screen Time on this iPhone. Remove its access first (Settings → Screen Time), then try again."
        case .authorizationCanceled:
            return "Screen Time access was not granted. ConcentrationMaxx cannot block apps without it."
        case .networkError:
            return "Connect to the internet and try again: iOS checks Screen Time access online."
        case .authenticationMethodUnavailable:
            return "Set a passcode for this iPhone first (Settings → Face ID & Passcode), then try again."
        default:
            return error.localizedDescription
        }
    }
}
