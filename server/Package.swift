// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "concentrationmaxx-server",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        // 💧 Vapor 4: HTTP server, routing, Bcrypt.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
        // 🔑 JWT (HS256) for session tokens.
        .package(url: "https://github.com/vapor/jwt.git", from: "5.2.0"),
        // 🍃 MongoDB driver (MongoDB's own Swift driver is no longer developed).
        .package(url: "https://github.com/orlandos-nl/MongoKitten.git", from: "7.17.0"),
        // 🔵 SwiftNIO, used directly for the thread pool and event loops.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "MongoKitten", package: "MongoKitten"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
    ]
}
