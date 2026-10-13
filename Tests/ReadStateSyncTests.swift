import Martin
import XCTest
@testable import Luma

final class ReadStateSyncTests: XCTestCase {
    private func makePayloadMessage(id: String = "marker-42") -> Message {
        let message = Message()
        message.id = id
        let payload = Element(name: "read-marker", xmlns: ReadStateSync.namespace)
        payload.addChild(Element(name: "conversation", cdata: "Bob@Example.org"))
        payload.addChild(Element(name: "id", cdata: "msg-uuid"))
        payload.addChild(Element(name: "stanza", cdata: "stanza-7"))
        payload.addChild(Element(name: "when", cdata: "2026-09-14T12:00:00Z"))
        message.addChild(payload)
        return message
    }

    func testEnvelopeParsesPayload() throws {
        let envelope = try XCTUnwrap(ReadStateSync.envelope(from: makePayloadMessage()))
        XCTAssertEqual(envelope.id, "marker-42")
        XCTAssertEqual(envelope.conversationJID, "bob@example.org")
        XCTAssertEqual(envelope.messageID, "msg-uuid")
        XCTAssertEqual(envelope.stanzaID, "stanza-7")
        XCTAssertEqual(
            envelope.timestamp,
            ISO8601DateFormatter().date(from: "2026-09-14T12:00:00Z")
        )
    }

    func testEnvelopePrefersOriginID() throws {
        let message = makePayloadMessage()
        let origin = Element(name: "origin-id", xmlns: "urn:xmpp:sid:0")
        origin.setAttribute("id", value: "marker-uuid")
        message.addChild(origin)
        XCTAssertEqual(ReadStateSync.envelope(from: message)?.id, "marker-uuid")
    }

    func testEnvelopeIgnoresOrdinaryMessages() {
        let message = Message()
        message.body = "hello"
        XCTAssertNil(ReadStateSync.envelope(from: message))
    }

    func testEnvelopeAllowsMissingStanzaID() throws {
        let message = Message()
        message.id = "marker-1"
        let payload = Element(name: "read-marker", xmlns: ReadStateSync.namespace)
        payload.addChild(Element(name: "conversation", cdata: "bob@example.org"))
        payload.addChild(Element(name: "id", cdata: "msg-uuid"))
        message.addChild(payload)
        let envelope = try XCTUnwrap(ReadStateSync.envelope(from: message))
        XCTAssertNil(envelope.stanzaID)
    }

    func testPayloadRoundTripPreservesReadDetails() throws {
        let marker = ReadStateSync.Envelope(
            id: "marker-1",
            conversationJID: "Room@Conference.example.org",
            messageID: "msg-uuid",
            stanzaID: "stanza-7",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let message = Message()
        message.id = marker.id
        message.addChild(ReadStateSync.payloadElement(marker: marker))

        let envelope = try XCTUnwrap(ReadStateSync.envelope(from: message))
        XCTAssertEqual(envelope.id, "marker-1")
        XCTAssertEqual(envelope.conversationJID, "room@conference.example.org")
        XCTAssertEqual(envelope.messageID, "msg-uuid")
        XCTAssertEqual(envelope.stanzaID, "stanza-7")
    }
}
