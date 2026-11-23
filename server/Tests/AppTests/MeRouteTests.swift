@testable import App
import Testing
import VaporTesting

@Suite("Signed-in account routes", .serialized)
struct MeRouteTests {
    @Test("GET /v1/me needs a valid token")
    func me() async throws {
        try await withTestApp { app, _, _ in
            let account = try await app.register("henry")
            try await app.send(.GET, "v1/me", token: account.token) { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(MeResponse.self).user.username == "henry")
            }
            try await app.send(.GET, "v1/me") { res async throws in
                #expect(res.status == .unauthorized)
                #expect(try res.errorCode() == "unauthorized")
            }
            try await app.send(.GET, "v1/me", token: "not.a.token") { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("A token signed with another secret is refused")
    func foreignToken() async throws {
        try await withTestApp { app, _, _ in
            let account = try await app.register("ivy")
            var parts = account.token.split(separator: ".").map(String.init)
            parts[2] = String(parts[2].reversed())
            try await app.send(.GET, "v1/me", token: parts.joined(separator: ".")) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Changing the password ends older sessions and swaps the password")
    func changePassword() async throws {
        try await withTestApp { app, _, clock in
            let account = try await app.register("jack")
            clock.advance(by: 10)
            try await app.send(.POST, "v1/me/password",
                               json: ChangePasswordRequest(currentPassword: TestValues.password, newPassword: TestValues.otherPassword),
                               token: account.token) { res async throws in
                #expect(res.status == .noContent)
            }
            try await app.send(.GET, "v1/me", token: account.token) { res async throws in
                #expect(res.status == .unauthorized)
            }
            let (oldStatus, _, _) = try await app.login("jack", password: TestValues.password)
            #expect(oldStatus == .unauthorized)
            let (newStatus, fresh, _) = try await app.login("jack", password: TestValues.otherPassword)
            #expect(newStatus == .ok)
            try await app.send(.GET, "v1/me", token: try #require(fresh?.token)) { res async throws in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("Changing the password checks the current one and the new one's rules")
    func changePasswordChecks() async throws {
        try await withTestApp { app, _, _ in
            let account = try await app.register("kate")
            try await app.send(.POST, "v1/me/password",
                               json: ChangePasswordRequest(currentPassword: "wrong password!", newPassword: TestValues.otherPassword),
                               token: account.token) { res async throws in
                #expect(res.status == .forbidden)
                #expect(try res.errorCode() == "invalid_password")
            }
            try await app.send(.POST, "v1/me/password",
                               json: ChangePasswordRequest(currentPassword: TestValues.password, newPassword: "short"),
                               token: account.token) { res async throws in
                #expect(res.status == .badRequest)
            }
            try await app.send(.POST, "v1/me/password",
                               json: ChangePasswordRequest(currentPassword: TestValues.password, newPassword: TestValues.otherPassword)) { res async throws in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("Deleting the account needs the password and removes it for good")
    func deleteAccount() async throws {
        try await withTestApp { app, repository, _ in
            let account = try await app.register("liam")
            try await app.send(.DELETE, "v1/me", json: DeleteAccountRequest(password: "wrong password!"), token: account.token) { res async throws in
                #expect(res.status == .forbidden)
                #expect(try res.errorCode() == "invalid_password")
            }
            #expect(await repository.count == 1)
            try await app.send(.DELETE, "v1/me", json: DeleteAccountRequest(password: TestValues.password), token: account.token) { res async throws in
                #expect(res.status == .noContent)
            }
            #expect(await repository.count == 0)
            try await app.send(.GET, "v1/me", token: account.token) { res async throws in
                #expect(res.status == .unauthorized)
            }
            let (status, _, _) = try await app.login("liam", password: TestValues.password)
            #expect(status == .unauthorized)
        }
    }
}
