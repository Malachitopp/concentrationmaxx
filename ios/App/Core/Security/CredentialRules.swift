import Foundation

/// Username and password rules. They match the server's (server/Sources/App/Auth/
/// Validation.swift), so most mistakes are caught before any request is sent.
enum CredentialRules {
    static let usernameLength = 3...32
    static let passwordLength = 10...64
    /// Bcrypt reads at most 72 bytes; the server refuses longer passwords.
    static let passwordMaxBytes = 72

    static func normalizeUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The password in the form it is sent to the server and hashed on the phone.
    static func normalizePassword(_ password: String) -> String {
        password.precomposedStringWithCanonicalMapping
    }

    /// Nil when the username is acceptable, otherwise what is wrong with it.
    static func usernameProblem(_ raw: String) -> String? {
        let username = normalizeUsername(raw)
        guard usernameLength.contains(username.count) else {
            return "Usernames have 3 to 32 characters."
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard username.allSatisfy({ allowed.contains($0) }) else {
            return "Usernames may only use letters, digits, dots, dashes and underscores."
        }
        guard let first = username.first, first.isLetter || first.isNumber else {
            return "Usernames must start with a letter or a digit."
        }
        return nil
    }

    /// Nil when the password is acceptable, otherwise what is wrong with it.
    static func passwordProblem(_ raw: String) -> String? {
        let password = normalizePassword(raw)
        guard passwordLength.contains(password.count) else {
            return "Passwords have 10 to 64 characters."
        }
        guard password.utf8.count <= passwordMaxBytes else {
            return "That password is too long. Use fewer special characters or emoji."
        }
        return nil
    }
}
