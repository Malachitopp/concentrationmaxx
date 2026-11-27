import FamilyControls
import XCTest

final class StorageAndSettingsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("cmx-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Session record

    func testSessionRecordRoundTrip() throws {
        let store = FileSessionStore(directory: directory)
        XCTAssertNil(try store.load())
        let session = try BlockSession.make(now: referenceNow, duration: 1800, messagingBlocked: true, strictMode: true, unlockEntries: 3)
        try store.save(session)
        XCTAssertEqual(try FileSessionStore(directory: directory).load(), session)
        try store.clear()
        XCTAssertNil(try store.load())
        XCTAssertNoThrow(try store.clear())
    }

    func testCorruptSessionRecordThrowsInsteadOfLookingEmpty() throws {
        let store = FileSessionStore(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    func testStorageUnavailableWithoutAppGroup() {
        // The unit test bundle has no App Group, which must surface as an error.
        XCTAssertThrowsError(try SharedStorage.directory())
    }

    // MARK: Selections

    func testEmptySelectionRoundTripAndMissingFile() throws {
        let store = FileSelectionStore(directory: directory)
        XCTAssertTrue(store.load(.social).isEmptySelection)
        try store.save(FamilyActivitySelection(), as: .messaging)
        XCTAssertTrue(store.load(.messaging).isEmptySelection)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .messaging).path))
    }

    func testSelectionSummary() {
        XCTAssertEqual(SelectionSummary.text(apps: 0, categories: 0, websites: 0), "Nothing selected")
        XCTAssertEqual(SelectionSummary.text(apps: 1, categories: 0, websites: 0), "1 app")
        XCTAssertEqual(SelectionSummary.text(apps: 3, categories: 1, websites: 2), "3 apps, 1 category, 2 websites")
        XCTAssertEqual(SelectionSummary.text(apps: 0, categories: 2, websites: 1), "2 categories, 1 website")
    }

    // MARK: Diagnostics

    func testDiagnosticsLogIsCappedAndKeepsTheNewest() {
        var clock = referenceNow
        let log = DiagnosticsLog(directory: directory, limit: 3, now: { clock })
        for index in 1...5 {
            clock = clock.addingTimeInterval(1)
            log.record(.monitor, "event \(index)")
        }
        XCTAssertEqual(log.events().map(\.message), ["event 3", "event 4", "event 5"])
        XCTAssertEqual(log.events().last?.source, .monitor)
        log.clear()
        XCTAssertTrue(log.events().isEmpty)
    }

    // MARK: Settings

    func testSettingsDefaultsAndClamping() {
        let suite = "cmx.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.unlockEntries, 3)
        XCTAssertTrue(settings.strictMode)
        XCTAssertFalse(settings.reelsFreeEnabled)
        XCTAssertEqual(settings.instagramStrategy, .shield)
        XCTAssertFalse(settings.onboardingCompleted)
        XCTAssertEqual(settings.lastDurationMinutes, 60)

        settings.unlockEntries = 1
        XCTAssertEqual(settings.unlockEntries, 3)
        settings.unlockEntries = 9
        XCTAssertEqual(settings.unlockEntries, 5)
        settings.unlockEntries = 4
        XCTAssertEqual(settings.unlockEntries, 4)

        settings.strictMode = false
        XCTAssertFalse(AppSettings(defaults: defaults).strictMode)

        // Serious mode is never on unless the person turned it on, and a reset clears it.
        XCTAssertFalse(settings.seriousMode)
        settings.seriousMode = true
        XCTAssertTrue(AppSettings(defaults: defaults).seriousMode)
        settings.reset()
        XCTAssertFalse(settings.seriousMode)

        settings.lastDurationMinutes = 5
        XCTAssertEqual(settings.lastDurationMinutes, 15)
        settings.lastDurationMinutes = 5000
        XCTAssertEqual(settings.lastDurationMinutes, 1440)

        settings.instagramStrategy = .hide
        XCTAssertEqual(AppSettings(defaults: defaults).instagramStrategy, .hide)
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.minutes(15), "15 min")
        XCTAssertEqual(DurationText.minutes(60), "1 h")
        XCTAssertEqual(DurationText.minutes(90), "1 h 30 min")
        XCTAssertEqual(DurationText.minutes(1440), "24 h")
        XCTAssertEqual(DurationText.countdown(3849), "1:04:09")
        XCTAssertEqual(DurationText.countdown(249), "4:09")
        XCTAssertEqual(DurationText.countdown(0), "0:00")
        XCTAssertEqual(DurationText.countdown(0.2), "0:01")
        XCTAssertEqual(DurationText.countdown(-5), "0:00")
    }
}
