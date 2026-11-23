import XCTest

final class AccountServiceTests: XCTestCase {
    private var transport: StubTransport!
    private var secrets: InMemorySecretStore!
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        transport = StubTransport()
        secrets = InMemorySecretStore()
        suite = "cmx.tests.account.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func service(_ mode: AppConfig.ServerMode = .server(URL(string: "https://api.example.com")!)) -> AccountService {
        AccountService(serverMode: mode, transport: transport, secrets: secrets, defaults: defaults, verifierIterations: 1_000)
    }

    private func token() -> String? {
        (try? secrets.data(for: .authToken)).flatMap { String(data: $0, encoding: .utf8) }
    }

    func testCreatingAnAccountStoresTheTokenAndAVerifier() async throws {
        transport.replies = [StubReplies.auth(token: "t1", username: "alice")]
        let accounts = service()
        let profile = try await accounts.createAccount(username: "  Alice ", password: "correct horse battery", inviteCode: " code ")
        XCTAssertEqual(profile, AccountProfile(username: "alice", serverBacked: true))
        XCTAssertEqual(try transport.bodyJSON(0)["username"], "alice")
        XCTAssertEqual(try transport.bodyJSON(0)["inviteCode"], "code")
        XCTAssertEqual(token(), "t1")
        XCTAssertTrue(accounts.hasAccount)
        let correct = await accounts.check("correct horse battery")
        let wrong = await accounts.check("correct horse")
        XCTAssertTrue(correct)
        XCTAssertFalse(wrong)
        // The verifier is not the password.
        let stored = try XCTUnwrap(secrets.data(for: .passwordVerifier))
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("correct horse"))
    }

    func testLocalRulesAreCheckedBeforeAnyRequest() async {
        let accounts = service()
        do {
            _ = try await accounts.createAccount(username: "alice", password: "short", inviteCode: "code")
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is AccountError)
        }
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(accounts.hasAccount)
    }

    func testServerRefusalLeavesNothingBehind() async {
        transport.replies = [StubReplies.error(403, "invalid_invite_code")]
        let accounts = service()
        do {
            _ = try await accounts.createAccount(username: "alice", password: "correct horse battery", inviteCode: "wrong")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidInviteCode)
        }
        XCTAssertFalse(accounts.hasAccount)
        XCTAssertNil(token())
    }

    func testDeviceOnlyAccountNeedsNoServer() async throws {
        let accounts = service(.deviceOnly)
        XCTAssertFalse(accounts.usesServer)
        let profile = try await accounts.createAccount(username: "", password: "local password 1", inviteCode: "")
        XCTAssertFalse(profile.serverBacked)
        XCTAssertTrue(transport.requests.isEmpty)
        let correct = await accounts.check("local password 1")
        XCTAssertTrue(correct)
        do {
            _ = try await accounts.logIn(username: "x", password: "y")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AccountError, .serverNotConfigured)
        }
    }

    func testLogInStoresTheTokenAndVerifier() async throws {
        transport.replies = [StubReplies.auth(token: "t2", username: "bob")]
        let accounts = service()
        let profile = try await accounts.logIn(username: "BOB", password: "bobs password!")
        XCTAssertEqual(profile.username, "bob")
        XCTAssertEqual(token(), "t2")
        let correct = await accounts.check("bobs password!")
        XCTAssertTrue(correct)
    }

    func testChangePasswordChecksTheOldOneOnThePhoneFirst() async throws {
        transport.replies = [StubReplies.auth()]
        let accounts = service()
        _ = try await accounts.createAccount(username: "alice", password: "old password 1", inviteCode: "code")
        do {
            try await accounts.changePassword(current: "not the password", new: "new password 1")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AccountError, .wrongPassword)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testChangePasswordUpdatesServerVerifierAndToken() async throws {
        transport.replies = [StubReplies.auth(token: "t1"), StubReplies.noContent, StubReplies.auth(token: "t3")]
        let accounts = service()
        _ = try await accounts.createAccount(username: "alice", password: "old password 1", inviteCode: "code")
        try await accounts.changePassword(current: "old password 1", new: "new password 1")

        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/v1/auth/register", "/v1/me/password", "/v1/auth/login"])
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer t1")
        XCTAssertEqual(try transport.bodyJSON(2)["password"], "new password 1")
        XCTAssertEqual(token(), "t3")
        let new = await accounts.check("new password 1")
        let old = await accounts.check("old password 1")
        XCTAssertTrue(new)
        XCTAssertFalse(old)
    }

    func testAnExpiredTokenIsRenewedWithThePasswordJustTyped() async throws {
        transport.replies = [
            StubReplies.auth(token: "old-token"),
            StubReplies.error(401, "unauthorized"),
            StubReplies.auth(token: "fresh-token"),
            StubReplies.noContent,
            StubReplies.auth(token: "after-change"),
        ]
        let accounts = service()
        _ = try await accounts.createAccount(username: "alice", password: "old password 1", inviteCode: "code")
        try await accounts.changePassword(current: "old password 1", new: "new password 1")
        XCTAssertEqual(transport.requests.map { $0.url?.path },
                       ["/v1/auth/register", "/v1/me/password", "/v1/auth/login", "/v1/me/password", "/v1/auth/login"])
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "Authorization"), "Bearer fresh-token")
        XCTAssertEqual(token(), "after-change")
    }

    func testDeleteAccountRemovesEverythingFromThePhone() async throws {
        transport.replies = [StubReplies.auth(), StubReplies.noContent]
        let accounts = service()
        _ = try await accounts.createAccount(username: "alice", password: "the password 1", inviteCode: "code")
        try await accounts.deleteAccount(password: "the password 1")
        XCTAssertEqual(transport.requests.last?.httpMethod, "DELETE")
        XCTAssertFalse(accounts.hasAccount)
        XCTAssertNil(accounts.profile)
        XCTAssertTrue(secrets.items.isEmpty)
    }

    func testServerSessionCheck() async throws {
        transport.replies = [StubReplies.auth(token: "t1")]
        let accounts = service()
        _ = try await accounts.createAccount(username: "alice", password: "the password 1", inviteCode: "code")

        transport.replies = [.init(status: 200, body: #"{"user":{"id":"1","username":"alice","createdAt":"2026-11-23T10:00:00Z"}}"#)]
        let active = await accounts.checkServerSession()
        XCTAssertEqual(active, .active)

        transport.error = URLError(.notConnectedToInternet)
        let offline = await accounts.checkServerSession()
        guard case .unreachable = offline else { return XCTFail("\(offline)") }
        transport.error = nil

        transport.replies = [StubReplies.error(401, "unauthorized")]
        let ended = await accounts.checkServerSession()
        XCTAssertEqual(ended, .signedOut)
        XCTAssertNil(token())
        // The phone can still check the password with no server at all.
        let stillWorks = await accounts.check("the password 1")
        XCTAssertTrue(stillWorks)
    }
}
