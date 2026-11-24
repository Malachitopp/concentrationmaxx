import FamilyControls
import XCTest

final class BlockSetupTests: XCTestCase {
    func testInstagramIsHiddenOnlyUnderTheHideStrategyWithAPick() {
        XCTAssertTrue(BlockSetup.hidesInstagram(reelsFreeEnabled: true, strategy: .hide, instagramPicked: true, reelsFreeAvailable: true))
        // Any missing condition keeps the normal shield.
        XCTAssertFalse(BlockSetup.hidesInstagram(reelsFreeEnabled: true, strategy: .shield, instagramPicked: true, reelsFreeAvailable: true))
        XCTAssertFalse(BlockSetup.hidesInstagram(reelsFreeEnabled: false, strategy: .hide, instagramPicked: true, reelsFreeAvailable: true))
        XCTAssertFalse(BlockSetup.hidesInstagram(reelsFreeEnabled: true, strategy: .hide, instagramPicked: false, reelsFreeAvailable: true))
        XCTAssertFalse(BlockSetup.hidesInstagram(reelsFreeEnabled: true, strategy: .hide, instagramPicked: true, reelsFreeAvailable: false))
    }

    func testPlanWithoutAnInstagramPickShieldsInstagramNormally() {
        let plan = BlockSetup.plan(social: FamilyActivitySelection(), messaging: FamilyActivitySelection(),
                                   instagram: FamilyActivitySelection(), reelsFreeEnabled: true,
                                   strategy: .hide, reelsFreeAvailable: true)
        XCTAssertNil(plan.instagramHide)
        XCTAssertTrue(plan.socialCount.isEmpty)
    }
}
