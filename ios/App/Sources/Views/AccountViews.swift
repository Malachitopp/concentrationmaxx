import SwiftUI

/// Create an account or log in (onboarding step 2). Without a server in the build, it
/// sets a password that lives only on this iPhone.
struct AccountSetupView: View {
    enum Mode: Hashable {
        case create, logIn
    }

    @EnvironmentObject private var model: AppModel
    var onDone: () -> Void

    @State private var mode: Mode = .create
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var inviteCode = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var showsSlowServerHint = false

    private var usesServer: Bool { model.account.usesServer }
    private var creating: Bool { !usesServer || mode == .create }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if usesServer {
                Picker("Account", selection: $mode) {
                    Text("Create account").tag(Mode.create)
                    Text("Log in").tag(Mode.logIn)
                }
                .pickerStyle(.segmented)

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .textFieldStyle(.roundedBorder)
            } else {
                deviceOnlyNote
            }

            SecureField(creating ? "Password (10 to 64 characters)" : "Password", text: $password)
                .textContentType(nil)
                .textFieldStyle(.roundedBorder)

            if creating {
                SecureField("Type the password again", text: $confirmation)
                    .textContentType(nil)
                    .textFieldStyle(.roundedBorder)
            }

            if usesServer, mode == .create {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }

            if creating {
                Text("You will type this password to end a block early, several times in a row, so pick one you can type reliably. A generated password is a bad fit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if showsSlowServerHint {
                Text("Still waiting for the server. A free server can take up to a minute to wake up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                submit()
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(creating ? (usesServer ? "Create account" : "Set password") : "Log in")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || !isComplete)
        }
    }

    @ViewBuilder
    private var deviceOnlyNote: some View {
        if case .invalid(let problem) = model.account.serverMode {
            Label("The server address in this build cannot be used: \(problem) Your password will live only on this iPhone.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        } else {
            Text("This build has no account server, so your password lives only on this iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var isComplete: Bool {
        guard !password.isEmpty else { return false }
        if usesServer, username.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if creating, confirmation.isEmpty { return false }
        if usesServer, mode == .create, inviteCode.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func submit() {
        error = nil
        if creating {
            if let problem = CredentialRules.passwordProblem(password) {
                error = problem
                return
            }
            guard password == confirmation else {
                error = "The two passwords are not the same."
                return
            }
            if usesServer, let problem = CredentialRules.usernameProblem(username) {
                error = problem
                return
            }
        }
        isWorking = true
        showsSlowServerHint = false
        let hint = Task {
            try await Task.sleep(nanoseconds: 6_000_000_000)
            showsSlowServerHint = true
        }
        Task {
            defer {
                hint.cancel()
                isWorking = false
                showsSlowServerHint = false
            }
            do {
                if creating {
                    try await model.createAccount(username: username, password: password, inviteCode: inviteCode)
                } else {
                    try await model.logIn(username: username, password: password)
                }
                password = ""
                confirmation = ""
                onDone()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Settings → Account → Change password. Only while no block runs.
struct ChangePasswordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $current).textContentType(nil)
                }
                Section {
                    SecureField("New password (10 to 64 characters)", text: $new).textContentType(nil)
                    SecureField("New password again", text: $confirmation).textContentType(nil)
                } footer: {
                    Text("The new password is used to end blocks early from now on.")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(current.isEmpty || new.isEmpty || confirmation.isEmpty)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func save() {
        error = nil
        if let problem = CredentialRules.passwordProblem(new) {
            error = problem
            return
        }
        guard new == confirmation else {
            error = "The two new passwords are not the same."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.changePassword(current: current, new: new)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Settings → Account → Delete account. Only while no block runs.
struct DeleteAccountView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password).textContentType(nil)
                } footer: {
                    Text(model.accountProfile?.serverBacked == true
                         ? "Your account is removed from the server for good, and your password from this iPhone."
                         : "Your password is removed from this iPhone.")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Delete account", role: .destructive) {
                        confirming = true
                    }
                    .disabled(password.isEmpty || isWorking)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { delete() }
            } message: {
                Text("This cannot be undone.")
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func delete() {
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await model.deleteAccount(password: password)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
