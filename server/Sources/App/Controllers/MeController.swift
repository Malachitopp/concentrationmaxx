import Vapor

/// GET /v1/me, POST /v1/me/password and DELETE /v1/me (Bearer token).
struct MeController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let me = routes.grouped("me")
        me.get(use: show)
        me.post("password", use: changePassword)
        me.delete(use: delete)
    }

    @Sendable
    func show(req: Request) async throws -> MeResponse {
        MeResponse(user: UserDTO(try await req.authenticatedUser()))
    }

    /// `{currentPassword, newPassword}` → `204`. Every earlier token stops working; the
    /// app logs in again with the new password.
    @Sendable
    func changePassword(req: Request) async throws -> HTTPStatus {
        let services = req.appServices
        let user = try await req.authenticatedUser()
        try await services.limiter.hit("account:\(user.id)", rule: services.config.rateLimits.accountActionsPerUser)

        let body = try req.content.decode(ChangePasswordRequest.self)
        guard try await services.hasher.verify(body.currentPassword, against: user.passwordHash) else {
            throw APIError.invalidPassword
        }
        try Validation.password(body.newPassword)

        let hash = try await services.hasher.hash(body.newPassword)
        guard try await services.repository.updatePasswordHash(id: user.id, passwordHash: hash, at: services.now()) else {
            throw APIError.unauthorized
        }
        req.logger.info("Password changed")
        return .noContent
    }

    /// `{password}` → `204`. Removes the account for good.
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let services = req.appServices
        let user = try await req.authenticatedUser()
        try await services.limiter.hit("account:\(user.id)", rule: services.config.rateLimits.accountActionsPerUser)

        let body = try req.content.decode(DeleteAccountRequest.self)
        guard try await services.hasher.verify(body.password, against: user.passwordHash) else {
            throw APIError.invalidPassword
        }
        _ = try await services.repository.delete(id: user.id)
        req.logger.info("Account deleted")
        return .noContent
    }
}
