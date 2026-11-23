import FamilyControls
import SwiftUI

/// Settings (PLAN.md section 4). Block lists and the block-related options are locked
/// while a block is running.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeAccess
    @Environment(\.dismiss) private var dismiss

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
                    Toggle("Strict mode", isOn: Binding(
                        get: { model.strictMode },
                        set: { model.setStrictMode($0) }
                    ))
                    .disabled(model.isBlockRunning)
                } footer: {
                    Text("During a block, apps cannot be deleted and the date and time must stay automatic, which closes the two cheapest ways out.")
                }

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
