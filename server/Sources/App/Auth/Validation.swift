import Foundation

/// Rules for usernames and passwords. The iOS app applies the same rules.
enum Validation {
    static let usernameLength = 3...32
    static let passwordLength = 10...64
    /// Bcrypt only reads the first 72 bytes of a password, so longer ones are refused
    /// instead of being silently cut.
    static let passwordMaxBytes = 72

    /// Lowercases and trims, so "Alice" and "alice " are the same account.
    static func normalizeUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns the normalised username or throws a 400 with a readable message.
    static func username(_ raw: String) throws -> String {
        let username = normalizeUsername(raw)
        guard usernameLength.contains(username.count) else {
            throw APIError.invalidRequest("Usernames have 3 to 32 characters.")
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        guard username.allSatisfy({ allowed.contains($0) }) else {
            throw APIError.invalidRequest("Usernames may only use letters, digits, dots, dashes and underscores.")
        }
        guard let first = username.first, first.isLetter || first.isNumber else {
            throw APIError.invalidRequest("Usernames must start with a letter or a digit.")
        }
        return username
    }

    static func password(_ password: String) throws {
        guard passwordLength.contains(password.count) else {
            throw APIError.invalidRequest("Passwords have 10 to 64 characters.")
        }
        guard password.utf8.count <= passwordMaxBytes else {
            throw APIError.invalidRequest("That password is too long. Use fewer special characters or emoji.")
        }
    }

    /// Compares two strings in time that does not depend on where they differ.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            difference |= a ^ b
        }
        return difference == 0
    }
}
