import Foundation
import Security

/// What the app keeps on the phone to check the password during a block, with no
/// network (PLAN.md section 3): a PBKDF2-HMAC-SHA256 key with a random salt and a high
/// iteration count. The password itself is never stored.
struct PasswordVerifier: Codable, Equatable {
    static let currentVersion = 1
    /// OWASP's recommendation for PBKDF2-HMAC-SHA256 (2023). About a quarter of a
    /// second per check on a recent iPhone, run off the main thread.
    static let defaultIterations = 600_000
    static let saltLength = 16
    static let keyLength = 32

    var version: Int
    var iterations: Int
    var salt: Data
    var key: Data

    enum Failure: Error {
        case randomBytesUnavailable(OSStatus)
    }

    static func make(password: String,
                     iterations: Int = defaultIterations,
                     salt: Data? = nil) throws -> PasswordVerifier {
        let salt = try salt ?? randomBytes(count: saltLength)
        let key = try PBKDF2.sha256(password: encode(password), salt: salt, iterations: iterations, keyLength: keyLength)
        return PasswordVerifier(version: currentVersion, iterations: iterations, salt: salt, key: key)
    }

    /// Checks a password. Slow on purpose; call it off the main thread.
    func matches(_ password: String) -> Bool {
        guard let candidate = try? PBKDF2.sha256(password: Self.encode(password), salt: salt,
                                                  iterations: iterations, keyLength: key.count) else {
            return false
        }
        return Self.constantTimeEquals(candidate, key)
    }

    /// The same characters typed on different keyboards can produce different Unicode
    /// sequences, so passwords are compared in canonical (NFC) form.
    static func encode(_ password: String) -> Data {
        Data(password.precomposedStringWithCanonicalMapping.utf8)
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            difference |= a ^ b
        }
        return difference == 0
    }

    static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw Failure.randomBytesUnavailable(status) }
        return Data(bytes)
    }
}
