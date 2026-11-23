import SwiftUI

/// The running block (PLAN.md section 4): countdown and end time, plus the ways out.
struct ActiveBlockView: View {
    @EnvironmentObject private var model: AppModel
    let session: BlockSession

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 6) {
                        Text(DurationText.countdown(session.remaining(at: context.date)))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("Blocked until \(ShieldContent.endDescription(session.end, now: context.date))")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 10) {
                    statusRow(session.messagingBlocked ? "Messaging apps are blocked" : "Messaging apps are open",
                              symbol: session.messagingBlocked ? "message.badge.filled.fill" : "message")
                    statusRow(session.strictMode ? "Strict mode: apps cannot be deleted, the clock stays automatic" : "Strict mode is off",
                              symbol: session.strictMode ? "lock.shield" : "shield.slash")
                    statusRow("Phone calls are never blocked", symbol: "phone")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 12) {
                    extendMenu
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .task(id: session.end) {
            // Lift the block the moment it ends while the app is open.
            let delay = session.end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if !Task.isCancelled {
                model.countdownFinished()
            }
        }
    }

    private var extendMenu: some View {
        let options = session.availableExtensions(now: Date())
        return Menu {
            ForEach(options, id: \.self) { minutes in
                Button("+ \(DurationText.minutes(minutes))") {
                    model.extendBlock(minutes: minutes)
                }
            }
        } label: {
            Label("Extend block", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(options.isEmpty)
    }

    private func statusRow(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
    }
}
