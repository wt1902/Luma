import Foundation
import Martin

/// Counts XEP-0198 stanza statistics (sent / acknowledged / received) at the
/// stream level so the server-details screen can mirror Monal's connection
/// statistics. Registered as an `XmppStanzaFilter` *before* stream management
/// so it can also observe the server's `<a h='N'>` acknowledgements.
final class LumaConnectionStatsModule: XmppModuleBase, XmppModule, XmppStanzaFilter {
    static let ID = "lumaConnectionStats"
    static let smNamespace = "urn:xmpp:sm:3"

    let criteria = Criteria.empty()
    let features: [String] = []

    private let lock = NSLock()
    private var sent: UInt32 = 0
    private var received: UInt32 = 0
    private var acknowledged: UInt32 = 0

    struct Snapshot: Equatable, Sendable {
        let sent: UInt32
        let acknowledged: UInt32
        let received: UInt32

        var unacknowledged: UInt32 {
            sent > acknowledged ? sent - acknowledged : 0
        }
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(sent: sent, acknowledged: acknowledged, received: received)
    }

    func processIncoming(stanza: Stanza) -> Bool {
        if stanza.xmlns == Self.smNamespace, stanza.name == "a" {
            if let raw = stanza.attribute("h"), let value = UInt32(raw) {
                lock.lock()
                acknowledged = value
                lock.unlock()
            }
            // Let StreamManagementModule consume the acknowledgement too.
            return false
        }
        if Self.isCountable(stanza) {
            lock.lock()
            received += 1
            lock.unlock()
        }
        return false
    }

    func processOutgoing(stanza: Stanza) {
        guard Self.isCountable(stanza) else { return }
        lock.lock()
        sent += 1
        lock.unlock()
    }

    func process(stanza: Stanza) throws {
        // Criteria is empty, so this module is never selected by the dispatcher.
    }

    private static func isCountable(_ stanza: Stanza) -> Bool {
        stanza.name == "iq" || stanza.name == "message" || stanza.name == "presence"
    }
}
