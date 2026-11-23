import Foundation

/// Location of the files the app and its extensions share.
enum SharedStorage {
    /// The App Group container, which every target can read and write.
    /// Throws when the container is unavailable (missing entitlement or provisioning).
    static func directory() throws -> URL {
        guard let identifier = AppGroup.identifier else {
            throw BlockError.storageUnavailable("no App Group identifier in Info.plist")
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw BlockError.storageUnavailable("App Group \(identifier) is not available to this build")
        }
        let directory = container.appendingPathComponent("ConcentrationMaxx", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes atomically. Files stay readable after the first unlock following a
    /// reboot, which is when the monitor extension may need them.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Session record

protocol SessionStoring: AnyObject {
    /// Returns nil when no block is running. Throws when the record exists but cannot
    /// be read, so callers never mistake "unreadable" for "no block".
    func load() throws -> BlockSession?
    func save(_ session: BlockSession) throws
    func clear() throws
}

final class FileSessionStore: SessionStoring {
    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("block-session.json")
    }

    /// The store in the App Group container.
    static func shared() throws -> FileSessionStore {
        FileSessionStore(directory: try SharedStorage.directory())
    }

    func load() throws -> BlockSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(BlockSession.self, from: data)
    }

    func save(_ session: BlockSession) throws {
        try SharedStorage.write(try encoder.encode(session), to: fileURL)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

/// Used by tests and SwiftUI previews.
final class InMemorySessionStore: SessionStoring {
    var session: BlockSession?
    var loadError: Error?
    var saveError: Error?
    var clearError: Error?

    init(session: BlockSession? = nil) {
        self.session = session
    }

    func load() throws -> BlockSession? {
        if let loadError { throw loadError }
        return session
    }

    func save(_ session: BlockSession) throws {
        if let saveError { throw saveError }
        self.session = session
    }

    func clear() throws {
        if let clearError { throw clearError }
        session = nil
    }
}

// MARK: - Diagnostics

/// Where an event came from. The extensions cannot be watched in a debugger on a
/// phone without a Mac, so they leave a short trail here that Settings → Advanced shows.
enum DiagnosticSource: String, Codable {
    case app, monitor, shieldAction, shieldConfiguration, intent
}

struct DiagnosticEvent: Codable, Equatable {
    var date: Date
    var source: DiagnosticSource
    var message: String
}

protocol DiagnosticsLogging: AnyObject {
    func record(_ source: DiagnosticSource, _ message: String)
}

/// A small, capped event log in the App Group. It never leaves the device and holds no
/// personal data (no passwords, no app names; Screen Time tokens are opaque anyway).
final class DiagnosticsLog: DiagnosticsLogging {
    let fileURL: URL
    let limit: Int
    private let now: () -> Date

    init(directory: URL, limit: Int = 200, now: @escaping () -> Date = Date.init) {
        fileURL = directory.appendingPathComponent("diagnostics.json")
        self.limit = limit
        self.now = now
    }

    /// The log in the App Group container, or nil if the container is unavailable.
    static func shared() -> DiagnosticsLog? {
        guard let directory = try? SharedStorage.directory() else { return nil }
        return DiagnosticsLog(directory: directory)
    }

    func record(_ source: DiagnosticSource, _ message: String) {
        var events = self.events()
        events.append(DiagnosticEvent(date: now(), source: source, message: message))
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        if let data = try? JSONEncoder().encode(events) {
            try? SharedStorage.write(data, to: fileURL)
        }
    }

    func events() -> [DiagnosticEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
