import Martin
import XCTest
@testable import Luma

final class CallHistorySyncTests: XCTestCase {
    private func makePayloadMessage(id: String = "call-42") -> Message {
        let message = Message()
        message.id = id
        let payload = Element(name: "call-history", xmlns: CallHistorySync.namespace)
        payload.addChild(Element(name: "direction", cdata: "incoming"))
        payload.addChild(Element(name: "status", cdata: "missed"))
        payload.addChild(Element(name: "duration", cdata: "0"))
        payload.addChild(Element(name: "start", cdata: "2026-08-27T10:00:00Z"))
        payload.addChild(Element(name: "with", cdata: "Bob@Example.org"))
        payload.addChild(Element(name: "video", cdata: "false"))
        message.addChild(payload)
        return message
    }

    func testEnvelopeParsesPayload() throws {
        let envelope = try XCTUnwrap(CallHistorySync.envelope(from: makePayloadMessage()))
        XCTAssertEqual(envelope.id, "call-42")
        XCTAssertEqual(envelope.peerJID, "bob@example.org")
        XCTAssertEqual(envelope.direction, .incoming)
        XCTAssertEqual(envelope.outcome, .missed)
        XCTAssertFalse(envelope.isVideo)
        XCTAssertNil(envelope.duration)
        XCTAssertEqual(
            envelope.startedAt,
            ISO8601DateFormatter().date(from: "2026-08-27T10:00:00Z")
        )
    }

    func testEnvelopePrefersOriginID() throws {
        let message = makePayloadMessage()
        let origin = Element(name: "origin-id", xmlns: "urn:xmpp:sid:0")
        origin.setAttribute("id", value: "call-uuid")
        message.addChild(origin)
        XCTAssertEqual(CallHistorySync.envelope(from: message)?.id, "call-uuid")
    }

    func testEnvelopeIgnoresOrdinaryMessages() {
        let message = Message()
        message.body = "hello"
        XCTAssertNil(CallHistorySync.envelope(from: message))
    }

    func testPayloadRoundTripPreservesCallDetails() throws {
        let entry = CallHistoryEntry(
            id: "call-1",
            peerJID: "bob@example.org",
            direction: .outgoing,
            isVideo: true,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_042),
            duration: 42,
            outcome: .completed
        )
        let message = Message()
        message.id = entry.id
        message.addChild(CallHistorySync.payloadElement(entry: entry))

        let envelope = try XCTUnwrap(CallHistorySync.envelope(from: message))
        XCTAssertEqual(envelope.id, "call-1")
        XCTAssertEqual(envelope.peerJID, "bob@example.org")
        XCTAssertEqual(envelope.direction, .outgoing)
        XCTAssertTrue(envelope.isVideo)
        XCTAssertEqual(envelope.duration, 42)
        XCTAssertEqual(envelope.outcome, .completed)
    }
}

