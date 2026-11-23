import SwiftUI

/// Onboarding until it is finished, then the main screen.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.onboardingCompleted, model.accountProfile != nil {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .tint(Color.accentColor)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.appBecameActive()
            }
        }
    }
}

/// Home when no block runs, the active block otherwise.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let session = model.session {
                    ActiveBlockView(session: session)
                } else if let problem = model.sessionProblem {
                    DamagedBlockView(problem: problem)
                } else {
                    HomeView()
                }
            }
            .navigationTitle("ConcentrationMaxx")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .top) {
                if let banner = model.banner {
                    BannerView(banner: banner) {
                        model.banner = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

/// Shown when a block record exists but cannot be read. The block stays in place until
/// the person ends it with the usual password entries.
struct DamagedBlockView: View {
    @EnvironmentObject private var model: AppModel
    let problem: String
    @State private var unlocking = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("The block could not be read")
                .font(.title3.bold())
            Text("Your apps stay blocked. Details: \(problem)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Check again") {
                model.appBecameActive()
            }
            .buttonStyle(.bordered)
            Button("End block (password \(model.unlockEntries) times)", role: .destructive) {
                unlocking = true
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $unlocking) {
            UnlockView(purpose: .endDamagedBlock, required: model.unlockEntries) {
                model.endBlockEarly()
            }
        }
    }
}
