import Foundation

/// A stored account: `{ _id, username, passwordHash, createdAt, updatedAt }` and
/// nothing else (PLAN.md section 5).
struct UserRecord: Sendable, Equatable {
    var id: String
    var username: String
    var passwordHash: String
    var createdAt: Date
    var updatedAt: Date
}

enum UserRepositoryError: Error, Equatable {
    case usernameTaken
}

/// Storage for accounts. Route tests use the in-memory version; production uses
/// MongoDB through MongoKitten.
protocol UserRepository: Sendable {
    /// Creates indexes and anything else storage needs before serving requests.
    func prepare() async throws
    /// Throws `UserRepositoryError.usernameTaken` for a duplicate username.
    func create(username: String, passwordHash: String, at date: Date) async throws -> UserRecord
    func find(username: String) async throws -> UserRecord?
    func find(id: String) async throws -> UserRecord?
    /// Returns false when the user no longer exists.
    func updatePasswordHash(id: String, passwordHash: String, at date: Date) async throws -> Bool
    /// Returns false when the user no longer exists.
    func delete(id: String) async throws -> Bool
}

actor InMemoryUserRepository: UserRepository {
    private var users: [String: UserRecord] = [:]
    private var nextID = 1

    func prepare() async throws {}

    func create(username: String, passwordHash: String, at date: Date) async throws -> UserRecord {
        guard !users.values.contains(where: { $0.username == username }) else {
            throw UserRepositoryError.usernameTaken
        }
        let id = String(format: "%024x", nextID)
        nextID += 1
        let user = UserRecord(id: id, username: username, passwordHash: passwordHash, createdAt: date, updatedAt: date)
        users[id] = user
        return user
    }

    func find(username: String) async throws -> UserRecord? {
        users.values.first { $0.username == username }
    }

    func find(id: String) async throws -> UserRecord? {
        users[id]
    }

    func updatePasswordHash(id: String, passwordHash: String, at date: Date) async throws -> Bool {
        guard var user = users[id] else { return false }
        user.passwordHash = passwordHash
        user.updatedAt = date
        users[id] = user
        return true
    }

    func delete(id: String) async throws -> Bool {
        users.removeValue(forKey: id) != nil
    }

    var count: Int { users.count }
}
