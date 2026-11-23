import Foundation

/// Who is signed in. The username is not secret, so it lives in UserDefaults; the
/// token and the password verifier live in the Keychain.
struct AccountProfile: Codable, Equatable {
    var username: String
    /// True for an account on the server; false for a device-only password
    /// (PLAN.md section 5, "Device-only fallback").
    var serverBacked: Bool
}

enum AccountError: Error, LocalizedError, Equatable {
    case invalidInput(String)
    case wrongPassword
    case noAccount
    case serverNotConfigured
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .wrongPassword: return "That password is not correct."
        case .noAccount: return "No account is set up on this iPhone."
        case .serverNotConfigured: return "This build has no account server."
        case .storage(let detail): return "The password could not be saved on this iPhone (\(detail))."
        }
    }
}

enum ServerSessionStatus: Equatable {
    case notApplicable
    case active
    case signedOut
    case unreachable(String)
}

/// Accounts: on the server when the build has an `API_BASE_URL`, otherwise a password
/// that lives only on this iPhone. Either way the password is checked on the phone
/// against a PBKDF2 verifier, so unlocking works offline.
final class AccountService {
    let serverMode: AppConfig.ServerMode
    private let client: APIClient?
    private let secrets: SecretStoring
    private let defaults: UserDefaults
    private let verifierIterations: Int
    private let profileKey = "account.profile"

    init(serverMode: AppConfig.ServerMode,
         transport: HTTPTransport = URLSessionTransport.makeDefault(),
         secrets: SecretStoring = KeychainSecretStore(),
         defaults: UserDefaults = .standard,
         verifierIterations: Int = PasswordVerifier.defaultIterations) {
        self.serverMode = serverMode
        if case .server(let url) = serverMode {
            client = APIClient(baseURL: url, transport: transport)
        } else {
            client = nil
        }
        self.secrets = secrets
        self.defaults = defaults
        self.verifierIterations = verifierIterations
    }

    /// Whether new accounts are created on the server.
    var usesServer: Bool { client != nil }

    var profile: AccountProfile? {
        guard let data = defaults.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(AccountProfile.self, from: data)
    }

    /// An account is usable once it has a profile and a password verifier.
    var hasAccount: Bool { profile != nil && currentVerifier() != nil }

    func currentVerifier() -> PasswordVerifier? {
        guard let data = try? secrets.data(for: .passwordVerifier) else { return nil }
        return try? JSONDecoder().decode(PasswordVerifier.self, from: data)
    }

    // MARK: Creating an account and signing in

    func createAccount(username: String, password rawPassword: String, inviteCode: String) async throws -> AccountProfile {
        let password = CredentialRules.normalizePassword(rawPassword)
        if let problem = CredentialRules.passwordProblem(password) {
            throw AccountError.invalidInput(problem)
        }
        let profile: AccountProfile
        if let client {
            if let problem = CredentialRules.usernameProblem(username) {
                throw AccountError.invalidInput(problem)
            }
            let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else {
                throw AccountError.invalidInput("Enter the invite code you were given.")
            }
            let result = try await client.register(username: CredentialRules.normalizeUsername(username),
                                                   password: password, inviteCode: code)
            try saveToken(result.token)
            profile = AccountProfile(username: result.user.username, serverBacked: true)
        } else {
            profile = AccountProfile(username: "", serverBacked: false)
        }
        try await storeVerifier(for: password)
        try save(profile)
        return profile
    }

    func logIn(username: String, password rawPassword: String) async throws -> AccountProfile {
        guard let client else { throw AccountError.serverNotConfigured }
        let password = CredentialRules.normalizePassword(rawPassword)
        let name = CredentialRules.normalizeUsername(username)
        guard !name.isEmpty, !password.isEmpty else {
            throw AccountError.invalidInput("Enter your username and password.")
        }
        let result = try await client.login(username: name, password: password)
        try saveToken(result.token)
        try await storeVerifier(for: password)
        let profile = AccountProfile(username: result.user.username, serverBacked: true)
        try save(profile)
        return profile
    }

    // MARK: Checking the password

    /// Checks a password against the on-device verifier, off the main thread.
    func check(_ password: String) async -> Bool {
        guard let verifier = currentVerifier() else { return false }
        return await Task.detached(priority: .userInitiated) {
            verifier.matches(password)
        }.value
    }

    // MARK: Changing the account (the UI only allows this while no block runs)

    func changePassword(current rawCurrent: String, new rawNew: String) async throws {
        guard let profile else { throw AccountError.noAccount }
        let current = CredentialRules.normalizePassword(rawCurrent)
        let new = CredentialRules.normalizePassword(rawNew)
        guard await check(current) else { throw AccountError.wrongPassword }
        if let problem = CredentialRules.passwordProblem(new) {
            throw AccountError.invalidInput(problem)
        }
        if profile.serverBacked {
            guard let client else { throw AccountError.serverNotConfigured }
            try await withValidToken(password: current) { token in
                try await client.changePassword(token: token, currentPassword: current, newPassword: new)
            }
            // The server now has the new password, so the phone must too, whatever happens next.
            try await storeVerifier(for: new)
            // A password change ends every earlier session on the server: sign in again.
            if let result = try? await client.login(username: profile.username, password: new) {
                try saveToken(result.token)
            } else {
                try? secrets.remove(.authToken)
            }
        } else {
            try await storeVerifier(for: new)
        }
    }

    func deleteAccount(password rawPassword: String) async throws {
        guard let profile else { throw AccountError.noAccount }
        let password = CredentialRules.normalizePassword(rawPassword)
        guard await check(password) else { throw AccountError.wrongPassword }
        if profile.serverBacked {
            guard let client else { throw AccountError.serverNotConfigured }
            try await withValidToken(password: password) { token in
                try await client.deleteAccount(token: token, password: password)
            }
        }
        wipeLocal()
    }

    func logOut() {
        wipeLocal()
    }

    /// Removes the token, the verifier and the profile from this iPhone.
    func wipeLocal() {
        for key in SecretKey.allCases {
            try? secrets.remove(key)
        }
        defaults.removeObject(forKey: profileKey)
    }

    /// Checks the saved login with GET /v1/me.
    func checkServerSession() async -> ServerSessionStatus {
        guard let client, let profile, profile.serverBacked else { return .notApplicable }
        guard let token = savedToken() else { return .signedOut }
        do {
            _ = try await client.me(token: token)
            return .active
        } catch APIError.unauthorized {
            try? secrets.remove(.authToken)
            return .signedOut
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }

    // MARK: Helpers

    /// Runs `operation` with the saved token. If the server no longer accepts it (tokens
    /// last 30 days), signs in again with the password just typed and retries once.
    private func withValidToken(password: String, _ operation: (String) async throws -> Void) async throws {
        guard let client, let profile else { throw AccountError.serverNotConfigured }
        if let token = savedToken() {
            do {
                try await operation(token)
                return
            } catch APIError.unauthorized {
                // Fall through and sign in again.
            }
        }
        let result = try await client.login(username: profile.username, password: password)
        try saveToken(result.token)
        try await operation(result.token)
    }

    private func savedToken() -> String? {
        guard let data = try? secrets.data(for: .authToken), let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            return nil
        }
        return token
    }

    private func saveToken(_ token: String) throws {
        do {
            try secrets.set(Data(token.utf8), for: .authToken)
        } catch {
            throw AccountError.storage(error.localizedDescription)
        }
    }

    private func storeVerifier(for password: String) async throws {
        let iterations = verifierIterations
        let verifier = try await Task.detached(priority: .userInitiated) {
            try PasswordVerifier.make(password: password, iterations: iterations)
        }.value
        do {
            try secrets.set(try JSONEncoder().encode(verifier), for: .passwordVerifier)
        } catch {
            throw AccountError.storage(error.localizedDescription)
        }
    }

    private func save(_ profile: AccountProfile) throws {
        do {
            defaults.set(try JSONEncoder().encode(profile), forKey: profileKey)
        } catch {
            throw AccountError.storage(error.localizedDescription)
        }
    }
}
