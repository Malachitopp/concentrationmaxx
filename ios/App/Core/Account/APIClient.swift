import Foundation

/// Sends one HTTP request. Injected so the client can be tested without a network.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    /// Free hosting tiers stop an idle server and take about a minute to start it again,
    /// so requests wait up to 90 seconds instead of URLSession's default 60.
    static func makeDefault() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, http)
    }
}

struct APIUser: Codable, Equatable {
    var id: String
    var username: String
    var createdAt: Date
}

struct AuthResult: Codable, Equatable {
    var token: String
    var user: APIUser
}

/// What can go wrong talking to the account server, mapped from the server's
/// `{"error": {"code", "message"}}` replies and from URLSession errors.
enum APIError: Error, Equatable, LocalizedError {
    case invalidCredentials
    case invalidInviteCode
    case usernameTaken
    /// The password given to change the password or delete the account was wrong.
    case invalidPassword
    /// The login token is missing, expired or no longer valid.
    case unauthorized
    case rateLimited(retryAfter: Int?, message: String?)
    case invalidRequest(String)
    case server(status: Int, message: String?)
    case offline
    case timedOut
    case cannotReachServer(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "The username or password is not correct."
        case .invalidInviteCode:
            return "That invite code is not valid."
        case .usernameTaken:
            return "That username is taken."
        case .invalidPassword:
            return "The password is not correct."
        case .unauthorized:
            return "Your session with the server has ended. Log in again."
        case .rateLimited(_, let message):
            return message ?? "Too many attempts. Try again in a few minutes."
        case .invalidRequest(let message):
            return message
        case .server(let status, let message):
            return message.map { "\($0) (\(status))" } ?? "The server had a problem (\(status)). Try again later."
        case .offline:
            return "You are offline. Connect to the internet and try again."
        case .timedOut:
            return "The server did not answer in time. If it was asleep it may be awake now, so try again."
        case .cannotReachServer(let detail):
            return "The server cannot be reached (\(detail))."
        case .invalidResponse:
            return "The server sent an unexpected reply."
        }
    }
}

/// The ConcentrationMaxx account API (PLAN.md section 5).
struct APIClient {
    let baseURL: URL
    let transport: HTTPTransport

    private struct RegisterBody: Encodable { var username: String; var password: String; var inviteCode: String }
    private struct LoginBody: Encodable { var username: String; var password: String }
    private struct ChangePasswordBody: Encodable { var currentPassword: String; var newPassword: String }
    private struct DeleteBody: Encodable { var password: String }
    private struct MeReply: Decodable { var user: APIUser }
    private struct ErrorReply: Decodable {
        struct Body: Decodable { var code: String; var message: String }
        var error: Body
    }

    func register(username: String, password: String, inviteCode: String) async throws -> AuthResult {
        try await decode(AuthResult.self, from: send("POST", "v1/auth/register",
                                                       body: RegisterBody(username: username, password: password, inviteCode: inviteCode)))
    }

    func login(username: String, password: String) async throws -> AuthResult {
        try await decode(AuthResult.self, from: send("POST", "v1/auth/login",
                                                       body: LoginBody(username: username, password: password)))
    }

    func me(token: String) async throws -> APIUser {
        try await decode(MeReply.self, from: send("GET", "v1/me", body: nil as LoginBody?, token: token)).user
    }

    func changePassword(token: String, currentPassword: String, newPassword: String) async throws {
        _ = try await send("POST", "v1/me/password",
                           body: ChangePasswordBody(currentPassword: currentPassword, newPassword: newPassword), token: token)
    }

    func deleteAccount(token: String, password: String) async throws {
        _ = try await send("DELETE", "v1/me", body: DeleteBody(password: password), token: token)
    }

    // MARK: Plumbing

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func makeRequest<Body: Encodable>(_ method: String, _ path: String, body: Body?, token: String?) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Body: Encodable>(_ method: String, _ path: String, body: Body?, token: String? = nil) async throws -> Data {
        let request = try makeRequest(method, path, body: body, token: token)
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw APIError.cannotReachServer(error.localizedDescription)
        }
        let (data, response) = result
        guard (200..<300).contains(response.statusCode) else {
            throw Self.map(status: response.statusCode, data: data, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    static func map(status: Int, data: Data, retryAfter: String?) -> APIError {
        let reply = try? decoder.decode(ErrorReply.self, from: data)
        let code = reply?.error.code
        let message = reply?.error.message
        switch status {
        case 400:
            return .invalidRequest(message ?? "The request was not accepted.")
        case 401:
            return code == "invalid_credentials" ? .invalidCredentials : .unauthorized
        case 403:
            switch code {
            case "invalid_invite_code": return .invalidInviteCode
            case "invalid_password": return .invalidPassword
            default: return .server(status: status, message: message)
            }
        case 409:
            return .usernameTaken
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }, message: message)
        default:
            return .server(status: status, message: message)
        }
    }

    static func map(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .cannotReachServer(error.localizedDescription)
        }
    }
}
