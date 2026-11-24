import SwiftUI

/// The Reels-free Instagram switch, off by default (PLAN.md section 6). Builds with the
/// feature compiled out (CMX_FEATURE_FLAGS="") show nothing.
struct ReelsFreeOption: View {
    @EnvironmentObject private var model: AppModel

    #if REELS_FREE
    var body: some View {
        Toggle(isOn: Binding(get: { model.reelsFreeEnabled }, set: { model.setReelsFreeEnabled($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Instagram without Reels")
                Text("An in-app Instagram with your feed and messages but no Reels or Explore, usable during a block. Video posts in the feed still play.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}

/// Settings → Instagram without Reels.
struct InstagramSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingInstagram = false

    #if REELS_FREE
    var body: some View {
        Section {
            ReelsFreeOption()
                .disabled(model.isBlockRunning && !model.reelsFreeEnabled)
            if model.reelsFreeEnabled {
                Button("Open Instagram (no Reels)") {
                    showingInstagram = true
                }
            }
        } header: {
            Text("Instagram without Reels")
        } footer: {
            Text("It can be turned on only while no block runs. Log in once here; the login is kept. Instagram changes its website now and then, so this feature needs occasional updates.")
        }
        .fullScreenCover(isPresented: $showingInstagram) {
            InstagramScreen()
        }
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}

/// Settings → Advanced → Instagram strategy, the switch PLAN.md section 6 puts in a
/// debug menu, with the extra pick the "Hide" strategy needs.
struct InstagramStrategySection: View {
    @EnvironmentObject private var model: AppModel

    #if REELS_FREE
    var body: some View {
        Section {
            Picker("Instagram strategy", selection: Binding(get: { model.instagramStrategy },
                                                            set: { model.setInstagramStrategy($0) })) {
                ForEach(InstagramStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .disabled(model.isBlockRunning)
            if model.instagramStrategy == .hide {
                SelectionEditor(kind: .instagram, buttonTitle: "Pick Instagram")
                if model.instagramSelection.isEmptySelection {
                    Text("Pick only the Instagram app here (and instagram.com if your social list has it). Until then, blocks shield Instagram as usual.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if !model.reelsFreeEnabled {
                    Text("Hide only applies while Instagram without Reels is on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Instagram strategy (debug)")
        } footer: {
            Text("Shield: Instagram is shielded like every other app, and iOS may then block instagram.com in the in-app view too. Hide: Instagram is taken out of the shield and hidden from the Home Screen instead, which may also leave instagram.com open in Safari.")
        }
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}

/// "Instagram (no Reels)" on the active block screen, when the feature is on.
struct InstagramLaunchButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var showing = false

    #if REELS_FREE
    var body: some View {
        if model.reelsFreeEnabled {
            Button {
                showing = true
            } label: {
                Label("Instagram (no Reels)", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .fullScreenCover(isPresented: $showing) {
                InstagramScreen()
            }
        }
    }
    #else
    var body: some View {
        EmptyView()
    }
    #endif
}
