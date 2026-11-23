import Vapor

/// Configures the application. Kept small and dependency-free in the skeleton.
func configure(_ app: Application) async throws {
    // Hosting platforms pass the port in $PORT; default to 8080 like the Dockerfile.
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    try routes(app)
}
