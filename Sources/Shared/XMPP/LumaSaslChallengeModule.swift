import Foundation
import Martin

/// Observes the raw SASL `<challenge/>` stanzas before `SaslModule` consumes
/// them, so Luma can detect the XEP-0474 downgrade-protection hash (`h=`
/// attribute in the SCRAM server-first message) regardless of which SCRAM
/// mechanism implementation actually runs the exchange. Registered before
/// `SaslModule` in the module list.
final class LumaSaslChallengeModule: XmppModuleBase, XmppModule {
    static let ID = "lumaSaslChallenge"
    static let saslXMLNS = "urn:ietf:params:xml:ns:xmpp-sasl"

    let criteria = Criteria.name("challenge", xmlns: LumaSaslChallengeModule.saslXMLNS)
    let features: [String] = []

    private let onChallenge: (String) -> Void

    init(onChallenge: @escaping (String) -> Void) {
        self.onChallenge = onChallenge
        super.init()
    }

    func process(stanza: Stanza) throws {
        onChallenge(stanza.element.value ?? "")
    }
}
