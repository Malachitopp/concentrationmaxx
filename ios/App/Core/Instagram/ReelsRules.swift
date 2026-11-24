import Foundation

/// Which Instagram pages the Reels-free web view refuses (PLAN.md section 6). The rules
/// live in bundled files so they can be updated when Instagram changes its site:
///   reels-rules.json          paths the web view refuses to open (layer 2)
///   reels-content-rules.json  a WKContentRuleList that blocks Reels requests (layer 1)
///   reels-filter.js           a script that bounces in-page route changes (layer 3)
struct ReelsRules: Codable, Equatable {
    static let rulesFile = "reels-rules"
    static let contentRulesFile = "reels-content-rules"
    static let scriptFile = "reels-filter"
    static let scriptMessageName = "cmxReelsBlocked"

    var version: Int
    var instagramHosts: [String]
    /// `/reels/…`, `/reel/…`, `/explore/…`
    var blockedFirstSegments: [String]
    /// `/<profile>/reels/…`, the Reels tab of a profile.
    var blockedSecondSegments: [String]
    var feedURL: URL

    func isInstagram(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return instagramHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// True for Instagram pages that show Reels or Explore.
    func isBlocked(_ url: URL) -> Bool {
        guard isInstagram(url) else { return false }
        let segments = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        if let first = segments.first, blockedFirstSegments.contains(first) {
            return true
        }
        if segments.count > 1, blockedSecondSegments.contains(segments[1]) {
            return true
        }
        return false
    }

    enum LoadError: Error, LocalizedError {
        case missing(String)
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .missing(let name): return "The Reels filter file \(name) is missing from this build."
            case .invalid(let name): return "The Reels filter file \(name) is not valid."
            }
        }
    }

    static func load(from bundle: Bundle) throws -> ReelsRules {
        let data = try resource(rulesFile, "json", in: bundle)
        do {
            return try JSONDecoder().decode(ReelsRules.self, from: data)
        } catch {
            throw LoadError.invalid("\(rulesFile).json")
        }
    }

    /// The JSON for WKContentRuleListStore.
    static func contentRuleList(from bundle: Bundle) throws -> String {
        let data = try resource(contentRulesFile, "json", in: bundle)
        guard (try? JSONSerialization.jsonObject(with: data)) is [Any], let text = String(data: data, encoding: .utf8) else {
            throw LoadError.invalid("\(contentRulesFile).json")
        }
        return text
    }

    /// The injected script, with the blocked path lists filled in from these rules.
    func script(from bundle: Bundle) throws -> String {
        let data = try Self.resource(Self.scriptFile, "js", in: bundle)
        guard let template = String(data: data, encoding: .utf8),
              template.contains("__CMX_BLOCKED_FIRST__"), template.contains("__CMX_BLOCKED_SECOND__") else {
            throw LoadError.invalid("\(Self.scriptFile).js")
        }
        return template
            .replacingOccurrences(of: "__CMX_BLOCKED_FIRST__", with: try Self.jsonArray(blockedFirstSegments))
            .replacingOccurrences(of: "__CMX_BLOCKED_SECOND__", with: try Self.jsonArray(blockedSecondSegments))
    }

    private static func jsonArray(_ values: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(values.map { $0.lowercased() }), as: UTF8.self)
    }

    private static func resource(_ name: String, _ ext: String, in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else {
            throw LoadError.missing("\(name).\(ext)")
        }
        return data
    }
}
