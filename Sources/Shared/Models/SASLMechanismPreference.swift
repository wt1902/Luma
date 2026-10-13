import Foundation

/// Order in which Luma prefers SASL mechanisms during authentication.
/// Channel-binding SCRAM first (tls-exporter / tls-server-end-point prove
/// the exchange runs over the client's own TLS channel, defeating MITM
/// relays), then the strongest plain SCRAM variant, and PLAIN as the
/// last-resort fallback. The server must advertise a mechanism for it to be
/// eligible — Martin's `SaslModule.guessSaslMechanism` walks exactly this
/// order, and the PLUS mechanisms additionally gate on available binding
/// data in `isAllowedToUse`.
enum SASLMechanismPreference {
    static let order: [String] = [
        "SCRAM-SHA-512-PLUS",
        "SCRAM-SHA-256-PLUS",
        "SCRAM-SHA-1-PLUS",
        "SCRAM-SHA-512",
        "SCRAM-SHA-256",
        "SCRAM-SHA-1",
        "PLAIN",
    ]

    /// The most secure mechanism from `order` that the server advertises,
    /// or nil when no password-based mechanism is offered. When
    /// `allowsChannelBinding` is false the -PLUS variants are skipped, since
    /// without binding data the exchange would fail.
    static func selected(
        among offered: [String],
        allowsChannelBinding: Bool = true
    ) -> String? {
        order.first { candidate in
            guard offered.contains(candidate) else { return false }
            return allowsChannelBinding || !candidate.hasSuffix("-PLUS")
        }
    }

    /// Mechanisms that send credentials in a way a TLS MITM can replay or
    /// read directly; shown with a warning on the server-information screen.
    static let weakMechanisms: Set<String> = ["PLAIN", "OAUTHBEARER"]

    /// True when `mechanism` is the strongest one available among
    /// `offered`: the server offers nothing better than the chosen one.
    static func isStrongestAvailable(_ mechanism: String, among offered: [String]) -> Bool {
        guard let chosenRank = order.firstIndex(of: mechanism) else { return false }
        for stronger in order[..<chosenRank] where offered.contains(stronger) {
            return false
        }
        return offered.contains(mechanism)
    }
}
