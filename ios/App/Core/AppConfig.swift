import Foundation

/// Build-time configuration, read from the app's Info.plist. project.yml fills the
/// Info.plist keys from build settings, and testflight.yml passes `API_BASE_URL`.
struct AppConfig: Equatable {
    /// Where accounts live (PLAN.md section 5).
    enum ServerMode: Equatable {
        /// No server configured: the password lives only on this phone.
        case deviceOnly
        /// Accounts are kept by the ConcentrationMaxx server at this base URL.
        case server(URL)
        /// A value was configured but cannot be used. The message says why.
        case invalid(String)
    }

    static let apiBaseURLKey = "CMXAPIBaseURL"

    let serverMode: ServerMode

    static let current = AppConfig(infoDictionary: Bundle.main.infoDictionary)

    init(serverMode: ServerMode) {
        self.serverMode = serverMode
    }

    init(infoDictionary: [String: Any]?) {
        self.serverMode = AppConfig.parseServerMode(infoDictionary?[AppConfig.apiBaseURLKey] as? String)
    }

    /// Parses the configured base URL. HTTPS is required (PLAN.md section 5, "HTTPS only").
    static func parseServerMode(_ raw: String?) -> ServerMode {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty, or a build setting that was never expanded, means "not configured".
        if value.isEmpty || value.hasPrefix("$(") {
            return .deviceOnly
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else {
            return .invalid("The server address \"\(value)\" is not a valid URL.")
        }
        guard scheme == "https" else {
            return .invalid("The server address must start with https:// (it is \"\(value)\").")
        }
        guard components.query == nil, components.fragment == nil else {
            return .invalid("The server address must not contain ? or # (it is \"\(value)\").")
        }
        var cleaned = components
        cleaned.scheme = "https"
        // Drop trailing slashes so paths like "/v1/me" can be appended safely.
        while cleaned.path.hasSuffix("/") {
            cleaned.path.removeLast()
        }
        guard let url = cleaned.url else {
            return .invalid("The server address \"\(value)\" is not a valid URL.")
        }
        return .server(url)
    }
}
