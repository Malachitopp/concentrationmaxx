import JWT
import Vapor

/// Everything the routes need, built once in `configure`.
struct AppServices: Sendable {
    var config: ServerConfig
    var repository: any UserRepository
    var hasher: any PasswordHashing
    var limiter: RateLimiter
    /// A bcrypt hash of random text, checked when a login names an unknown user, so
    /// both failures take the same time.
    var dummyHash: String
    var now: @Sendable () -> Date
}

private struct AppServicesKey: StorageKey {
    typealias Value = AppServices
}

extension Application {
    var appServices: AppServices {
        get {
            guard let services = storage[AppServicesKey.self] else {
                fatalError("configure(_:) has not set up the services")
            }
            return services
        }
        set { storage[AppServicesKey.self] = newValue }
    }
}

extension Request {
    var appServices: AppServices { application.appServices }

    /// The client address used for rate limiting. Behind a proxy, set
    /// CLIENT_IP_HEADER to the header the host fills in; for a comma-separated list
    /// the last entry is used, which is the one the host's own proxy added.
    var clientKey: String {
        if let header = appServices.config.clientIPHeader,
           let value = headers.first(name: header) {
            let entries = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let last = entries.last {
                return last
            }
        }
        return remoteAddress?.ipAddress ?? "unknown"
    }

    /// The signed-in user for a Bearer token, or a 401.
    func authenticatedUser() async throws -> UserRecord {
        let token: SessionToken
        do {
            token = try await jwt.verify(as: SessionToken.self)
        } catch {
            throw APIError.unauthorized
        }
        guard let user = try await appServices.repository.find(id: token.sub.value),
              token.isIssued(notBefore: user.updatedAt) else {
            throw APIError.unauthorized
        }
        return user
    }

    func issueToken(for user: UserRecord) async throws -> String {
        let token = SessionToken(userID: user.id, issuedAt: appServices.now(), lifetime: appServices.config.tokenLifetime)
        return try await jwt.sign(token)
    }
}
