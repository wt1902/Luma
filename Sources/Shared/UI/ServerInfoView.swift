import SwiftUI

/// "Server information" screen shown from Settings, mirroring Monal's
/// `ServerDetails`: a grouped list of headline + caption entries whose row
/// background is tinted green/orange/red according to the detected status.
struct ServerInfoView: View {
    @ObservedObject var model: AppModel
    @State private var isLoading = false

    var body: some View {
        #if os(iOS)
        Form {
            infocontent()
        }
        .navigationTitle(model.account?.domain ?? "Сервер")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .listStyle(.grouped)
        #else
        List {
            infocontent()
        }
        .navigationTitle(model.account?.domain ?? "Сервер")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .listStyle(.inset)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
    
    @ViewBuilder
    private func infocontent() -> some View {
        if let info = model.serverInformation {
            Section("Это статистика вашего соединения.") {
                statisticsEntries(info)
            }
            Section("Это программное обеспечение, работающее на вашем сервере.") {
                softwareEntry(info)
            }
            Section {
                connectionRows(info)
            } header: {
                Text("Параметры подключения к вашему серверу.")
            } footer: {
                Text(
                    "Luma автоматически выбирает самый безопасный вариант: при TLS договаривается о максимальной версии (1.3 > 1.2), а при входе — о самом стойком SASL-механизме, который поддерживает сервер."
                )
            }
            Section("Современные возможности XMPP, обнаруженные на вашем сервере после входа.") {
                ForEach(info.capabilities) { capability in
                    entry(
                        title: capability.title,
                        detail: capability.detail,
                        status: capability.status
                    )
                }
            }
            Section("MUC-серверы, обнаруженные на вашем сервере.") {
                mucEntries(info)
            }
            Section("STUN и TURN сервисы, объявленные вашим сервером.") {
                stunTurnEntries(info)
            }
            Section("Методы аутентификации SASL, которые поддерживает ваш сервер.") {
                saslEntries(info)
            }
            Section("Методы аутентификации SASL2 (RFC 9050), которые поддерживает ваш сервер.") {
                sasl2Entries(info)
            }
            Section {
                channelBindingEntries(info)
            } header: {
                Text("Привязка канала (channel binding), которую поддерживает ваш сервер.")
            } footer: {
                Text(
                    "Channel binding связывает SASL-обмен с TLS-каналом: MITM-ретрансляция не сможет подменить соединение. Зелёным отмечен тип, использованный в текущем соединении, оранжевым — типы, которые Luma не поддерживает."
                )
            }
        } else if isLoading {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Загрузка информации о сервере…")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Нет данных о сервере",
                    systemImage: "server.rack",
                    description: Text(
                        model.connectionStatus == .connected
                            ? "Сервер не ответил на запрос. Попробуйте обновить."
                            : "Подключитесь к серверу, чтобы увидеть его возможности."
                    )
                )
            }
        }
    }

    // MARK: - Sections

    private func softwareEntry(_ info: ServerInformation) -> some View {
        let name = info.software.name ?? "Неизвестный сервер"
        let version = info.software.version ?? "неизвестная версия"
        let platform = info.software.os.map { ", работает на \($0)" } ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text("версия \(version)\(platform)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(
                "Рекомендации для администраторов серверов",
                destination: URL(
                    string: "https://github.com/monal-im/Monal/wiki/Considerations-for-XMPP-server-admins"
                )!
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.gray.opacity(0.16))
    }

    private func connectionRows(_ info: ServerInformation) -> some View {
        Group {
            if let account = model.account {
                if let host = account.manualHost {
                    let port = account.manualPort ?? (account.usesDirectTLS ? 5223 : 5222)
                    LabeledContent("Хост", value: "\(host):\(port)")
                    LabeledContent(
                        "Шифрование",
                        value: account.usesDirectTLS ? "Direct TLS" : "STARTTLS"
                    )
                } else {
                    LabeledContent("Хост", value: "DNS SRV")
                }
                LabeledContent("Ресурс", value: account.effectiveResource)
            }
            if let tlsVersion = info.tlsVersion {
                LabeledContent(
                    "Версия TLS",
                    value: info.tlsCipher.map { "\(tlsVersion) · \($0)" } ?? tlsVersion
                )
            } else {
                LabeledContent("Версия TLS", value: "Неизвестно")
            }
            if let saslMechanism = info.saslMechanism {
                LabeledContent("SASL-механизм", value: saslMechanism)
            } else {
                LabeledContent("SASL-механизм", value: "Неизвестно")
            }
        }
    }

    @ViewBuilder
    private func mucEntries(_ info: ServerInformation) -> some View {
        if info.conferenceServers.isEmpty {
            entry(
                title: "Нет",
                detail: "Этот сервер не предоставляет MUC-серверы.",
                status: .error
            )
        } else {
            ForEach(info.conferenceServers) { server in
                entry(
                    title: "Сервер: \(server.jid)",
                    detail: "\(server.name ?? "<неизвестное имя>") (тип «\(server.type)», категория «\(server.category)»)",
                    status: server.type == "text" ? .success : .normal
                )
            }
        }
    }

    @ViewBuilder
    private func stunTurnEntries(_ info: ServerInformation) -> some View {
        if info.externalServices.isEmpty {
            entry(
                title: "Нет",
                detail: "Этот сервер не предоставляет STUN / TURN сервисы.",
                status: .error
            )
        } else {
            ForEach(info.externalServices) { service in
                let endpoint = "\(service.host):\(service.port.map(String.init) ?? "-")"
                entry(
                    title: service.type.uppercased(),
                    detail: endpoint,
                    status: ["stun", "turn", "stuns", "turns"].contains(service.type.lowercased())
                        ? .success
                        : .error
                )
            }
        }
    }

    @ViewBuilder
    private func statisticsEntries(_ info: ServerInformation) -> some View {
        let stats = info.connectionStats
        entry(
            title: "Последний вход",
            detail: formatDate(stats.lastLogin),
            status: .normal
        )
        entry(
            title: "Сессия Stream Management установлена",
            detail: formatDate(stats.smacksSessionEstablished),
            status: .normal
        )
        entry(
            title: "Станз отправлено / не подтверждено / получено в этой сессии",
            detail: "\(stats.sent) / \(stats.unacknowledged) / \(stats.received)",
            status: .normal
        )
    }

    @ViewBuilder
    private func saslEntries(_ info: ServerInformation) -> some View {
        if info.saslMethods.isEmpty {
            entry(
                title: "Нет",
                detail: "Сервер не объявил методы SASL-аутентификации.",
                status: .error
            )
        } else {
            ForEach(info.saslMethods, id: \.self) { method in
                entry(
                    title: "Метод: \(method)",
                    detail: method == info.usedSASLMechanism
                        ? "Используется в текущем соединении. " + saslDescription(method)
                        : saslDescription(method),
                    status: method == info.usedSASLMechanism
                        ? .success
                        : (SASLMechanismPreference.weakMechanisms.contains(method)
                            ? .warning
                            : .normal)
                )
            }
        }
    }

    @ViewBuilder
    private func sasl2Entries(_ info: ServerInformation) -> some View {
        if info.sasl2Methods.isEmpty {
            entry(
                title: "Нет",
                detail: "Сервер не объявил методы аутентификации SASL2 (RFC 9050).",
                status: .normal
            )
        } else {
            ForEach(info.sasl2Methods, id: \.self) { method in
                entry(
                    title: "Метод: \(method)",
                    detail: method == info.usedSASLMechanism
                        ? "Используется в текущем соединении. " + sasl2Description(method)
                        : sasl2Description(method),
                    status: method == info.usedSASLMechanism
                        ? .success
                        : (SASLMechanismPreference.weakMechanisms.contains(method)
                            ? .warning
                            : .normal)
                )
            }
        }
    }

    private func sasl2Description(_ method: String) -> String {
        switch method {
        case "PLAIN":
            return "Отправляет пароль открытым текстом (шифруется только TLS), не очень безопасно."
        case "OAUTHBEARER":
            return "OAuth 2.0 bearer-токен: пароль не передаётся, но сам токен — bearer-секрет, не очень безопасно."
        case "EXTERNAL":
            return "Использует TLS-клиентские сертификаты для аутентификации."
        case let method where method.hasPrefix("SCRAM-") && method.hasSuffix("-PLUS"):
            return "Salted Challenge Response Authentication Mechanism с channel-binding."
        case let method where method.hasPrefix("SCRAM-"):
            return "Salted Challenge Response Authentication Mechanism на указанном хэше."
        default:
            return "Неизвестный метод аутентификации."
        }
    }

    /// Channel-binding types Luma can actually produce binding data for.
    private static let supportedChannelBindingTypes: Set<String> = [
        "tls-exporter", "tls-server-end-point",
    ]

    @ViewBuilder
    private func channelBindingEntries(_ info: ServerInformation) -> some View {
        if info.channelBindingTypes.isEmpty {
            entry(
                title: "Нет",
                detail: "Сервер не рекламирует channel-binding типы (XEP-0440): SASL-обмен не детектирует MITM-атаку на TLS-слой.",
                status: .warning
            )
        } else {
            ForEach(info.channelBindingTypes, id: \.self) { type in
                let used = info.usedChannelBindingType == type
                let supported = Self.supportedChannelBindingTypes.contains(type)
                entry(
                    title: "Тип: \(type)",
                    detail: channelBindingDescription(type, used: used, supported: supported),
                    status: used ? .success : (supported ? .normal : .warning)
                )
            }
        }
    }

    private func channelBindingDescription(
        _ type: String,
        used: Bool,
        supported: Bool
    ) -> String {
        if used {
            return "Используется в текущем соединении."
        }
        if supported {
            return "Luma поддерживает этот тип привязки."
        }
        return "Luma не поддерживает этот тип привязки."
    }

    private func saslDescription(_ method: String) -> String {
        switch method {
        case "PLAIN":
            return "Отправляет пароль открытым текстом (шифруется только TLS), не очень безопасно."
        case "EXTERNAL":
            return "Использует TLS-клиентские сертификаты для аутентификации."
        case let method where method.hasPrefix("SCRAM-") && method.hasSuffix("-PLUS"):
            return "Salted Challenge Response Authentication Mechanism с channel-binding."
        case let method where method.hasPrefix("SCRAM-"):
            return "Salted Challenge Response Authentication Mechanism на указанном хэше."
        default:
            return "Неизвестный метод аутентификации."
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "<неизвестно>" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    // MARK: - Entry

    private func entry(
        title: String,
        detail: String,
        status: ServerInformation.CapabilityStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
//        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(status.color)
    }

    private func load() async {
        guard model.connectionStatus == .connected else { return }
        isLoading = true
        await model.refreshServerInformation()
        isLoading = false
    }
}

private extension ServerInformation.CapabilityStatus {
    var color: Color {
        switch self {
        case .success: return Color.green.opacity(0.16)
        case .normal: return Color.gray.opacity(0.16)
        case .warning: return Color.orange.opacity(0.16)
        case .error: return Color.red.opacity(0.16)
        }
    }
}

#Preview {
    NavigationStack {
        ServerInfoView(model: PreviewSupport.model)
    }
}
