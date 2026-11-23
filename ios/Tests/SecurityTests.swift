import XCTest

final class PBKDF2Tests: XCTestCase {
    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func derive(_ password: String, _ salt: String, _ iterations: Int, _ length: Int) throws -> String {
        hex(try PBKDF2.sha256(password: Data(password.utf8), salt: Data(salt.utf8), iterations: iterations, keyLength: length))
    }

    /// Published PBKDF2-HMAC-SHA256 vectors (the 64-byte ones are from RFC 7914 §11).
    func testKnownVectors() throws {
        XCTAssertEqual(try derive("password", "salt", 1, 32), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
        XCTAssertEqual(try derive("password", "salt", 2, 32), "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
        XCTAssertEqual(try derive("password", "salt", 4096, 32), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
        XCTAssertEqual(try derive("passwd", "salt", 1, 64),
                       "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
        XCTAssertEqual(try derive("Password", "NaCl", 80000, 64),
                       "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d")
    }

    func testInvalidParametersThrow() {
        XCTAssertThrowsError(try PBKDF2.sha256(password: Data(), salt: Data("s".utf8), iterations: 1, keyLength: 32))
        XCTAssertThrowsError(try PBKDF2.sha256(password: Data("p".utf8), salt: Data(), iterations: 1, keyLength: 32))
        XCTAssertThrowsError(try PBKDF2.sha256(password: Data("p".utf8), salt: Data("s".utf8), iterations: 0, keyLength: 32))
    }
}

final class PasswordVerifierTests: XCTestCase {
    func testMatchesOnlyTheRightPassword() throws {
        let verifier = try PasswordVerifier.make(password: "correct horse battery", iterations: 1_000)
        XCTAssertTrue(verifier.matches("correct horse battery"))
        XCTAssertFalse(verifier.matches("correct horse batterY"))
        XCTAssertFalse(verifier.matches(""))
        XCTAssertEqual(verifier.salt.count, PasswordVerifier.saltLength)
        XCTAssertEqual(verifier.key.count, PasswordVerifier.keyLength)
        XCTAssertEqual(verifier.version, PasswordVerifier.currentVersion)
    }

    func testRandomSaltMeansDifferentKeys() throws {
        let first = try PasswordVerifier.make(password: "same password here", iterations: 1_000)
        let second = try PasswordVerifier.make(password: "same password here", iterations: 1_000)
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.key, second.key)
    }

    func testKnownSaltGivesTheKnownKey() throws {
        let verifier = try PasswordVerifier.make(password: "password", iterations: 4096, salt: Data("salt".utf8))
        XCTAssertEqual(verifier.key.map { String(format: "%02x", $0) }.joined(),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    func testUnicodeNormalisationMakesKeyboardsAgree() throws {
        let composed = "caf\u{00E9} au lait!"     // é as one code point
        let decomposed = "cafe\u{0301} au lait!"  // e + combining accent
        let verifier = try PasswordVerifier.make(password: composed, iterations: 1_000)
        XCTAssertTrue(verifier.matches(decomposed))
    }

    func testRoundTripsThroughJSONAndUsesAHighDefaultIterationCount() throws {
        XCTAssertGreaterThanOrEqual(PasswordVerifier.defaultIterations, 600_000)
        let verifier = try PasswordVerifier.make(password: "default iterations")
        XCTAssertEqual(verifier.iterations, PasswordVerifier.defaultIterations)
        let decoded = try JSONDecoder().decode(PasswordVerifier.self, from: JSONEncoder().encode(verifier))
        XCTAssertEqual(decoded, verifier)
        XCTAssertTrue(decoded.matches("default iterations"))
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(PasswordVerifier.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3])))
        XCTAssertFalse(PasswordVerifier.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 4])))
        XCTAssertFalse(PasswordVerifier.constantTimeEquals(Data([1, 2, 3]), Data([1, 2])))
    }
}

final class CredentialRulesTests: XCTestCase {
    func testUsernames() {
        XCTAssertEqual(CredentialRules.normalizeUsername("  Alice "), "alice")
        XCTAssertNil(CredentialRules.usernameProblem("alice.b_1-x"))
        XCTAssertNotNil(CredentialRules.usernameProblem("ab"))
        XCTAssertNotNil(CredentialRules.usernameProblem(String(repeating: "a", count: 33)))
        XCTAssertNotNil(CredentialRules.usernameProblem("has space"))
        XCTAssertNotNil(CredentialRules.usernameProblem("_hidden"))
    }

    func testPasswords() {
        XCTAssertNil(CredentialRules.passwordProblem("ten chars!"))
        XCTAssertNil(CredentialRules.passwordProblem(String(repeating: "p", count: 64)))
        XCTAssertNotNil(CredentialRules.passwordProblem("nine char"))
        XCTAssertNotNil(CredentialRules.passwordProblem(String(repeating: "p", count: 65)))
        // 37 × "é" is 74 bytes of UTF-8: over bcrypt's 72-byte limit.
        XCTAssertNotNil(CredentialRules.passwordProblem(String(repeating: "\u{00E9}", count: 37)))
    }
}
