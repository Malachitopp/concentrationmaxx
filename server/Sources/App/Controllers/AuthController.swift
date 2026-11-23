import Vapor

/// POST /v1/auth/register and POST /v1/auth/login.
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
    }

    /// `{username, password, inviteCode}` → `201 {token, user}`.
    @Sendable
    func register(req: Request) async throws -> Response {
        let services = req.appServices
        try await services.limiter.hit("register:\(req.clientKey)", rule: services.config.rateLimits.registerPerClient)

        let body = try req.content.decode(RegisterRequest.self)
        // The repo and the server address are public, so new accounts need the code.
        guard Validation.constantTimeEquals(body.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
                                            services.config.inviteCode) else {
            throw APIError.invalidInviteCode
        }
        let username = try Validation.username(body.username)
        try Validation.password(body.password)

        let hash = try await services.hasher.hash(body.password)
        let user: UserRecord
        do {
            user = try await services.repository.create(username: username, passwordHash: hash, at: services.now())
        } catch UserRepositoryError.usernameTaken {
            throw APIError.usernameTaken
        }
        req.logger.info("Account created")
        let response = AuthResponse(token: try await req.issueToken(for: user), user: UserDTO(user))
        return try await response.encodeResponse(status: .created, for: req)
    }

    /// `{username, password}` → `200 {token, user}`. A wrong password and an unknown
    /// username get the same answer and take the same time.
    @Sendable
    func login(req: Request) async throws -> AuthResponse {
        let services = req.appServices
        let limits = services.config.rateLimits
        try await services.limiter.hit("login:\(req.clientKey)", rule: limits.loginPerClient)

        let body = try req.content.decode(LoginRequest.self)
        let username = Validation.normalizeUsername(body.username)
        let failureKey = "login-failures:\(username)"
        try await services.limiter.check(failureKey, rule: limits.loginFailuresPerUsername)

        guard let user = try await services.repository.find(username: username) else {
            _ = try? await services.hasher.verify(body.password, against: services.dummyHash)
            await services.limiter.record(failureKey, rule: limits.loginFailuresPerUsername)
            throw APIError.invalidCredentials
        }
        guard try await services.hasher.verify(body.password, against: user.passwordHash) else {
            await services.limiter.record(failureKey, rule: limits.loginFailuresPerUsername)
            throw APIError.invalidCredentials
        }
        await services.limiter.reset(failureKey)
        return AuthResponse(token: try await req.issueToken(for: user), user: UserDTO(user))
    }
}
