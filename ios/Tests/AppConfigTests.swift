import ManagedSettings
import XCTest

final class AppConfigTests: XCTestCase {
    func testEmptyOrUnexpandedValueMeansDeviceOnly() {
        XCTAssertEqual(AppConfig.parseServerMode(nil), .deviceOnly)
        XCTAssertEqual(AppConfig.parseServerMode(""), .deviceOnly)
        XCTAssertEqual(AppConfig.parseServerMode("   "), .deviceOnly)
        XCTAssertEqual(AppConfig.parseServerMode("$(API_BASE_URL)"), .deviceOnly)
    }

    func testHTTPSURLIsAcceptedAndTrailingSlashesAreDropped() {
        XCTAssertEqual(AppConfig.parseServerMode("https://api.example.com"),
                       .server(URL(string: "https://api.example.com")!))
        XCTAssertEqual(AppConfig.parseServerMode("https://api.example.com/"),
                       .server(URL(string: "https://api.example.com")!))
        XCTAssertEqual(AppConfig.parseServerMode(" https://example.com/cmx// "),
                       .server(URL(string: "https://example.com/cmx")!))
    }

    func testPlainHTTPIsRejected() {
        guard case .invalid = AppConfig.parseServerMode("http://api.example.com") else {
            return XCTFail("http must be rejected")
        }
    }

    func testGarbageIsRejected() {
        guard case .invalid = AppConfig.parseServerMode("not a url") else {
            return XCTFail("garbage must be rejected")
        }
        guard case .invalid = AppConfig.parseServerMode("https://example.com/?a=b") else {
            return XCTFail("query strings must be rejected")
        }
    }

    func testInfoDictionaryKey() {
        let config = AppConfig(infoDictionary: [AppConfig.apiBaseURLKey: "https://cmx.example.org"])
        XCTAssertEqual(config.serverMode, .server(URL(string: "https://cmx.example.org")!))
        XCTAssertEqual(AppConfig(infoDictionary: nil).serverMode, .deviceOnly)
    }

    func testAppGroupIsAbsentInTheTestBundle() {
        // The test bundle has no CMXAppGroupID key, so shared storage must fall back.
        XCTAssertNil(AppGroup.identifier)
    }

    func testStoreNamesAreDistinct() {
        // Also touches ManagedSettings from the test bundle, so linking it is exercised.
        let names = ManagedSettingsStore.Name.cmxAll.map { $0.rawValue }
        XCTAssertEqual(Set(names).count, 3)
    }
}
