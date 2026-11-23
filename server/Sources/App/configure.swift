import Foundation
import JWT
import NIOCore
import Vapor

/// Production configuration: reads the environment and connects to MongoDB.
func configure(_ app: Application) async throws {
    let config: ServerConfig
    do {
        config = try ServerConfig.load(from: ProcessInfo.processInfo.environment)
    } catch {
        app.logger.critical("\(error)")
        throw error
    }
    let repository = try await MongoUserRepository.connect(uri: config.mongoURI, logger: app.logger)
    try await configure(app, config: config, repository: repository)
}

/// Shared by production and tests, which pass an in-memory repository.
func configure(_ app: Application,
               config: ServerConfig,
               repository: any UserRepository,
               now: @escaping @Sendable () -> Date = { Date() }) async throws {
    // Hosting platforms pass the port in $PORT; the Dockerfile's default is 8080.
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080

    // ISO 8601 dates in JSON, which the iOS client decodes.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    ContentConfiguration.global.use(encoder: encoder, for: .json)
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Every error leaves as {"error": {"code", "message"}}.
    app.middleware = Middlewares()
    app.middleware.use(RouteLoggingMiddleware(logLevel: .info))
    app.middleware.use(APIErrorMiddleware())

    await app.jwt.keys.add(hmac: HMACKey(from: config.jwtSecret), digestAlgorithm: .sha256)

    try await repository.prepare()

    let hasher = BcryptPasswordHashing(cost: config.bcryptCost, threadPool: app.threadPool)
    let dummyHash = try await hasher.hash(UUID().uuidString + UUID().uuidString)
    app.appServices = AppServices(config: config,
                            repository: repository,
                            hasher: hasher,
                            limiter: RateLimiter(now: now),
                            dummyHash: dummyHash,
                            now: now)

    try routes(app)
}
