import Foundation

/// Snapshot of everything the "server details" screen shows, modelled after
/// Monal's `ServerDetails`: server software (XEP-0092), disco#info identities
/// and features (XEP-0030), conference (MUC) services, STUN/TURN services
/// (XEP-0215) and a few connection-level capability flags.
struct ServerInformation: Equatable, Sendable {
    enum CapabilityStatus: Equatable, Sendable {
        case success, normal, warning, error
    }

    struct Software: Equatable, Sendable {
        let name: String?
        let version: String?
        let os: String?
    }

    struct Identity: Equatable, Sendable, Identifiable {
        let category: String
        let type: String
        let name: String?

        var id: String { "\(category)/\(type)" }

        var title: String { "\(category) / \(type)" }
    }

    struct ConferenceServer: Equatable, Sendable, Identifiable {
        let jid: String
        let name: String?
        let type: String
        let category: String

        var id: String { jid }
    }

    struct ExternalService: Equatable, Sendable, Identifiable {
        let type: String
        let host: String
        let port: UInt16?
        let transport: String?

        var id: String { "\(type)|\(host)|\(port.map(String.init) ?? "")" }
    }

    struct ConnectionStats: Equatable, Sendable {
        let lastLogin: Date?
        let smacksSessionEstablished: Date?
        let sent: UInt32
        let acknowledged: UInt32
        let received: UInt32

        var unacknowledged: UInt32 {
            sent > acknowledged ? sent - acknowledged : 0
        }
    }

    struct Capability: Equatable, Sendable, Identifiable {
        let title: String
        let detail: String
        let status: CapabilityStatus

        var id: String { title }
    }

    let serverDomain: String
    let software: Software
    let identities: [Identity]
    let serverFeatures: [String]
    let accountFeatures: [String]
    let conferenceServers: [ConferenceServer]
    let externalServices: [ExternalService]
    let connectionStats: ConnectionStats
    let saslMethods: [String]
    /// SASL2 (RFC 9050) mechanisms advertised in `<authentication/>`.
    let sasl2Methods: [String]
    /// XEP-0440 channel-binding types advertised by the server, used to
    /// detect MITM attacks on the TLS layer during SCRAM-PLUS.
    let channelBindingTypes: [String]
    /// The channel-binding type actually used for this connection's SASL
    /// exchange, when a -PLUS mechanism was selected.
    let usedChannelBindingType: String?
    /// True when the server included its XEP-0474 downgrade-protection
    /// hash in the SCRAM exchange (`h` attribute of the server-first message).
    let supportsSCRAMDowngradeProtection: Bool
    /// Raw name of the SASL mechanism used for this connection's auth
    /// (without the channel-binding suffix), highlighted in the method lists.
    let usedSASLMechanism: String?
    /// TLS version negotiated with the server during this connection
    /// (probed from a parallel handshake when the library does not expose it).
    let tlsVersion: String?
    /// Cipher suite negotiated alongside the TLS version.
    let tlsCipher: String?
    /// SASL mechanism actually selected for authentication (the strongest
    /// one the server advertises).
    let saslMechanism: String?
    let supportsStreamManagement: Bool
    let supportsCarbons: Bool
    let supportsClientState: Bool
    let supportsHTTPUpload: Bool
    let supportsRosterVersioning: Bool
    let supportsRosterPreApproval: Bool

    /// The curated XEP list Monal shows, with a status derived from the server
    /// and account disco features plus the connection-level flags.
    var capabilities: [Capability] {
        let server = Set(serverFeatures)
        let account = Set(accountFeatures)
        let supportsPubSub = account.contains { $0.hasPrefix("http://jabber.org/protocol/pubsub") }
        return [
            Capability(
                title: "XEP-0163 Personal Eventing Protocol",
                detail: "Публикация событий состояния аккаунта (аватары, статусы) через publish-subscribe.",
                status: supportsPubSub ? .success : .error
            ),
            Capability(
                title: "XEP-0191 Blocking Command",
                detail: "Расширение XMPP для блокировки контактов.",
                status: server.contains("urn:xmpp:blocking") ? .success : .error
            ),
            Capability(
                title: "XEP-0198 Stream Management",
                detail: "Возобновление потока при обрыве соединения — быстрее переподключение и экономия заряда.",
                status: supportsStreamManagement ? .success : .error
            ),
            Capability(
                title: "XEP-0199 XMPP Ping",
                detail: "Пинг уровня приложения поверх XML-потока.",
                status: server.contains("urn:xmpp:ping") ? .success : .error
            ),
            Capability(
                title: "XEP-0215 External Service Discovery",
                detail: "Обнаружение внешних сервисов (STUN/TURN) для аудио- и видеозвонков.",
                status: server.contains("urn:xmpp:extdisco:2") ? .success : .error
            ),
            Capability(
                title: "XEP-0237 Roster Versioning",
                detail: "Версионирование ростера, чтобы сервер не отправлял его повторно, если он не менялся.",
                status: supportsRosterVersioning ? .success : .error
            ),
            Capability(
                title: "XEP-0280 Message Carbons",
                detail: "Синхронизация сообщений между всеми вашими устройствами.",
                status: supportsCarbons ? .success : .error
            ),
            Capability(
                title: "XEP-0313 Message Archive Management",
                detail: "Доступ к архиву сообщений на сервере.",
                status: account.contains("urn:xmpp:mam:2") ? .success : .error
            ),
            Capability(
                title: "XEP-0352 Client State Indication",
                detail: "Указывает, активно ли устройство. Экономит заряд.",
                status: supportsClientState ? .success : .error
            ),
            Capability(
                title: "XEP-0357 Push Notifications",
                detail: "Push-уведомления через Apple даже когда приложение выгружено.",
                status: account.contains("urn:xmpp:push:0") ? .success : .error
            ),
            Capability(
                title: "XEP-0363 HTTP File Upload",
                detail: "Загрузка файлов на сервер для обмена с собеседниками.",
                status: supportsHTTPUpload ? .success : .error
            ),
            Capability(
                title: "XEP-0379 Pre-Authenticated Roster Subscription",
                detail: "Ссылки для предварительно аутентифицированной подписки на присутствие.",
                status: supportsRosterPreApproval ? .success : .error
            ),
            Capability(
                title: "XEP-0474 SASL SCRAM Downgrade Protection",
                detail: supportsSCRAMDowngradeProtection
                    ? "Сервер включил downgrade-protection hash в SCRAM-обмен (атрибут h): списки SASL-механизмов и channel-binding защищены от подмены MITM."
                    : "Сервер не включил downgrade-protection hash в SCRAM-обмен (или вход выполнен через PLAIN): списки механизмов и channel-binding не защищены от подмены.",
                status: supportsSCRAMDowngradeProtection ? .success : .error
            ),
        ]
    }
}
