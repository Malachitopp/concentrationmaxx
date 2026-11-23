import Vapor

/// An error the API reports as `{"error": {"code", "message"}}` (PLAN.md section 5).
struct APIError: AbortError, Sendable {
    let status: HTTPResponseStatus
    let code: String
    let message: String
    var headers: HTTPHeaders = [:]

    var reason: String { message }

    init(_ status: HTTPResponseStatus, code: String, message: String, headers: HTTPHeaders = [:]) {
        self.status = status
        self.code = code
        self.message = message
        self.headers = headers
    }

    static func invalidRequest(_ message: String) -> APIError {
        APIError(.badRequest, code: "invalid_request", message: message)
    }

    /// One message for an unknown username and for a wrong password.
    static let invalidCredentials = APIError(.unauthorized, code: "invalid_credentials",
                                             message: "The username or password is not correct.")
    static let unauthorized = APIError(.unauthorized, code: "unauthorized",
                                       message: "Your session has ended. Log in again.")
    static let invalidInviteCode = APIError(.forbidden, code: "invalid_invite_code",
                                            message: "That invite code is not valid.")
    /// A signed-in request whose password check failed (change password, delete account).
    static let invalidPassword = APIError(.forbidden, code: "invalid_password",
                                          message: "The password is not correct.")
    static let usernameTaken = APIError(.conflict, code: "username_taken",
                                        message: "That username is taken.")

    static func rateLimited(retryAfter seconds: Int) -> APIError {
        let wait = max(1, seconds)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .retryAfter, value: String(wait))
        return APIError(.tooManyRequests, code: "rate_limited",
                        message: "Too many attempts. Try again in \(Self.describe(seconds: wait)).",
                        headers: headers)
    }

    private static func describe(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

struct ErrorEnvelope: Content {
    struct Body: Content {
        var code: String
        var message: String
    }

    var error: Body
}

/// Turns every error into the JSON error envelope and never leaks internal details.
struct APIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return Self.response(for: error, request: request)
        }
    }

    static func response(for error: any Error, request: Request) -> Response {
        let status: HTTPResponseStatus
        let code: String
        let message: String
        var headers = HTTPHeaders()

        switch error {
        case let apiError as APIError:
            status = apiError.status
            code = apiError.code
            message = apiError.message
            headers = apiError.headers
        case is DecodingError:
            status = .badRequest
            code = "invalid_request"
            message = "The request body is missing a field or has a wrong value."
        case let abort as any AbortError:
            status = abort.status
            code = Self.code(for: abort.status)
            message = abort.status == .internalServerError ? "Something went wrong on the server." : abort.reason
            headers = abort.headers
        default:
            status = .internalServerError
            code = "internal_error"
            message = "Something went wrong on the server."
        }

        if status.code >= 500 {
            request.logger.report(error: error)
        }

        let response = Response(status: status, headers: headers)
        do {
            try response.content.encode(ErrorEnvelope(error: .init(code: code, message: message)), as: .json)
        } catch {
            response.body = .init(string: #"{"error":{"code":"internal_error","message":"Something went wrong on the server."}}"#)
            response.headers.contentType = .json
        }
        return response
    }

    static func code(for status: HTTPResponseStatus) -> String {
        switch status.code {
        case 400: return "invalid_request"
        case 401: return "unauthorized"
        case 403: return "forbidden"
        case 404: return "not_found"
        case 405: return "method_not_allowed"
        case 409: return "conflict"
        case 413: return "payload_too_large"
        case 415: return "unsupported_media_type"
        case 429: return "rate_limited"
        default: return status.code >= 500 ? "internal_error" : "error"
        }
    }
}
