@testable import App
import Foundation
import Logging
import Testing

/// Runs against a real MongoDB when MONGODB_TEST_URI is set (server-ci starts one as a
/// service container). The database named in the URI is dropped first.
@Suite("MongoDB user repository", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["MONGODB_TEST_URI"] != nil, "MONGODB_TEST_URI is not set"))
struct MongoRepositoryTests {
    private func makeRepository() async throws -> MongoUserRepository {
        let uri = try #require(ProcessInfo.processInfo.environment["MONGODB_TEST_URI"])
        let repository = try await MongoUserRepository.connect(uri: uri, logger: Logger(label: "mongo-tests"))
        try await repository.database.drop()
        try await repository.prepare()
        return repository
    }

    @Test("Create, find, update and delete")
    func lifecycle() async throws {
        let repository = try await makeRepository()
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let user = try await repository.create(username: "mia", passwordHash: "$2b$04$hash", at: created)
        #expect(user.username == "mia")
        #expect(user.id.count == 24)

        let byName = try #require(try await repository.find(username: "mia"))
        #expect(byName == user)
        #expect(try await repository.find(id: user.id) == user)
        #expect(try await repository.find(username: "nobody") == nil)
        #expect(try await repository.find(id: "not-an-object-id") == nil)

        let updated = created.addingTimeInterval(60)
        #expect(try await repository.updatePasswordHash(id: user.id, passwordHash: "$2b$04$other", at: updated))
        let afterUpdate = try #require(try await repository.find(id: user.id))
        #expect(afterUpdate.passwordHash == "$2b$04$other")
        #expect(afterUpdate.updatedAt == updated)
        #expect(afterUpdate.createdAt == created)

        #expect(try await repository.delete(id: user.id))
        #expect(try await repository.find(id: user.id) == nil)
        #expect(try await repository.delete(id: user.id) == false)
        #expect(try await repository.updatePasswordHash(id: user.id, passwordHash: "x", at: updated) == false)
    }

    @Test("The unique index rejects a duplicate username")
    func duplicate() async throws {
        let repository = try await makeRepository()
        _ = try await repository.create(username: "noah", passwordHash: "h", at: Date())
        await #expect(throws: UserRepositoryError.usernameTaken) {
            _ = try await repository.create(username: "noah", passwordHash: "h2", at: Date())
        }
    }
}
