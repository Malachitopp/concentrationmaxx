import NIOPosix
import Vapor

/// Hashes and checks passwords. Bcrypt is slow on purpose, so it runs on the thread
/// pool instead of an event loop.
protocol PasswordHashing: Sendable {
    func hash(_ password: String) async throws -> String
    func verify(_ password: String, against hash: String) async throws -> Bool
}

struct BcryptPasswordHashing: PasswordHashing {
    let cost: Int
    let threadPool: NIOThreadPool

    func hash(_ password: String) async throws -> String {
        let cost = self.cost
        return try await threadPool.runIfActive {
            try Bcrypt.hash(password, cost: cost)
        }
    }

    func verify(_ password: String, against hash: String) async throws -> Bool {
        try await threadPool.runIfActive {
            try Bcrypt.verify(password, created: hash)
        }
    }
}
