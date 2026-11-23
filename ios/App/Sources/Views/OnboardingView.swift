import FamilyControls
import SwiftUI

/// First-run setup (PLAN.md section 4): welcome → Screen Time permission → social
/// apps → messaging apps → done.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, screenTime, socialApps, messagingApps, finish

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .screenTime: return "Screen Time access"
            case .socialApps: return "Social apps"
            case .messagingApps: return "Messaging apps"
            case .finish: return "All set"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeAccess
    @State private var step: Step = .welcome

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) {
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .background(.bar)
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { move(by: -1) }
                    }
                }
            }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            OnboardingHeader(symbol: "scope", title: "ConcentrationMaxx",
                             text: "Block social media for a time you choose. Ending a block early takes your password, typed several times in a row.")
            BulletList(items: [
                "Social apps are blocked with Apple's Screen Time shield.",
                "Messaging apps can be blocked too, and unblocked with one password entry.",
                "Phone calls are never blocked.",
            ])
        case .screenTime:
            OnboardingHeader(symbol: "hourglass", title: "Allow Screen Time access",
                             text: "iOS asks you to confirm with Face ID or your passcode. Without this permission nothing can be blocked.")
            if screenTime.isApproved {
                Label("Screen Time access is allowed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let error = screenTime.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .socialApps:
            OnboardingHeader(symbol: "apps.iphone", title: "Pick the apps to block",
                             text: "Apple's picker opens. Tick the apps below, or whole categories. You only do this once and can change it later in Settings.")
            BulletList(items: ["TikTok", "Instagram", "X (Twitter)", "Reddit", "Snapchat"])
            SelectionEditor(kind: .social, buttonTitle: "Choose apps")
        case .messagingApps:
            OnboardingHeader(symbol: "message", title: "Pick your messaging apps",
                             text: "Each block has an \"also block messaging\" switch. During a block, one password entry unblocks messaging only.")
            BulletList(items: ["WhatsApp", "Telegram", "Messenger", "Signal", "Discord"])
            Text("Apple Messages and FaceTime stay in Screen Time's \"Always Allowed\" list unless you remove them there yourself. Phone calls are never blocked. You can skip this step.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            SelectionEditor(kind: .messaging, buttonTitle: "Choose apps")
        case .finish:
            OnboardingHeader(symbol: "checkmark.seal", title: "You are ready",
                             text: "Pick a duration and start a block. Blocks last 15 minutes to 24 hours and can be extended but not shortened.")
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .screenTime where !screenTime.isApproved:
            Button {
                Task { await screenTime.request() }
            } label: {
                Text(screenTime.isRequesting ? "Waiting for iOS…" : "Allow Screen Time access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(screenTime.isRequesting)
        case .finish:
            Button {
                model.completeOnboarding()
            } label: {
                Text("Start using ConcentrationMaxx").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        default:
            Button {
                move(by: 1)
            } label: {
                Text(continueTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canContinue)
        }
    }

    private var continueTitle: String {
        if step == .messagingApps, model.messagingSelection.isEmptySelection {
            return "Skip"
        }
        return "Continue"
    }

    private var canContinue: Bool {
        switch step {
        case .screenTime: return screenTime.isApproved
        case .socialApps: return !model.socialSelection.isEmptySelection
        default: return true
        }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation { step = next }
    }
}

struct OnboardingHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title2.bold())
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
