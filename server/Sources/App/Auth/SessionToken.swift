import JWT
import Vapor

/// The login token: HS256, valid for 30 days (PLAN.md section 5).
struct SessionToken: JWTPayload {
    var sub: SubjectClaim
    var iat: IssuedAtClaim
    var exp: ExpirationClaim

    init(userID: String, issuedAt: Date, lifetime: TimeInterval) {
        sub = SubjectClaim(value: userID)
        iat = IssuedAtClaim(value: issuedAt)
        exp = ExpirationClaim(value: issuedAt.addingTimeInterval(lifetime))
    }

    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }

    /// A password change ends every older session: tokens issued before the account's
    /// last update are refused. Whole seconds, because JWT times are in seconds.
    func isIssued(notBefore date: Date) -> Bool {
        iat.value.timeIntervalSince1970.rounded(.down) >= date.timeIntervalSince1970.rounded(.down)
    }
}
