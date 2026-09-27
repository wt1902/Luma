import Foundation
import Martin

/// Observes the raw SASL `<failure/>` stanza before `SaslModule` collapses
/// it into its `SaslError` enum, so the UI can show the real RFC 6120
/// condition (`account-disabled`, `credentials-expired`, …) and the
/// optional server `<text/>` instead of a catch-all "authentication
/// failure". Registered before `SaslModule` in the module list.
final class LumaSaslFailureModule: XmppModuleBase, XmppModule {
    static let ID = "lumaSaslFailure"
    static let saslXMLNS = "urn:ietf:params:xml:ns:xmpp-sasl"

    struct Failure: Equatable, Sendable {
        let condition: String?
        let text: String?
    }

    let criteria = Criteria.name("failure", xmlns: LumaSaslFailureModule.saslXMLNS)
    let features: [String] = []

    private let lock = NSLock()
    private var stored: Failure?

    var lastFailure: Failure? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func process(stanza: Stanza) throws {
        let condition = stanza.firstChild(where: { _ in true })?.name
        let text = stanza.firstChild(name: "text")?.value
        lock.lock()
        stored = Failure(condition: condition, text: text)
        lock.unlock()
    }
}
