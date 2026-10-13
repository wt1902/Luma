import XCTest

@testable import Luma

final class CallSDPOrderingTests: XCTestCase {
    func testAnswerKeepsOfferMediaOrder() {
        XCTAssertEqual(
            CallSDPOrdering.answerIndices(
                localOrder: ["audio", "video"],
                remoteOrder: ["audio", "video"]
            ),
            [0, 1]
        )
    }

    func testAnswerWithReversedJingleContentsIsReordered() {
        XCTAssertEqual(
            CallSDPOrdering.answerIndices(
                localOrder: ["audio", "video"],
                remoteOrder: ["video", "audio"]
            ),
            [1, 0]
        )
    }

    func testAnswerWithMissingOrDuplicateContentIsRejected() {
        XCTAssertNil(
            CallSDPOrdering.answerIndices(
                localOrder: ["audio", "video"],
                remoteOrder: ["audio"]
            )
        )
        XCTAssertNil(
            CallSDPOrdering.answerIndices(
                localOrder: ["audio", "video"],
                remoteOrder: ["audio", "audio"]
            )
        )
    }

    func testJingleCandidateIsNormalizedForWebRTC() {
        XCTAssertEqual(
            CallSDPOrdering.webRTCCandidateLine("a=candidate:1 1 UDP 1 192.0.2.1 5000 typ host"),
            "candidate:1 1 UDP 1 192.0.2.1 5000 typ host"
        )
        XCTAssertEqual(
            CallSDPOrdering.webRTCCandidateLine("candidate:2 1 UDP 1 192.0.2.2 5002 typ host"),
            "candidate:2 1 UDP 1 192.0.2.2 5002 typ host"
        )
    }

    func testMartinParseInputPreservesFinalMSIDCharacter() {
        let raw =
            [
                "v=0",
                "m=video 9 UDP/TLS/RTP/SAVPF 96",
                "a=ssrc-group:FID 2408145738 2025569816",
                "a=ssrc:2408145738 msid:luma-stream luma-video-0435",
                "a=ssrc:2025569816 msid:luma-stream luma-video-0435",
            ].joined(separator: "\r\n") + "\n"

        let result = CallSDPNormalization.martinParseInput(raw)

        let expected =
            [
                "v=0",
                "m=video 9 UDP/TLS/RTP/SAVPF 96",
                "a=ssrc-group:FID 2408145738 2025569816",
                "a=ssrc:2408145738 msid:luma-stream luma-video-0435",
                "a=ssrc:2025569816 msid:luma-stream luma-video-0435",
            ].joined(separator: "\r\n") + "\r\n"

        XCTAssertEqual(result, expected)
    }

    func testMartinParseInputUsesExactlyOneTrailingCRLF() {
        for suffix in ["", "\n", "\r\n", "\n\n"] {
            let parseInput = CallSDPNormalization.martinParseInput(
                "v=0\nm=audio 9 UDP/TLS/RTP/SAVPF 111\na=mid:0" + suffix
            )
            XCTAssertTrue(parseInput.hasSuffix("a=mid:0\r\n"))
            XCTAssertFalse(parseInput.hasSuffix("\r\n\r\n"))
        }
    }

    func testFIDMSIDsUseTheCompleteTrackIdentifier() {
        let repaired = CallSDPCompatibility.canonicalFIDMSIDs(
            groups: [
                .init(semantics: "FID", sources: ["primary", "rtx"])
            ],
            msids: [
                "primary": "luma-stream luma-video-9FBECB58-45C5-445B-9F4E-0598594F4F2D",
                "rtx": "luma-stream luma-video-9FBECB58-45C5-445B-9F4E-0598594F4F2",
            ]
        )

        XCTAssertEqual(repaired["primary"], repaired["rtx"])
        XCTAssertTrue(repaired["rtx"]?.hasSuffix("F4F2D") == true)
    }

    func testFIDMSIDRepairAlsoHandlesMissingRTXMetadata() {
        let repaired = CallSDPCompatibility.canonicalFIDMSIDs(
            groups: [
                .init(semantics: "fid", sources: ["primary", "rtx"]),
                .init(semantics: "SIM", sources: ["sim-a", "sim-b"]),
            ],
            msids: [
                "primary": "stream video-track",
                "sim-a": "stream camera-a",
                "sim-b": "stream camera-b",
            ]
        )

        XCTAssertEqual(repaired["rtx"], "stream video-track")
        XCTAssertEqual(repaired["sim-a"], "stream camera-a")
        XCTAssertEqual(repaired["sim-b"], "stream camera-b")
    }

    func testCandidateDispatchWaitsForRemoteAnswerAndFullJID() {
        XCTAssertFalse(
            CallCandidateDispatchGate.canSend(
                initialDescriptionWasSignaled: true,
                hasLocalDescription: true,
                hasRemoteDescription: false,
                hasFullPeerJID: true
            ))
        XCTAssertFalse(
            CallCandidateDispatchGate.canSend(
                initialDescriptionWasSignaled: true,
                hasLocalDescription: true,
                hasRemoteDescription: true,
                hasFullPeerJID: false
            ))
    }

    func testCandidateDispatchOpensAfterSessionAccept() {
        XCTAssertTrue(
            CallCandidateDispatchGate.canSend(
                initialDescriptionWasSignaled: true,
                hasLocalDescription: true,
                hasRemoteDescription: true,
                hasFullPeerJID: true
            ))
    }
}
