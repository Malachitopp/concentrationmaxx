@testable import App
import Testing
import VaporTesting

@Suite("Health")
struct HealthTests {
    @Test("GET /health returns ok")
    func health() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.GET, "health", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode(HealthResponse.self)
                #expect(body.status == "ok")
            })
        }
    }
}
