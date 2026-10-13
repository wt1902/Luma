import Foundation
import WatchConnectivity

struct WatchSnapshot: Codable {
    struct Chat: Codable, Identifiable, Hashable {
        var id: String { jid }
        let jid: String
        let name: String
        let unread: Int
        let messages: [Message]
    }

    struct Message: Codable, Identifiable, Hashable {
        let id: String
        let body: String
        let timestamp: Date
        let outgoing: Bool
        let encrypted: Bool
    }

    let chats: [Chat]
}

@MainActor
final class WatchSessionModel: NSObject, ObservableObject {
    @Published private(set) var chats: [WatchSnapshot.Chat] = []
    @Published private(set) var phoneReachable = false
    @Published private(set) var voiceStatusByJID: [String: String] = [:]
    @Published var errorMessage: String?

    private let session: WCSession?
    private let cacheKey = "luma.watch.snapshot.v1"
    private let voiceTransferCacheKey = "luma.watch.voice-transfers.v1"
    private var outgoingVoiceTransfers: [String: OutgoingVoiceTransfer] = [:]

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        loadCachedSnapshot()
        loadOutgoingVoiceTransfers()
        session?.delegate = self
        session?.activate()
    }

    func send(text rawText: String, to jid: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session else { return }
        let payload: [String: Any] = [
            "action": "reply",
            "jid": jid,
            "text": text,
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    @discardableResult
    func sendVoice(fileURL: URL, duration: TimeInterval, to jid: String) -> Bool {
        guard let session else {
            errorMessage = "WatchConnectivity недоступен."
            return false
        }
        guard session.activationState == .activated else {
            errorMessage = "Соединение с iPhone ещё не готово. Повторите через несколько секунд."
            return false
        }
        #if os(watchOS)
            guard session.isCompanionAppInstalled else {
                errorMessage = "Установите Luma на связанный iPhone."
                return false
            }
        #endif
        guard duration.isFinite, duration >= 0.4,
            FileManager.default.fileExists(atPath: fileURL.path)
        else {
            errorMessage = "Запись голосового сообщения недоступна."
            return false
        }

        let transferID = UUID().uuidString
        let normalizedJID = jid.lowercased()
        let metadata: [String: Any] = [
            "action": "voice",
            "transferID": transferID,
            "jid": normalizedJID,
            "filename": fileURL.lastPathComponent,
            "duration": duration,
        ]
        outgoingVoiceTransfers[transferID] = OutgoingVoiceTransfer(
            jid: normalizedJID,
            fileURL: fileURL,
            createdAt: Date()
        )
        persistOutgoingVoiceTransfers()
        voiceStatusByJID[normalizedJID] = "Голосовое в очереди на iPhone…"
        session.transferFile(fileURL, metadata: metadata)
        return true
    }

    func voiceStatus(for jid: String) -> String? {
        voiceStatusByJID[jid.lowercased()]
    }

    private func apply(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WatchSnapshot.self, from: data) else { return }
        chats = snapshot.chats
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func loadCachedSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return }
        apply(data: data)
    }

    private func consume(_ payload: [String: Any]) {
        guard payload["action"] as? String == "voiceResult",
            let transferID = payload["transferID"] as? String,
            let success = payload["success"] as? Bool
        else { return }

        let transfer = outgoingVoiceTransfers.removeValue(forKey: transferID)
        let jid = transfer?.jid ?? (payload["jid"] as? String)?.lowercased()
        guard let jid else { return }

        if let transfer {
            try? FileManager.default.removeItem(at: transfer.fileURL)
        }
        persistOutgoingVoiceTransfers()
        if success {
            voiceStatusByJID[jid] = "Голосовое отправлено"
        } else {
            voiceStatusByJID[jid] = "Голосовое не отправлено"
            errorMessage =
                (payload["error"] as? String) ?? "iPhone не смог отправить голосовое сообщение."
        }
    }

    private func finishVoiceTransfer(
        transferID: String?,
        fallbackURL: URL,
        errorDescription: String?
    ) {
        guard let transferID,
            let transfer = outgoingVoiceTransfers[transferID]
        else {
            try? FileManager.default.removeItem(at: fallbackURL)
            return
        }

        // Once WatchConnectivity has copied the file to the iPhone the source
        // recording is no longer needed. Keep only the transfer metadata while
        // waiting for the actual XMPP upload result from the companion app.
        try? FileManager.default.removeItem(at: transfer.fileURL)
        if let errorDescription {
            outgoingVoiceTransfers.removeValue(forKey: transferID)
            persistOutgoingVoiceTransfers()
            voiceStatusByJID[transfer.jid] = "Не удалось передать запись"
            errorMessage = errorDescription
        } else {
            voiceStatusByJID[transfer.jid] = "iPhone получил запись. Отправляем…"
        }
    }

    private func loadOutgoingVoiceTransfers() {
        guard let data = UserDefaults.standard.data(forKey: voiceTransferCacheKey),
            let stored = try? JSONDecoder().decode(
                [String: OutgoingVoiceTransfer].self,
                from: data
            )
        else { return }
        let expiration = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        outgoingVoiceTransfers = stored.filter { $0.value.createdAt >= expiration }
        for transfer in outgoingVoiceTransfers.values {
            voiceStatusByJID[transfer.jid] = "Ожидает подтверждения iPhone…"
        }
        persistOutgoingVoiceTransfers()
    }

    private func persistOutgoingVoiceTransfers() {
        guard let data = try? JSONEncoder().encode(outgoingVoiceTransfers) else { return }
        UserDefaults.standard.set(data, forKey: voiceTransferCacheKey)
    }
}

private struct OutgoingVoiceTransfer: Codable {
    let jid: String
    let fileURL: URL
    let createdAt: Date
}

extension WatchSessionModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            phoneReachable = session.isReachable
            if let error { errorMessage = error.localizedDescription }
            if let data = session.receivedApplicationContext["snapshot"] as? Data {
                apply(data: data)
            }
        }
    }

    // nonisolated func sessionDidDeactivate(_ session: WCSession) {
    //     Task { @MainActor in
    //         phoneReachable = false
    //     }
    // }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in phoneReachable = session.isReachable }
    }

    nonisolated func session(
        _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in apply(data: data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in consume(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in consume(userInfo) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let transferID = fileTransfer.file.metadata?["transferID"] as? String
        let fileURL = fileTransfer.file.fileURL
        let errorDescription = error?.localizedDescription
        Task { @MainActor in
            finishVoiceTransfer(
                transferID: transferID,
                fallbackURL: fileURL,
                errorDescription: errorDescription
            )
        }
    }
}
