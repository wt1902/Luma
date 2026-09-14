import Foundation
import Martin

/// Service messages that sync read receipts between the user's own devices.
/// When a device marks an outgoing message as read (the peer's XEP-0333
/// <displayed/> marker arrived there) it sends a message to its own bare JID
/// carrying a `<read-marker xmlns='https://luma.chat/read-marker'>` payload;
/// Carbons deliver it to the other devices and MAM archives it, so a fresh
/// install and every later archive replay converge on the same read state.
/// Receivers upsert the state on the matching outgoing message, deduplicating
/// by the marker id.
///
/// MUC read state never leaks into the room archive: the marker is a plain
/// self-addressed message whose payload references the room JID and the
/// archived stanza-id of the room message. Group conversations are matched
/// through the MUC-MAM stanza-id, 1:1 chats through the origin-id.
enum ReadStateSync {
    static let namespace = "https://luma.chat/read-marker"

    struct Envelope: Equatable, Sendable {
        /// Unique marker id; matches the message origin-id so Carbons and MAM
        /// copies deduplicate into a single state application.
        let id: String
        /// Bare JID of the conversation holding the read message: a peer or
        /// a MUC room.
        let conversationJID: String
        /// Origin-id (clientID) of the read message on the sending device.
        let messageID: String
        /// Archived stanza-id of the read message (1:1 archive or MUC-MAM);
        /// group messages are matched through it on the receiving devices.
        let stanzaID: String?
        let timestamp: Date
    }

    static func envelope(from message: Message) -> Envelope? {
        guard let element = message.element.findChild(
            name: "read-marker",
            xmlns: namespace
        ) else {
            return nil
        }
        let value = { (name: String) -> String? in
            element.findChild(name: name)?.value
        }
        guard let rawConversation = value("conversation"), !rawConversation.isEmpty,
            let rawMessage = value("id"), !rawMessage.isEmpty
        else { return nil }
        let rawStanza = value("stanza")
        return Envelope(
            id: message.originId ?? message.id ?? UUID().uuidString,
            conversationJID: rawConversation.lowercased(),
            messageID: rawMessage,
            stanzaID: (rawStanza?.isEmpty == false) ? rawStanza : nil,
            timestamp: value("when").flatMap { timestampFormatter.date(from: $0) } ?? Date()
        )
    }

    static func payloadElement(marker: Envelope) -> Element {
        let element = Element(name: "read-marker", xmlns: namespace)
        element.addChild(Element(name: "conversation", cdata: marker.conversationJID.lowercased()))
        element.addChild(Element(name: "id", cdata: marker.messageID))
        if let stanzaID = marker.stanzaID, !stanzaID.isEmpty {
            element.addChild(Element(name: "stanza", cdata: stanzaID))
        }
        element.addChild(Element(name: "when", cdata: timestampFormatter.string(from: marker.timestamp)))
        return element
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
