import FamilyControls
import SwiftUI

/// Home (PLAN.md section 4): duration, "also block messaging apps", Start.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeAccess
    @State private var minutes = 60
    @State private var blockMessaging = false
    @State private var seriousMode = false
    @State private var confirmingSerious = false
    @State private var loaded = false

    var body: some View {
        Form {
            if !screenTime.isApproved {
                Section {
                    Label("Screen Time access is off, so nothing can be blocked.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if let error = screenTime.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(screenTime.isRequesting ? "Waiting for iOS…" : "Allow Screen Time access") {
                        Task { await screenTime.request() }
                    }
                    .disabled(screenTime.isRequesting)
                }
            }

            Section("Block for") {
                DurationPicker(minutes: $minutes)
            }

            Section {
                Toggle("Also block messaging apps", isOn: $blockMessaging)
                    .disabled(model.messagingSelection.isEmptySelection)
            } footer: {
                if model.messagingSelection.isEmptySelection {
                    Text("Pick your messaging apps in Settings to use this.")
                } else {
                    Text("During the block, one password entry unblocks messaging only.")
                }
            }

            Section {
                Toggle("Serious mode", isOn: $seriousMode)
            } footer: {
                Text("A serious block cannot be ended early. No password gets you out, strict mode is always on, and it runs until the timer ends.")
            }

            Section {
                Button {
                    if seriousMode {
                        // No way back once it starts, so ask first.
                        confirmingSerious = true
                    } else {
                        model.startBlock(minutes: minutes, blockMessaging: blockMessaging)
                    }
                } label: {
                    Label(seriousMode ? "Start serious block" : "Start block",
                          systemImage: seriousMode ? "lock.shield.fill" : "lock.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .disabled(!screenTime.isApproved || model.socialSelection.isEmptySelection)
            } footer: {
                if model.socialSelection.isEmptySelection {
                    Text("Pick the social apps to block in Settings first.")
                } else if seriousMode {
                    Text("This block cannot be ended early.")
                } else {
                    Text("Ending early takes your password \(model.unlockEntries) times in a row.")
                }
            }

            Section {
                LabeledContent("Social", value: model.socialSelection.summary)
                LabeledContent("Messaging", value: model.messagingSelection.summary)
            } header: {
                Text("Your lists")
            } footer: {
                Text("Phone calls are never blocked.")
            }
        }
        .confirmationDialog("Start a serious block?", isPresented: $confirmingSerious, titleVisibility: .visible) {
            Button("Block for \(DurationText.minutes(minutes)), no way out", role: .destructive) {
                model.startBlock(minutes: minutes, blockMessaging: blockMessaging, seriousMode: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your apps stay blocked for \(DurationText.minutes(minutes)). It cannot be ended early: your password will not end it, and it can be made longer but not shorter.")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            minutes = model.settings.lastDurationMinutes
            blockMessaging = model.settings.blockMessaging && !model.messagingSelection.isEmptySelection
            seriousMode = model.settings.seriousMode
        }
    }
}

/// Preset durations plus a custom one (PLAN.md section 4: 15m, 30m, 1h, 2h, 4h, custom).
struct DurationPicker: View {
    @Binding var minutes: Int
    @State private var showingCustom = false

    private var isCustom: Bool { !BlockRules.presetMinutes.contains(minutes) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(BlockRules.presetMinutes, id: \.self) { preset in
                chip(DurationText.minutes(preset), selected: minutes == preset) {
                    minutes = preset
                }
            }
            chip(isCustom ? DurationText.minutes(minutes) : "Custom", selected: isCustom) {
                showingCustom = true
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingCustom) {
            CustomDurationSheet(minutes: $minutes)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CustomDurationSheet: View {
    @Binding var minutes: Int
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 1
    @State private var extraMinutes = 0

    private var total: Int { hours * 60 + extraMinutes }
    private var isValid: Bool {
        BlockRules.isValidDuration(TimeInterval(total) * 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Picker("Hours", selection: $hours) {
                        ForEach(0...24, id: \.self) { value in
                            Text("\(value) h").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    Picker("Minutes", selection: $extraMinutes) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
                            Text("\(value) min").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Text(isValid ? "Block for \(DurationText.minutes(total))" : "Choose between 15 minutes and 24 hours.")
                    .font(.callout)
                    .foregroundStyle(isValid ? Color.secondary : Color.red)
            }
            .padding()
            .navigationTitle("Custom duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        minutes = total
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            hours = min(minutes / 60, 24)
            extraMinutes = (minutes % 60) / 5 * 5
        }
    }
}
