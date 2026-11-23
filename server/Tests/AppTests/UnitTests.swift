@testable import App
import Foundation
import Testing

@Suite("Configuration")
struct ConfigTests {
    private let valid = [
        "MONGODB_URI": "mongodb+srv://user:pass@cluster0.example.mongodb.net/concentrationmaxx",
        "JWT_SECRET": String(repeating: "a", count: 32),
        "INVITE_CODE": "friends-only",
    ]

    @Test("A complete environment loads")
    func loads() throws {
        let config = try ServerConfig.load(from: valid)
        #expect(config.inviteCode == "friends-only")
        #expect(config.bcryptCost == 12)
        #expect(config.tokenLifetime == 30 * 24 * 60 * 60)
        #expect(config.clientIPHeader == nil)
    }

    @Test("Each required variable is checked", arguments: ["MONGODB_URI", "JWT_SECRET", "INVITE_CODE"])
    func missing(name: String) {
        var environment = valid
        environment[name] = "   "
        #expect(throws: ServerConfig.ConfigError.self) { try ServerConfig.load(from: environment) }
    }

    @Test("Weak or malformed values are refused")
    func invalid() {
        var shortSecret = valid
        shortSecret["JWT_SECRET"] = "too-short"
        #expect(throws: ServerConfig.ConfigError.self) { try ServerConfig.load(from: shortSecret) }

        var badURI = valid
        badURI["MONGODB_URI"] = "https://example.com"
        #expect(throws: ServerConfig.ConfigError.self) { try ServerConfig.load(from: badURI) }

        var badCost = valid
        badCost["BCRYPT_COST"] = "4"
        #expect(throws: ServerConfig.ConfigError.self) { try ServerConfig.load(from: badCost) }
    }

    @Test("Optional settings are read")
    func optional() throws {
        var environment = valid
        environment["CLIENT_IP_HEADER"] = "Fly-Client-IP"
        environment["BCRYPT_COST"] = "11"
        let config = try ServerConfig.load(from: environment)
        #expect(config.clientIPHeader == "Fly-Client-IP")
        #expect(config.bcryptCost == 11)
    }
}

@Suite("Validation")
struct ValidationTests {
    @Test("Usernames are normalised and checked")
    func usernames() throws {
        #expect(try Validation.username("  Alice.B_1-x ") == "alice.b_1-x")
        #expect(throws: APIError.self) { try Validation.username("ab") }
        #expect(throws: APIError.self) { try Validation.username(String(repeating: "a", count: 33)) }
        #expect(throws: APIError.self) { try Validation.username("bad name") }
        #expect(throws: APIError.self) { try Validation.username("_hidden") }
        #expect(throws: APIError.self) { try Validation.username("emoji😀") }
    }

    @Test("Passwords need 10 to 64 characters and at most 72 bytes")
    func passwords() throws {
        try Validation.password("ten chars!")
        try Validation.password(String(repeating: "p", count: 64))
        #expect(throws: APIError.self) { try Validation.password("nine char") }
        #expect(throws: APIError.self) { try Validation.password(String(repeating: "p", count: 65)) }
        #expect(throws: APIError.self) { try Validation.password(String(repeating: "é", count: 37)) }
    }

    @Test("Constant-time comparison")
    func constantTime() {
        #expect(Validation.constantTimeEquals("invite", "invite"))
        #expect(!Validation.constantTimeEquals("invite", "invitE"))
        #expect(!Validation.constantTimeEquals("invite", "invite-longer"))
        #expect(!Validation.constantTimeEquals("", "x"))
        #expect(Validation.constantTimeEquals("", ""))
    }
}

@Suite("Rate limiter")
struct RateLimiterTests {
    @Test("Limits within a window and resets after it")
    func windows() async throws {
        let clock = TestClock()
        let limiter = RateLimiter(now: { clock.now() })
        let rule = RateLimiter.Rule(limit: 2, window: 60)
        try await limiter.hit("k", rule: rule)
        try await limiter.hit("k", rule: rule)
        await #expect(throws: APIError.self) { try await limiter.hit("k", rule: rule) }
        try await limiter.hit("other", rule: rule)
        clock.advance(by: 61)
        try await limiter.hit("k", rule: rule)
    }

    @Test("Failures are counted separately from checks")
    func failures() async throws {
        let clock = TestClock()
        let limiter = RateLimiter(now: { clock.now() })
        let rule = RateLimiter.Rule(limit: 2, window: 60)
        try await limiter.check("user", rule: rule)
        await limiter.record("user", rule: rule)
        try await limiter.check("user", rule: rule)
        await limiter.record("user", rule: rule)
        await #expect(throws: APIError.self) { try await limiter.check("user", rule: rule) }
        await limiter.reset("user")
        try await limiter.check("user", rule: rule)
    }
}

@Suite("Session token")
struct SessionTokenTests {
    @Test("Tokens issued before the last account change are refused")
    func notBefore() {
        let issued = Date(timeIntervalSince1970: 1_800_000_000.4)
        let token = SessionToken(userID: "u", issuedAt: issued, lifetime: 60)
        #expect(token.isIssued(notBefore: Date(timeIntervalSince1970: 1_800_000_000.9)))
        #expect(token.isIssued(notBefore: Date(timeIntervalSince1970: 1_799_999_999)))
        #expect(!token.isIssued(notBefore: Date(timeIntervalSince1970: 1_800_000_001)))
    }
}
