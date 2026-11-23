import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ -> HealthResponse in
        HealthResponse(status: "ok")
    }

    let v1 = app.grouped("v1")
    try v1.register(collection: AuthController())
    try v1.register(collection: MeController())
}
