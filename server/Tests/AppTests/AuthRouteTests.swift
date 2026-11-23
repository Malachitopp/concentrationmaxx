@testable import App
import Testing
import VaporTesting

@Suite("Register and login", .serialized)
struct AuthRouteTests {
    @Test("Register creates an account and returns a token")
    func register() async throws {
        try await withTestApp { app, repository, _ in
            let response = try await app.register("Alice")
            #expect(response.user.username == "alice")
            #expect(!response.token.isEmpty)
            #expect(await repository.count == 1)
            let stored = try #require(try await repository.find(username: "alice"))
            #expect(stored.passwordHash.hasPrefix("$2"))
            #expect(stored.passwordHash != TestValues.password)
        }
    }

    @Test("Register needs the invite code")
    func wrongInviteCode() async throws {
        try await withTestApp { app, repository, _ in
            try await app.send(.POST, "v1/auth/register",
                               json: RegisterRequest(username: "bob", password: TestValues.password, inviteCode: "guess")) { res async throws in
                #expect(res.status == .forbidden)
                #expect(try res.errorCode() == "invalid_invite_code")
            }
            #expect(await repository.count == 0)
        }
    }

    @Test("Usernames are unique regardless of case")
    func duplicateUsername() async throws {
        try await withTestApp { app, _, _ in
            try await app.register("carol")
            try await app.send(.POST, "v1/auth/register",
                               json: RegisterRequest(username: "CAROL", password: TestValues.password, inviteCode: TestValues.inviteCode)) { res async throws in
                #expect(res.status == .conflict)
                #expect(try res.errorCode() == "username_taken")
            }
        }
    }

    @Test("Register validates the username and password",
          arguments: [("x", TestValues.password), ("has space", TestValues.password), ("-dash", TestValues.password),
                      ("dave", "short"), ("dave", String(repeating: "é", count: 40))])
    func validation(username: String, password: String) async throws {
        try await withTestApp { app, repository, _ in
            try await app.send(.POST, "v1/auth/register",
                               json: RegisterRequest(username: username, password: password, inviteCode: TestValues.inviteCode)) { res async throws in
                #expect(res.status == .badRequest)
                #expect(try res.errorCode() == "invalid_request")
            }
            #expect(await repository.count == 0)
        }
    }

    @Test("Login works with any letter case")
    func login() async throws {
        try await withTestApp { app, _, _ in
            let registered = try await app.register("erin")
            let (status, response, _) = try await app.login("  ERIN ", password: TestValues.password)
            #expect(status == .ok)
            #expect(response?.user == registered.user)
        }
    }

    @Test("A wrong password and an unknown user get the same answer")
    func genericLoginFailure() async throws {
        try await withTestApp { app, _, _ in
            try await app.register("frank")
            let (wrongStatus, _, wrong) = try await app.login("frank", password: "not the password")
            let (unknownStatus, _, unknown) = try await app.login("nobody", password: "not the password")
            #expect(wrongStatus == .unauthorized)
            #expect(unknownStatus == .unauthorized)
            #expect(wrong?.error.code == "invalid_credentials")
            #expect(wrong?.error.code == unknown?.error.code)
            #expect(wrong?.error.message == unknown?.error.message)
        }
    }

    @Test("Repeated failed logins for one username are rate limited, then allowed again")
    func loginRateLimit() async throws {
        try await withTestApp { app, _, clock in
            try await app.register("grace")
            for _ in 0..<10 {
                let (status, _, _) = try await app.login("grace", password: "wrong password!")
                #expect(status == .unauthorized)
            }
            try await app.send(.POST, "v1/auth/login", json: LoginRequest(username: "grace", password: TestValues.password)) { res async throws in
                #expect(res.status == .tooManyRequests)
                #expect(try res.errorCode() == "rate_limited")
                #expect(res.headers.first(name: .retryAfter) != nil)
            }
            clock.advance(by: 15 * 60 + 1)
            let (status, _, _) = try await app.login("grace", password: TestValues.password)
            #expect(status == .ok)
        }
    }

    @Test("Registration is rate limited per client")
    func registerRateLimit() async throws {
        try await withTestApp { app, _, _ in
            for index in 0..<10 {
                try await app.register("user\(index)")
            }
            try await app.send(.POST, "v1/auth/register",
                               json: RegisterRequest(username: "user99", password: TestValues.password, inviteCode: TestValues.inviteCode)) { res async throws in
                #expect(res.status == .tooManyRequests)
            }
        }
    }
}
