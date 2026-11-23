@testable import App
import Foundation
import NIOConcurrencyHelpers
import Testing
import VaporTesting

/// A clock the tests move forward by hand.
final class TestClock: Sendable {
    private let value = NIOLockedValueBox(Date())

    func now() -> Date {
        value.withLockedValue { $0 }
    }

    func advance(by seconds: TimeInterval) {
        value.withLockedValue { $0 = $0.addingTimeInterval(seconds) }
    }
}

enum TestValues {
    static let inviteCode = "let-me-in-2026"
    static let password = "correct horse battery"
    static let otherPassword = "another long password"

    static var config: ServerConfig {
        var config = ServerConfig(mongoURI: "mongodb://localhost/unused",
                                  jwtSecret: String(repeating: "k", count: 48),
                                  inviteCode: inviteCode)
        config.bcryptCost = 4
        return config
    }
}

/// Runs a test against an app wired to an in-memory user repository.
func withTestApp(_ test: (Application, InMemoryUserRepository, TestClock) async throws -> Void) async throws {
    let repository = InMemoryUserRepository()
    let clock = TestClock()
    let config = TestValues.config
    try await withApp(configure: { app in
        try await configure(app, config: config, repository: repository, now: { clock.now() })
    }) { app in
        try await test(app, repository, clock)
    }
}

extension Application {
    /// Sends a JSON request and hands the response to `check`.
    func send(_ method: HTTPMethod,
              _ path: String,
              json body: (any Encodable & Sendable)? = nil,
              token: String? = nil,
              check: (TestingHTTPResponse) async throws -> Void) async throws {
        try await testing().test(method, path, beforeRequest: { req in
            if let token {
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
            }
            if let body {
                try req.content.encode(AnyEncodable(body), as: .json)
            }
        }, afterResponse: { res async throws in
            try await check(res)
        })
    }

    /// Registers an account and returns its token.
    @discardableResult
    func register(_ username: String, password: String = TestValues.password) async throws -> AuthResponse {
        var result: AuthResponse?
        try await send(.POST, "v1/auth/register",
                       json: RegisterRequest(username: username, password: password, inviteCode: TestValues.inviteCode)) { res async throws in
            #expect(res.status == .created)
            result = try res.content.decode(AuthResponse.self)
        }
        return try #require(result)
    }

    func login(_ username: String, password: String) async throws -> (HTTPStatus, AuthResponse?, ErrorEnvelope?) {
        var outcome: (HTTPStatus, AuthResponse?, ErrorEnvelope?) = (.internalServerError, nil, nil)
        try await send(.POST, "v1/auth/login", json: LoginRequest(username: username, password: password)) { res async throws in
            if res.status == .ok {
                outcome = (res.status, try res.content.decode(AuthResponse.self), nil)
            } else {
                outcome = (res.status, nil, try? res.content.decode(ErrorEnvelope.self))
            }
        }
        return outcome
    }
}

/// Type-erases an Encodable so request bodies of any type can be passed around.
struct AnyEncodable: Encodable, Sendable {
    private let encodeBody: @Sendable (any Encoder) throws -> Void

    init(_ value: any Encodable & Sendable) {
        encodeBody = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: any Encoder) throws {
        try encodeBody(encoder)
    }
}

extension TestingHTTPResponse {
    func errorCode() throws -> String {
        try content.decode(ErrorEnvelope.self).error.code
    }
}
