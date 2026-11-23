import Foundation

/// Server configuration, read from environment variables (PLAN.md section 5).
/// Only `.env.example` is committed; real values live in the host's settings.
struct ServerConfig: Sendable {
    struct RateLimits: Sendable {
        var loginPerClient = RateLimiter.Rule(limit: 30, window: 10 * 60)
        var loginFailuresPerUsername = RateLimiter.Rule(limit: 10, window: 15 * 60)
        var registerPerClient = RateLimiter.Rule(limit: 10, window: 60 * 60)
        var accountActionsPerUser = RateLimiter.Rule(limit: 10, window: 15 * 60)
    }

    var mongoURI: String
    var jwtSecret: String
    var inviteCode: String
    /// Bcrypt cost factor. 12 in production; tests use the minimum (4) for speed.
    var bcryptCost: Int = 12
    /// Login tokens last 30 days.
    var tokenLifetime: TimeInterval = 30 * 24 * 60 * 60
    /// Header set by the host's proxy that carries the client's IP, used for rate
    /// limiting. Nil means the TCP peer address is used.
    var clientIPHeader: String?
    var rateLimits = RateLimits()

    enum ConfigError: Error, CustomStringConvertible {
        case missing(String)
        case invalid(String, String)

        var description: String {
            switch self {
            case .missing(let name):
                return "Environment variable \(name) is not set. See server/.env.example."
            case .invalid(let name, let reason):
                return "Environment variable \(name) is invalid: \(reason)"
            }
        }
    }

    /// Reads and checks the configuration. The server refuses to start without a
    /// database, a strong JWT secret and an invite code, because the repo is public.
    static func load(from environment: [String: String]) throws -> ServerConfig {
        func required(_ name: String) throws -> String {
            guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                throw ConfigError.missing(name)
            }
            return value
        }

        let mongoURI = try required("MONGODB_URI")
        guard mongoURI.hasPrefix("mongodb://") || mongoURI.hasPrefix("mongodb+srv://") else {
            throw ConfigError.invalid("MONGODB_URI", "it must start with mongodb:// or mongodb+srv://")
        }
        let jwtSecret = try required("JWT_SECRET")
        guard jwtSecret.utf8.count >= 32 else {
            throw ConfigError.invalid("JWT_SECRET", "use at least 32 characters of random text")
        }
        let inviteCode = try required("INVITE_CODE")

        var config = ServerConfig(mongoURI: mongoURI, jwtSecret: jwtSecret, inviteCode: inviteCode)
        if let header = environment["CLIENT_IP_HEADER"]?.trimmingCharacters(in: .whitespaces), !header.isEmpty {
            config.clientIPHeader = header
        }
        if let cost = environment["BCRYPT_COST"].flatMap(Int.init) {
            guard (10...16).contains(cost) else {
                throw ConfigError.invalid("BCRYPT_COST", "use a value from 10 to 16")
            }
            config.bcryptCost = cost
        }
        return config
    }
}
