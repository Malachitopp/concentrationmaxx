import FamilyControls
import SwiftUI

/// Home (PLAN.md section 4): duration, "also block messaging apps", Start.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var screenTime: ScreenTimeAccess
    @State private var minutes = 60
    @State private var blockMessaging = false
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
                Button {
                    model.startBlock(minutes: minutes, blockMessaging: blockMessaging)
                } label: {
                    Label("Start block", systemImage: "lock.fill")
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
        .onAppear {
            guard !loaded else { return }
            loaded = true
            minutes = model.settings.lastDurationMinutes
            blockMessaging = model.settings.blockMessaging && !model.messagingSelection.isEmptySelection
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
