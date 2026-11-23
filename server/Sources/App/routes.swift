import Vapor

struct HealthResponse: Content {
    let status: String
}

func routes(_ app: Application) throws {
    app.get("health") { _ -> HealthResponse in
        HealthResponse(status: "ok")
    }
}
