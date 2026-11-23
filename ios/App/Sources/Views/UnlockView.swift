import SwiftUI
import UIKit

/// The unlock flow (PLAN.md section 4): "step 1 of 3, 2 of 3, 3 of 3". The password is
/// checked on the phone, so this works with no signal.
struct UnlockView: View {
    enum Purpose {
        case endBlock
        case unblockMessaging
        case endDamagedBlock

        var title: String {
            switch self {
            case .endBlock, .endDamagedBlock: return "End block early"
            case .unblockMessaging: return "Unblock messaging"
            }
        }

        var doneLabel: String {
            switch self {
            case .endBlock, .endDamagedBlock: return "Ending the block…"
            case .unblockMessaging: return "Unblocking messaging…"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let purpose: Purpose
    let onUnlocked: () -> Void

    @State private var machine: UnlockMachine
    @State private var password = ""
    @State private var isChecking = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var focusRequest = 0
    @State private var finished = false

    private let guardStore = UnlockGuardStore()

    init(purpose: Purpose, required: Int, onUnlocked: @escaping () -> Void) {
        self.purpose = purpose
        self.onUnlocked = onUnlocked
        _machine = State(initialValue: UnlockMachine(required: required, guardState: UnlockGuardStore().load()))
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let lockedUntil = machine.lockoutEnd(at: context.date)
                VStack(spacing: 20) {
                    header(lockedUntil: lockedUntil, now: context.date)

                    SecureEntryField(text: $password,
                                     placeholder: "Password",
                                     isEnabled: lockedUntil == nil && !isChecking && !finished,
                                     focusRequest: focusRequest) {
                        submit()
                    }
                    .frame(height: 52)

                    if let message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if isChecking {
                                ProgressView()
                            } else {
                                Text(finished ? purpose.doneLabel : "Continue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty || isChecking || lockedUntil != nil || finished)

                    Spacer()

                    Text("No paste, no AutoFill, no Face ID: type it each time. If you have forgotten your password, the block simply runs until it ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isChecking)
                }
            }
        }
        .interactiveDismissDisabled(isChecking)
        .onAppear {
            machine.refresh(at: Date())
            focusRequest += 1
        }
    }

    @ViewBuilder
    private func header(lockedUntil: Date?, now: Date) -> some View {
        VStack(spacing: 8) {
            if let lockedUntil {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("Locked for \(DurationText.countdown(lockedUntil.timeIntervalSince(now)))")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text("Five wrong entries lock the unlock screen for five minutes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(machine.required == 1 ? "Enter your password" : "Step \(machine.currentStep) of \(machine.required)")
                    .font(.title2.bold())
                Text(machine.required == 1
                     ? "One correct entry unblocks your messaging apps until the block ends."
                     : "Type your password \(machine.required) times in a row. A wrong entry starts again from step 1.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if machine.required > 1 {
                    StepDots(completed: machine.completed, total: machine.required)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard !password.isEmpty, !isChecking, !finished else { return }
        let entry = password
        password = ""
        if machine.lockoutEnd(at: Date()) != nil { return }
        isChecking = true
        Task {
            let correct = await model.account.check(entry)
            isChecking = false
            let outcome = machine.record(correct: correct, at: Date())
            guardStore.save(machine.guardState)
            handle(outcome)
        }
    }

    private func handle(_ outcome: UnlockMachine.Outcome) {
        let feedback = UINotificationFeedbackGenerator()
        switch outcome {
        case .progressed(let completed, let required):
            message = "Correct. \(required - completed) to go."
            messageIsError = false
            feedback.notificationOccurred(.success)
            focusRequest += 1
        case .unlocked:
            finished = true
            message = nil
            feedback.notificationOccurred(.success)
            onUnlocked()
            dismiss()
        case .wrong(let failuresLeft):
            message = failuresLeft == 1
                ? "Wrong password. Back to step 1. One more wrong entry locks this for 5 minutes."
                : "Wrong password. Back to step 1. \(failuresLeft) more wrong entries lock this for 5 minutes."
            messageIsError = true
            feedback.notificationOccurred(.error)
            focusRequest += 1
        case .lockedOut:
            message = "Too many wrong entries."
            messageIsError = true
            feedback.notificationOccurred(.error)
        }
    }
}

/// Filled dots for completed steps.
struct StepDots: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < completed ? Color.accentColor : Color(.tertiarySystemFill))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) of \(total) entries done")
    }
}
