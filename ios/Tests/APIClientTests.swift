import XCTest

/// Answers requests from a queue and records what was sent.
final class StubTransport: HTTPTransport {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = ["Content-Type": "application/json"]
    }

    var replies: [Reply] = []
    var error: Error?
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        let reply = replies.isEmpty ? Reply(status: 500, body: "") : replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func bodyJSON(_ index: Int) throws -> [String: String] {
        let data = try XCTUnwrap(requests[index].httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }
}

enum StubReplies {
    static func auth(token: String = "jwt-token", username: String = "alice") -> StubTransport.Reply {
        .init(status: 200, body: #"{"token":"\#(token)","user":{"id":"65f0c0ffee0000000000abcd","username":"\#(username)","createdAt":"2026-11-23T10:00:00Z"}}"#)
    }

    static func error(_ status: Int, _ code: String, _ message: String = "message", headers: [String: String] = [:]) -> StubTransport.Reply {
        var all = ["Content-Type": "application/json"]
        all.merge(headers) { $1 }
        return .init(status: status, body: #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#, headers: all)
    }

    static let noContent = StubTransport.Reply(status: 204, body: "")
}

final class APIClientTests: XCTestCase {
    private var transport: StubTransport!
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        transport = StubTransport()
        client = APIClient(baseURL: URL(string: "https://api.example.com/cmx")!, transport: transport)
    }

    func testRegisterSendsTheContractAndDecodesTheReply() async throws {
        transport.replies = [StubReplies.auth()]
        let result = try await client.register(username: "alice", password: "correct horse battery", inviteCode: "code-1")
        XCTAssertEqual(result.token, "jwt-token")
        XCTAssertEqual(result.user.username, "alice")
        XCTAssertEqual(result.user.createdAt, ISO8601DateFormatter().date(from: "2026-11-23T10:00:00Z"))

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/cmx/v1/auth/register")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try transport.bodyJSON(0), ["username": "alice", "password": "correct horse battery", "inviteCode": "code-1"])
    }

    func testSignedInCallsSendTheBearerToken() async throws {
        transport.replies = [
            .init(status: 200, body: #"{"user":{"id":"1","username":"alice","createdAt":"2026-11-23T10:00:00Z"}}"#),
            StubReplies.noContent,
            StubReplies.noContent,
        ]
        let user = try await client.me(token: "abc")
        XCTAssertEqual(user.username, "alice")
        try await client.changePassword(token: "abc", currentPassword: "old password!", newPassword: "new password!")
        try await client.deleteAccount(token: "abc", password: "new password!")

        XCTAssertEqual(transport.requests.map(\.httpMethod), ["GET", "POST", "DELETE"])
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/cmx/v1/me", "/cmx/v1/me/password", "/cmx/v1/me"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer abc" })
        XCTAssertNil(transport.requests[0].httpBody)
        XCTAssertEqual(try transport.bodyJSON(1), ["currentPassword": "old password!", "newPassword": "new password!"])
        XCTAssertEqual(try transport.bodyJSON(2), ["password": "new password!"])
    }

    func testErrorMapping() async {
        let cases: [(StubTransport.Reply, APIError)] = [
            (StubReplies.error(401, "invalid_credentials"), .invalidCredentials),
            (StubReplies.error(401, "unauthorized"), .unauthorized),
            (StubReplies.error(403, "invalid_invite_code"), .invalidInviteCode),
            (StubReplies.error(403, "invalid_password"), .invalidPassword),
            (StubReplies.error(409, "username_taken"), .usernameTaken),
            (StubReplies.error(400, "invalid_request", "Usernames have 3 to 32 characters."), .invalidRequest("Usernames have 3 to 32 characters.")),
            (StubReplies.error(429, "rate_limited", "Too many attempts.", headers: ["Retry-After": "120"]), .rateLimited(retryAfter: 120, message: "Too many attempts.")),
            (.init(status: 502, body: "<html>Bad gateway</html>", headers: ["Content-Type": "text/html"]), .server(status: 502, message: nil)),
        ]
        for (reply, expected) in cases {
            transport.replies = [reply]
            do {
                _ = try await client.login(username: "alice", password: "whatever password")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? APIError, expected)
            }
        }
    }

    func testNetworkErrorsAreReadable() async {
        let cases: [(URLError.Code, APIError)] = [
            (.notConnectedToInternet, .offline),
            (.timedOut, .timedOut),
        ]
        for (code, expected) in cases {
            transport.error = URLError(code)
            do {
                _ = try await client.login(username: "a", password: "b")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? APIError, expected)
            }
        }
        transport.error = URLError(.cannotFindHost)
        do {
            _ = try await client.login(username: "a", password: "b")
            XCTFail("expected an error")
        } catch {
            guard case .cannotReachServer? = error as? APIError else { return XCTFail("\(error)") }
        }
    }

    func testAnUnexpectedSuccessBodyIsAnInvalidResponse() async {
        transport.replies = [.init(status: 200, body: "{}")]
        do {
            _ = try await client.login(username: "a", password: "b")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .invalidResponse)
        }
    }

    func testEveryErrorHasAMessage() {
        let errors: [APIError] = [.invalidCredentials, .invalidInviteCode, .usernameTaken, .invalidPassword, .unauthorized,
                                  .rateLimited(retryAfter: nil, message: nil), .invalidRequest("x"), .server(status: 500, message: nil),
                                  .offline, .timedOut, .cannotReachServer("x"), .invalidResponse]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
