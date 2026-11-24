import XCTest

final class ReelsRulesTests: XCTestCase {
    private var bundle: Bundle { Bundle(for: ReelsRulesTests.self) }

    private func rules() throws -> ReelsRules {
        try ReelsRules.load(from: bundle)
    }

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testTheBundledRulesLoad() throws {
        let rules = try rules()
        XCTAssertEqual(rules.feedURL, url("https://www.instagram.com/"))
        XCTAssertEqual(Set(rules.blockedFirstSegments), ["reels", "reel", "explore"])
        XCTAssertEqual(Set(rules.blockedSecondSegments), ["reels", "reel"])
    }

    /// Layer 2: the navigation delegate refuses these pages.
    func testReelsAndExplorePagesAreRefused() throws {
        let rules = try rules()
        for blocked in ["https://www.instagram.com/reels/",
                        "https://www.instagram.com/reels",
                        "https://www.instagram.com/reel/C1a2b3/",
                        "https://www.instagram.com/REELS/",
                        "https://www.instagram.com/explore/",
                        "https://www.instagram.com/explore/tags/cats/",
                        "https://www.instagram.com/natgeo/reels/",
                        "https://www.instagram.com/natgeo/reel/C1a2b3/",
                        "https://m.instagram.com/reels/",
                        "https://instagram.com/reel/x?igsh=abc"] {
            XCTAssertTrue(rules.isBlocked(url(blocked)), blocked)
        }
    }

    func testTheFeedMessagesProfilesAndPostsStayOpen() throws {
        let rules = try rules()
        for open in ["https://www.instagram.com/",
                     "https://www.instagram.com/direct/inbox/",
                     "https://www.instagram.com/direct/t/123/",
                     "https://www.instagram.com/natgeo/",
                     "https://www.instagram.com/p/C1a2b3/",
                     "https://www.instagram.com/stories/natgeo/123/",
                     "https://www.instagram.com/accounts/login/",
                     "https://example.com/reels/",
                     "https://notinstagram.com/reels/"] {
            XCTAssertFalse(rules.isBlocked(url(open)), open)
        }
        XCTAssertTrue(rules.isInstagram(url("https://www.instagram.com/")))
        XCTAssertFalse(rules.isInstagram(url("https://evilinstagram.com/")))
    }

    /// Layer 1: the content rule list. The url-filter patterns are a subset of regular
    /// expressions, so NSRegularExpression checks them on sample requests.
    func testContentRulesBlockReelsRequestsOnly() throws {
        let json = try ReelsRules.contentRuleList(from: bundle)
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertFalse(entries.isEmpty)

        var blockPatterns: [NSRegularExpression] = []
        for entry in entries {
            let trigger = try XCTUnwrap(entry["trigger"] as? [String: Any])
            let action = try XCTUnwrap(entry["action"] as? [String: Any])
            let filter = try XCTUnwrap(trigger["url-filter"] as? String, "every rule needs a url-filter")
            let type = try XCTUnwrap(action["type"] as? String)
            XCTAssertTrue(["block", "css-display-none"].contains(type))
            if type == "block" {
                blockPatterns.append(try NSRegularExpression(pattern: filter))
            }
        }

        func isBlocked(_ string: String) -> Bool {
            blockPatterns.contains { $0.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil }
        }
        XCTAssertTrue(isBlocked("https://www.instagram.com/api/v1/clips/home/"))
        XCTAssertTrue(isBlocked("https://i.instagram.com/api/v1/clips/user/"))
        XCTAssertTrue(isBlocked("https://www.instagram.com/reels/C1a2b3/"))
        XCTAssertTrue(isBlocked("https://www.instagram.com/natgeo/reels/"))
        XCTAssertFalse(isBlocked("https://www.instagram.com/"))
        XCTAssertFalse(isBlocked("https://www.instagram.com/api/v1/feed/timeline/"))
        XCTAssertFalse(isBlocked("https://www.instagram.com/direct/inbox/"))
        XCTAssertFalse(isBlocked("https://scontent.cdninstagram.com/v/t51.2885-15/photo.jpg"))
    }

    /// Layer 3: the script gets its lists from reels-rules.json.
    func testTheScriptIsFilledInFromTheRules() throws {
        let script = try rules().script(from: bundle)
        XCTAssertFalse(script.contains("__CMX_"))
        XCTAssertTrue(script.contains(#"["reels","reel","explore"]"#))
        XCTAssertTrue(script.contains(ReelsRules.scriptMessageName))
    }
}
