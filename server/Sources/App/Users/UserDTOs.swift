import Vapor

/// The public view of an account. Never includes the password hash.
struct UserDTO: Content, Equatable {
    var id: String
    var username: String
    var createdAt: Date

    init(_ user: UserRecord) {
        id = user.id
        username = user.username
        createdAt = user.createdAt
    }
}

struct RegisterRequest: Content {
    var username: String
    var password: String
    var inviteCode: String
}

struct LoginRequest: Content {
    var username: String
    var password: String
}

struct ChangePasswordRequest: Content {
    var currentPassword: String
    var newPassword: String
}

struct DeleteAccountRequest: Content {
    var password: String
}

struct AuthResponse: Content {
    var token: String
    var user: UserDTO
}

struct MeResponse: Content {
    var user: UserDTO
}

struct HealthResponse: Content {
    var status: String
}
