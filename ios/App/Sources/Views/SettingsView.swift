import FamilyControls
import SwiftUI

/// Settings (PLAN.md section 4). Block lists and the block-related options are locked
/// while a block is running.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeAccess
    @Environment(\.dismiss) private var dismiss
    @State private var showingChangePassword = false
    @State private var showingDeleteAccount = false
    @State private var confirmingLogOut = false

    var body: some View {
        NavigationStack {
            Form {
                if model.isBlockRunning {
                    Section {
                        Label("Block lists and block options are locked while a block runs.", systemImage: "lock.fill")
                            .font(.callout)
                    }
                }

                Section {
                    SelectionEditor(kind: .social)
                } header: {
                    Text("Social apps")
                } footer: {
                    Text("TikTok, Instagram, X, Reddit, Snapchat, or whole categories. iOS can shield at most 50 individual apps per list.")
                }

                Section {
                    SelectionEditor(kind: .messaging)
                } header: {
                    Text("Messaging apps")
                } footer: {
                    Text("Blocked only when a block has \"also block messaging\" on. Apple Messages must first be removed from Screen Time's \"Always Allowed\" list to be blockable.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { model.unlockEntries },
                        set: { model.setUnlockEntries($0) }
                    ), in: BlockRules.unlockEntriesRange) {
                        LabeledContent("Password entries to end early", value: "\(model.unlockEntries)")
                    }
                    .disabled(model.isBlockRunning)
                } header: {
                    Text("Unlocking")
                } footer: {
                    Text("Ending a block early takes this many correct entries in a row. Unblocking messaging takes one. Five wrong entries lock the unlock screen for five minutes.")
                }

                Section {
                    Toggle("Strict mode", isOn: Binding(
                        get: { model.strictMode },
                        set: { model.setStrictMode($0) }
                    ))
                    .disabled(model.isBlockRunning)
                } footer: {
                    Text("During a block, apps cannot be deleted and the date and time must stay automatic, which closes the two cheapest ways out.")
                }

                accountSection

                Section("Advanced") {
                    NavigationLink("Diagnostics") {
                        DiagnosticsView()
                    }
                    LabeledContent("Screen Time access", value: screenTime.statusDescription)
                    if !screenTime.isApproved {
                        Button("Allow Screen Time access") {
                            Task { await screenTime.request() }
                        }
                    }
                    LabeledContent("Shared storage", value: model.storageProblem == nil ? "OK" : "Unavailable")
                    if let problem = model.storageProblem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                    LabeledContent("Version", value: AppInfo.versionDescription)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingChangePassword) {
                ChangePasswordView()
            }
            .sheet(isPresented: $showingDeleteAccount) {
                DeleteAccountView()
            }
            .confirmationDialog("Log out?", isPresented: $confirmingLogOut, titleVisibility: .visible) {
                Button("Log out", role: .destructive) {
                    model.logOut()
                    dismiss()
                }
            } message: {
                Text("Your password is removed from this iPhone. You set it up again before the next block.")
            }
            .task {
                await model.refreshServerStatus()
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let profile = model.accountProfile {
                LabeledContent("Account", value: profile.serverBacked ? profile.username : "On this iPhone only")
                if profile.serverBacked {
                    LabeledContent("Server", value: serverStatusText)
                }
            }
            Button("Change password") { showingChangePassword = true }
                .disabled(model.isBlockRunning)
            Button("Log out") { confirmingLogOut = true }
                .disabled(model.isBlockRunning)
            Button("Delete account", role: .destructive) { showingDeleteAccount = true }
                .disabled(model.isBlockRunning)
        } header: {
            Text("Account")
        } footer: {
            if model.isBlockRunning {
                Text("Changing the password, logging out and deleting the account are locked while a block runs. A forgotten password means the block runs until it ends.")
            } else {
                Text("The server stores only your username and a bcrypt hash of your password.")
            }
        }
    }

    private var serverStatusText: String {
        switch model.serverStatus {
        case .active: return "Signed in"
        case .signedOut: return "Session ended, log in again to change the account"
        case .unreachable: return "Cannot be reached right now"
        case .notApplicable: return "Not used"
        }
    }
}

/// The extensions' trail of events (they cannot be watched in a debugger without a
/// Mac). Useful for the real-device checks in PLAN.md section 10.
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var events: [DiagnosticEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                Text("No events yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(events.enumerated().reversed()), id: \.offset) { _, event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.source.rawValue)
                            .font(.caption.bold())
                        Spacer()
                        Text(event.date, format: .dateTime.month().day().hour().minute().second())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(event.message)
                        .font(.callout)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    model.diagnostics?.clear()
                    reload()
                }
                .disabled(events.isEmpty)
            }
        }
        .refreshable { reload() }
        .onAppear { reload() }
    }

    private func reload() {
        events = model.diagnostics?.events() ?? []
    }
}

enum AppInfo {
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
