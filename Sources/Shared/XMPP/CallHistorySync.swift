import Foundation
import Martin

/// Service messages that sync call-history cards between the user's own
/// devices. After a call ends the originating device sends a message to its
/// own bare JID carrying a `<call-history xmlns='https://luma.chat/call-history'>`
/// payload; Carbons deliver it to the other devices and MAM archives it.
/// Receivers parse the payload and upsert the same card, deduplicating by
/// the origin-id that matches the local card's clientID.
enum CallHistorySync {
    static let namespace = "https://luma.chat/call-history"

    struct Envelope: Equatable, Sendable {
        let id: String
        let peerJID: String
        let direction: CallDirection
        let isVideo: Bool
        let startedAt: Date
        let duration: TimeInterval?
        let outcome: CallHistoryOutcome
    }

    static func envelope(from message: Message) -> Envelope? {
        guard let element = message.element.findChild(
            name: "call-history",
            xmlns: namespace
        ) else {
            return nil
        }
        let value = { (name: String) -> String? in
            element.findChild(name: name)?.value
        }
        guard let rawPeer = value("with"), !rawPeer.isEmpty else { return nil }
        let durationSeconds = value("duration").flatMap { TimeInterval($0) }
        return Envelope(
            id: message.originId ?? message.id ?? UUID().uuidString,
            peerJID: rawPeer.lowercased(),
            direction: value("direction") == "outgoing" ? .outgoing : .incoming,
            isVideo: value("video") == "true",
            startedAt: value("start").flatMap { startFormatter.date(from: $0) } ?? Date(),
            duration: (durationSeconds ?? 0) > 0 ? durationSeconds : nil,
            outcome: value("status").flatMap(CallHistoryOutcome.init(rawValue:)) ?? .failed
        )
    }

    static func payloadElement(entry: CallHistoryEntry) -> Element {
        let element = Element(name: "call-history", xmlns: namespace)
        element.addChild(Element(name: "direction", cdata: entry.direction.rawValue))
        element.addChild(Element(name: "status", cdata: entry.outcome.rawValue))
        element.addChild(
            Element(name: "duration", cdata: String(Int((entry.duration ?? 0).rounded())))
        )
        element.addChild(Element(name: "start", cdata: startFormatter.string(from: entry.startedAt)))
        element.addChild(Element(name: "with", cdata: entry.peerJID.lowercased()))
        element.addChild(Element(name: "video", cdata: entry.isVideo ? "true" : "false"))
        return element
    }

    private static let startFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

