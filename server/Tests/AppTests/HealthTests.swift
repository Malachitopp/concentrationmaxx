@testable import App
import Testing
import VaporTesting

@Suite("Health and errors", .serialized)
struct HealthTests {
    @Test("GET /health returns ok")
    func health() async throws {
        try await withTestApp { app, _, _ in
            try await app.send(.GET, "health") { res async throws in
                #expect(res.status == .ok)
                #expect(try res.content.decode(HealthResponse.self).status == "ok")
            }
        }
    }

    @Test("Unknown routes use the error envelope")
    func notFound() async throws {
        try await withTestApp { app, _, _ in
            try await app.send(.GET, "v1/nothing-here") { res async throws in
                #expect(res.status == .notFound)
                #expect(try res.errorCode() == "not_found")
                #expect(res.headers.contentType == .json)
            }
        }
    }

    @Test("A malformed body is a 400 with the error envelope")
    func malformedBody() async throws {
        try await withTestApp { app, _, _ in
            try await app.send(.POST, "v1/auth/login", json: ["username": "someone"]) { res async throws in
                #expect(res.status == .badRequest)
                #expect(try res.errorCode() == "invalid_request")
            }
        }
    }
}
