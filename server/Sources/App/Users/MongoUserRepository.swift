import Foundation
import Logging
import MongoKitten

/// Accounts in MongoDB (Atlas in production), through MongoKitten.
final class MongoUserRepository: UserRepository {
    static let defaultDatabaseName = "concentrationmaxx"
    static let collectionName = "users"
    /// MongoDB's duplicate key error code.
    static let duplicateKeyCode = 11000

    private struct UserDocument: Codable {
        var _id: ObjectId
        var username: String
        var passwordHash: String
        var createdAt: Date
        var updatedAt: Date

        var record: UserRecord {
            UserRecord(id: _id.hexString, username: username, passwordHash: passwordHash,
                       createdAt: createdAt, updatedAt: updatedAt)
        }
    }

    struct WriteFailure: Error, CustomStringConvertible {
        let description: String
    }

    let database: MongoDatabase
    private var users: MongoCollection { database[Self.collectionName] }

    init(database: MongoDatabase) {
        self.database = database
    }

    /// Connects to the database in the connection string. Atlas's copied string has no
    /// database name, so "concentrationmaxx" is used when none is given.
    static func connect(uri: String, logger: Logger) async throws -> MongoUserRepository {
        var settings = try ConnectionSettings(uri)
        if settings.targetDatabase?.isEmpty ?? true {
            settings.targetDatabase = defaultDatabaseName
        }
        // Fail within seconds instead of the driver's 5-minute default.
        settings.connectTimeout = 20
        settings.maximumNumberOfConnections = 4
        let database = try await MongoDatabase.connect(to: settings, logger: logger)
        return MongoUserRepository(database: database)
    }

    func prepare() async throws {
        try await users.buildIndexes {
            UniqueIndex(named: "unique-username", field: "username")
        }
    }

    func create(username: String, passwordHash: String, at date: Date) async throws -> UserRecord {
        let document = UserDocument(_id: ObjectId(), username: username, passwordHash: passwordHash,
                                    createdAt: date, updatedAt: date)
        let reply: InsertReply
        do {
            reply = try await users.insertEncoded(document)
        } catch let failed as InsertReply {
            // MongoKitten throws the reply itself when the command reports ok != 1.
            try Self.check(failed.writeErrors?.map { ($0.code, $0.message) })
            throw WriteFailure(description: "insert failed: \(failed.debugDescription)")
        }
        // A duplicate key arrives as ok: 1 with a write error, not as a thrown error.
        try Self.check(reply.writeErrors?.map { ($0.code, $0.message) })
        return document.record
    }

    func find(username: String) async throws -> UserRecord? {
        try await users.findOne("username" == username, as: UserDocument.self)?.record
    }

    func find(id: String) async throws -> UserRecord? {
        guard let objectID = ObjectId(id) else { return nil }
        return try await users.findOne("_id" == objectID, as: UserDocument.self)?.record
    }

    func updatePasswordHash(id: String, passwordHash: String, at date: Date) async throws -> Bool {
        guard let objectID = ObjectId(id) else { return false }
        let reply = try await users.updateOne(
            where: "_id" == objectID,
            to: ["$set": ["passwordHash": passwordHash, "updatedAt": date] as Document]
        )
        try Self.check(reply.writeErrors?.map { ($0.code, $0.message) })
        return reply.updatableCount > 0
    }

    func delete(id: String) async throws -> Bool {
        guard let objectID = ObjectId(id) else { return false }
        let reply = try await users.deleteOne(where: "_id" == objectID)
        try Self.check(reply.writeErrors?.map { ($0.code, $0.message) })
        return reply.deletes > 0
    }

    /// Turns MongoDB write errors (code, message) into errors the routes understand.
    private static func check(_ errors: [(code: Int, message: String)]?) throws {
        guard let errors, !errors.isEmpty else { return }
        if errors.contains(where: { $0.code == duplicateKeyCode }) {
            throw UserRepositoryError.usernameTaken
        }
        throw WriteFailure(description: errors.map { "\($0.code): \($0.message)" }.joined(separator: "; "))
    }
}
