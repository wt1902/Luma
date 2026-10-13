import XCTest
@testable import Luma

final class SASLMechanismPreferenceTests: XCTestCase {
    func testPrefersScramSha512WhenAdvertised() {
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: [
                "PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-512", "SCRAM-SHA-256",
            ]),
            "SCRAM-SHA-512"
        )
    }

    func testFallsBackToSha256WithoutSha512() {
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: ["SCRAM-SHA-256", "PLAIN"]),
            "SCRAM-SHA-256"
        )
    }

    func testFallsBackToSha1AndPlain() {
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: ["PLAIN", "SCRAM-SHA-1"]),
            "SCRAM-SHA-1"
        )
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: ["PLAIN"]),
            "PLAIN"
        )
    }

    func testReturnsNilWhenNothingKnownIsOffered() {
        XCTAssertNil(
            SASLMechanismPreference.selected(among: ["X-OAUTH2", "ANONYMOUS"])
        )
        XCTAssertNil(SASLMechanismPreference.selected(among: []))
    }

    func testStrongestAvailableRanking() {
        XCTAssertTrue(
            SASLMechanismPreference.isStrongestAvailable(
                "SCRAM-SHA-512",
                among: ["SCRAM-SHA-512", "SCRAM-SHA-256", "PLAIN"]
            )
        )
        XCTAssertFalse(
            SASLMechanismPreference.isStrongestAvailable(
                "SCRAM-SHA-1",
                among: ["SCRAM-SHA-512", "SCRAM-SHA-1"]
            )
        )
        XCTAssertFalse(
            SASLMechanismPreference.isStrongestAvailable(
                "X-OAUTH2",
                among: ["X-OAUTH2"]
            )
        )
    }

    func testPLAINIsNeverChosenWhileSCRAMIsOffered() {
        let offered = ["SCRAM-SHA-1", "PLAIN", "SCRAM-SHA-512"]
        XCTAssertEqual(SASLMechanismPreference.selected(among: offered), "SCRAM-SHA-512")
        XCTAssertNotEqual(SASLMechanismPreference.selected(among: offered), "PLAIN")
    }

    func testPlusVariantsArePreferredOverPlainSCRAM() {
        let offered = ["PLAIN", "SCRAM-SHA-1", "SCRAM-SHA-256-PLUS", "SCRAM-SHA-512"]
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: offered),
            "SCRAM-SHA-256-PLUS"
        )
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: [
                "SCRAM-SHA-512", "SCRAM-SHA-1-PLUS", "SCRAM-SHA-256-PLUS",
            ]),
            "SCRAM-SHA-256-PLUS"
        )
        XCTAssertEqual(
            SASLMechanismPreference.selected(among: [
                "SCRAM-SHA-512-PLUS", "SCRAM-SHA-256-PLUS", "SCRAM-SHA-512",
            ]),
            "SCRAM-SHA-512-PLUS"
        )
    }

    func testWeakMechanismsAreFlagged() {
        XCTAssertTrue(SASLMechanismPreference.weakMechanisms.contains("PLAIN"))
        XCTAssertTrue(SASLMechanismPreference.weakMechanisms.contains("OAUTHBEARER"))
        XCTAssertFalse(SASLMechanismPreference.weakMechanisms.contains("SCRAM-SHA-1"))
        XCTAssertFalse(SASLMechanismPreference.weakMechanisms.contains("SCRAM-SHA-512-PLUS"))
        XCTAssertFalse(SASLMechanismPreference.weakMechanisms.contains("EXTERNAL"))
    }

    func testPlusVariantsSkippedWithoutChannelBinding() {
        let offered = ["SCRAM-SHA-512-PLUS", "SCRAM-SHA-512", "PLAIN"]
        XCTAssertEqual(
            SASLMechanismPreference.selected(
                among: offered,
                allowsChannelBinding: false
            ),
            "SCRAM-SHA-512"
        )
        // Without any plain SCRAM alternative, PLAIN is the only choice.
        XCTAssertEqual(
            SASLMechanismPreference.selected(
                among: ["SCRAM-SHA-1-PLUS", "PLAIN"],
                allowsChannelBinding: false
            ),
            "PLAIN"
        )
    }
}
