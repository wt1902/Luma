import Combine
import Foundation
@preconcurrency import Martin
@preconcurrency import MartinOMEMO
import os
import WebRTC

private struct BufferedArchiveStanza {
    let queryID: String
    let message: Message
    let timestamp: Date
    let archiveID: String
}

private struct BufferedArchivePage {
    let stanzas: [BufferedArchiveStanza]
    let overflowed: Bool
    let rejectedSource: Bool
}

private enum BufferedLiveDelivery {
    case direct(message: Message, timestamp: Date)
    case group(message: Message, room: RoomProtocol)
}

/// Martin publishes every MAM result synchronously on its parser queue. Keep
/// that burst off the main queue and hand the completed page to XMPPService
/// only after the final IQ callback. Message instances are immutable after the
/// publisher returns; the lock provides the ownership hand-off.
private final class ArchiveStanzaInbox: @unchecked Sendable {
    private struct State {
        let allowedSources: Set<String>
        var stanzas: [BufferedArchiveStanza] = []
        var overflowed = false
        var rejectedSource = false
    }
    
    private let lock = NSLock()
    private let maximumCount: Int
//    private var activeQueryID: String?
//    private var allowedSources: Set<String> = []
//    private var stanzas: [BufferedArchiveStanza] = []
//    private var overflowed = false
//    private var rejectedSource = false
    private var states: [String: State] = [:]
    
    init(maximumCount: Int) {
        self.maximumCount = maximumCount
    }

    func begin(queryID: String, allowedSources: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
//        activeQueryID = queryID
//        self.allowedSources = Set(allowedSources.map { $0.lowercased() })
//        stanzas.removeAll(keepingCapacity: true)
//        overflowed = false
//        rejectedSource = false
        states[queryID] = State(
            allowedSources: Set(allowedSources.map { $0.lowercased() })
        )
    }

    func append(
        queryID: String,
        source: BareJID,
        message: Message,
        timestamp: Date,
        archiveID: String
    ) {
        lock.lock()
        defer { lock.unlock() }
//        guard activeQueryID == queryID else { return }
//        guard allowedSources.contains(source.stringValue.lowercased()) else {
//            rejectedSource = true
        guard var state = states[queryID] else { return }
        guard state.allowedSources.contains(source.stringValue.lowercased()) else {
            state.rejectedSource = true
            states[queryID] = state
            return
        }
//        guard stanzas.count < maximumCount else {
//            overflowed = true
        guard state.stanzas.count < maximumCount else {
            state.overflowed = true
            states[queryID] = state
            return
        }
//        stanzas.append(
        state.stanzas.append(
            BufferedArchiveStanza(
                queryID: queryID,
                message: message,
                timestamp: timestamp,
                archiveID: archiveID
            ))
//        print("MAM source: \(source), allowed: \(allowedSources)")
        states[queryID] = state
    }

    func take(queryID: String) -> BufferedArchivePage {
        lock.lock()
        defer { lock.unlock() }
//        guard activeQueryID == queryID else {
        guard let state = states.removeValue(forKey: queryID) else {
            return BufferedArchivePage(stanzas: [], overflowed: false, rejectedSource: false)
        }
//        let page = BufferedArchivePage(
//            stanzas: stanzas,
//            overflowed: overflowed,
//            rejectedSource: rejectedSource
//        )
//        activeQueryID = nil
//        allowedSources.removeAll(keepingCapacity: true)
//        stanzas.removeAll(keepingCapacity: true)
//        overflowed = false
//        rejectedSource = false
//        return page
        return BufferedArchivePage(
            stanzas: state.stanzas,
            overflowed: state.overflowed,
            rejectedSource: state.rejectedSource
        )
    }

    func cancel(queryID: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
//        if let queryID, activeQueryID != queryID { return }
//        activeQueryID = nil
//        allowedSources.removeAll(keepingCapacity: true)
//        stanzas.removeAll(keepingCapacity: true)
//        overflowed = false
//        rejectedSource = false
        if let queryID {
            states.removeValue(forKey: queryID)
        } else {
            states.removeAll(keepingCapacity: true)
        }
    }
}

@MainActor
final class XMPPService {
    enum ConnectionStatus: Equatable, Sendable {
        case disconnected(reason: String?)
        case connecting
        case connected
    }

    struct MessageEnvelope: Sendable {
        let id: String
        let peerJID: String
        let senderJID: String
        let body: String
        let timestamp: Date
        let isOutgoing: Bool
        let security: ChatMessage.Security
        let kind: ChatMessage.Kind
        let remoteAttachmentURL: String?
        let localFilename: String?
        let mimeType: String?
        let duration: TimeInterval?
        let byteCount: Int?
        let fingerprint: String?
        let correctionTargetID: String?
        let replyToID: String?
        let replyToJID: String?
        let replyPreview: String?
        let originID: String?
        let stanzaID: String?
        let senderDisplayName: String?
        let isGroupMessage: Bool
        let isArchived: Bool
    }

    struct ReplyReference: Sendable {
        let id: String
        let authorJID: String?
        let fallbackAuthor: String
        let preview: String
    }

    struct RoomStateEnvelope: Sendable {
        let roomJID: String
        let nickname: String
        let joined: Bool
        let occupantCount: Int
    }

    struct RoomInvitationEnvelope: Sendable {
        let roomJID: String
        let inviterJID: String?
        let reason: String?
        let password: String?
    }

    struct RetractionEnvelope: Sendable {
        let peerJID: String
        let senderJID: String
        let targetID: String
        let retractionID: String
        let timestamp: Date
        let isOutgoing: Bool
    }

    struct ReactionEnvelope: Sendable {
        let peerJID: String
        let senderJID: String
        let targetID: String
        let emojis: [String]
        let timestamp: Date
        let isOutgoing: Bool
        let isGroupMessage: Bool
    }

    struct ChatStateEnvelope: Sendable {
        let peerJID: String
        let senderJID: String
        let senderDisplayName: String?
        let state: ChatTypingState
        let isGroupMessage: Bool
    }

    struct MediaSendResult: Sendable {
        let remoteURL: String
        let fingerprint: String?
    }

    enum ArchiveMutation: Sendable {
        case message(MessageEnvelope)
        case retraction(RetractionEnvelope)
        case reaction(ReactionEnvelope)
    }

    enum Event: Sendable {
        case connection(ConnectionStatus)
        case rosterItem(jid: String, name: String?)
        case rosterRemoved(jid: String)
        case presence(jid: String, online: Bool)
        case message(MessageEnvelope)
        case retraction(RetractionEnvelope)
        case reaction(ReactionEnvelope)
        case chatState(ChatStateEnvelope)
        case groupMessageEcho(
            roomJID: String, messageID: String, stanzaID: String, senderJID: String)
        case roomState(RoomStateEnvelope)
        case roomInvitation(RoomInvitationEnvelope)
        case avatar(jid: String, data: Data)
        case delivered(messageID: String)
        case read(conversationJID: String, messageID: String)
        case omemo(ready: Bool, ownFingerprint: String?)
        case archiveBatch([ArchiveMutation])
        case archiveSyncing(Bool)
        case archiveSyncCompleted(ArchiveSyncCheckpoint)
        case mucArchiveSyncCompleted(archive: MAMArchiveKey, checkpoint: MAMArchiveCheckpoint)
        case call(CallSnapshot?)
        case callHistory(CallHistoryEntry)
        case callHistorySync(CallHistorySync.Envelope)
        case readState(ReadStateSync.Envelope)
        case callError(String)
        case recoverableError(String)
    }

    var eventHandler: ((Event) -> Void)?

    private let callEngine: LumaCallEngine
    private var client: XMPPClient?
    private var omemoStorage: LumaOMEMOStore?
    private var connectionStatsModule: LumaConnectionStatsModule?
    private var saslFailureModule: LumaSaslFailureModule?
    private var activePassword: String?
    private var lastLoginDate: Date?
    private var smacksSessionEstablishedDate: Date?
    private(set) var negotiatedSASLMechanism: String?
    private(set) var negotiatedTLSVersion: String?
    private(set) var negotiatedTLSCipher: String?
    private var tlsProbeTask: Task<TLSProbeResult?, Never>?
    /// TLS parameters and channel-binding data of the live connection,
    /// captured by Luma's OpenSSL TLS processor and shared with SCRAM-PLUS.
    private let channelBindingStore = LumaChannelBindingStore()
    /// Mechanisms advertised in the stream features (classic SASL + SASL2),
    /// shown on the server-information screen.
    private var advertisedSASLMechanisms: [String] = []
    /// SASL2 (RFC 9050) mechanisms from the `<authentication/>` stream
    /// feature, shown as a dedicated list on the server-information screen.
    private var advertisedSASL2Mechanisms: [String] = []
    private var cancellables: Set<AnyCancellable> = []
    private var account: AccountConfiguration?
    private var archiveSyncStarted = false
    private var archiveSyncCompletedForConnection = false
    private var archiveSyncCheckpoint: ArchiveSyncCheckpoint?
    private var archiveSyncQueryStartedAt: Date?
    private var archiveSyncIndicatorVisible = false
    private var archivePagination = ArchiveSyncPagination()
    private var archiveRetryTask: Task<Void, Never>?
    private var archiveQueryTimeoutTask: Task<Void, Never>?
    private var archiveQueryCompletionTask: Task<Void, Never>?
    private var archiveSyncRetryTask: Task<Void, Never>?
    private var archiveAutoRetryCount = 0
    private var archiveActiveQueryID: String?
    private var archiveResumeAfter: String?
    private var archiveWorkBudget = ArchiveSyncWorkBudget()
    private var archiveHighWatermark: Date?
    private var archiveLastCompletedCursor: String?
    private var archiveHasCompletedPage = false
    private var archiveCursorFallbackUsed = false
    private var archivePassMutations: [ArchiveMutation] = []
    private var archiveIsBootstrapQuery = false
    private var archiveRetrySuppressedUntilActivation = false
    private var archiveSyncSuspended = false
    private var archiveResumeAfterMediaWorkTask: Task<Void, Never>?
    private var archiveStanzaBuffer: [BufferedArchiveStanza] = []
    private var archiveBufferOverflowed = false
    private var archiveRejectedSource = false
    private var mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint] = [:]
    private var pendingMUCCatchups: [MAMArchiveKey] = []
    private var activeMUCCatchup: MAMArchiveKey?
    private var mucCatchupHighWatermark: Date?
    private var mucCatchupLastCursor: String?
    private var mucCursorFallbackArchives: Set<MAMArchiveKey> = []
    private var delayedLiveByArchive: [MAMArchiveKey: [BufferedLiveDelivery]] = [:]
    private var olderHistoryQueryID: String?
    private var olderHistoryCompletion: ((Result<OlderHistoryScrollPage, Error>) -> Void)?
    private var olderHistoryTimeoutTask: Task<Void, Never>?
    /// When non-nil, archived mutations produced while applying an interactive
    /// backward-history page are collected here instead of the catch-up
    /// accumulator, so the two never interleave their mutations.
    private var interactiveHistoryMutations: [ArchiveMutation]?
    private let olderHistoryQueryTimeoutNanoseconds: UInt64 = 15_000_000_000
    /// Serial background queue for OMEMO decryption. `decode` performs the
    /// expensive Signal work (session decrypt + AES-GCM) and previously ran on
    /// the main actor for every MAM stanza, stalling the UI during large
    /// archive catch-ups. All decodes stay serialized on this single queue so
    /// Signal's per-session state is never mutated concurrently.
    private let omemoDecodeQueue = DispatchQueue(
        label: "app.luma.omemo.decode",
        qos: .userInitiated
    )
    private let archiveStanzaInbox = ArchiveStanzaInbox(
        maximumCount: ArchiveMessageBatchPolicy.maximumBufferedStanzas
    )
    private var avatarRequests: Set<String> = []
    private var observedRoomJIDs: Set<String> = []
    private var roomOccupantsByJID: [String: [MucOccupant]] = [:]
    private var roomRealJIDByNickname: [String: [String: BareJID]] = [:]
    private var omemoConfiguredRoomJIDs: Set<String> = []
    private var chatStatesEnabled = true
    private var knownChatStatePeers: Set<String> = []
    private let archivePageSize = ArchiveMessageBatchPolicy.pageSize
    private let archiveBootstrapMessageLimit = ArchiveMessageBatchPolicy.bootstrapMessageLimit
    private let archiveApplyBatchSize = ArchiveMessageBatchPolicy.decodeSliceSize
    private let archiveForegroundRefreshInterval: TimeInterval = 60
    private static let replyNamespace = "urn:xmpp:reply:0"
    private static let fallbackNamespace = "urn:xmpp:fallback:0"
    private static let retractionNamespace = "urn:xmpp:message-retract:1"
    private static let reactionsNamespace = "urn:xmpp:reactions:0"
    private static let stanzaIDNamespace = "urn:xmpp:sid:0"
    private static let extendedAddressingNamespace = "http://jabber.org/protocol/address"

    init(callEngine: LumaCallEngine? = nil) {
        let callEngine = callEngine ?? LumaCallEngine()
        self.callEngine = callEngine
        callEngine.snapshotHandler = { [weak self] snapshot in
            self?.eventHandler?(.call(snapshot))
        }
        callEngine.historyHandler = { [weak self] entry in
            self?.eventHandler?(.callHistory(entry))
        }
        callEngine.errorHandler = { [weak self] message in
            self?.eventHandler?(.callError(message))
        }
    }

    var connectionStatus: ConnectionStatus {
        guard let client else { return .disconnected(reason: nil) }
        switch client.state {
        case .connecting, .disconnecting:
            return .connecting
        case .connected:
            return .connected
        case .disconnected(let reason):
            return .disconnected(reason: reasonText(reason))
        }
    }

    func connect(
        account: AccountConfiguration,
        password: String,
        archiveCheckpoint: ArchiveSyncCheckpoint? = nil,
        mamCheckpoints: [MAMArchiveKey: MAMArchiveCheckpoint] = [:]
    ) async throws {
        await disconnect()
        cancellables.removeAll()
        archiveSyncStarted = false
        archiveSyncCompletedForConnection = false
        archiveSyncCheckpoint = archiveCheckpoint
        self.mamCheckpoints = mamCheckpoints
        archiveSyncQueryStartedAt = nil
        archivePagination = ArchiveSyncPagination()
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = nil
        archiveAutoRetryCount = 0
        archiveActiveQueryID = nil
        archiveResumeAfter = nil
        archiveWorkBudget = ArchiveSyncWorkBudget()
        archiveHighWatermark = nil
        archiveLastCompletedCursor = archiveCheckpoint?.cursor
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false
        archivePassMutations.removeAll(keepingCapacity: false)
        archiveIsBootstrapQuery = false
        archiveRetrySuppressedUntilActivation = false
        archiveStanzaBuffer.removeAll(keepingCapacity: false)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        archiveStanzaInbox.cancel()
        pendingMUCCatchups.removeAll()
        activeMUCCatchup = nil
        mucCursorFallbackArchives.removeAll()
        mucCatchupHighWatermark = nil
        mucCatchupLastCursor = nil
        setArchiveSyncIndicator(false)
        avatarRequests.removeAll()
        observedRoomJIDs.removeAll()
        roomOccupantsByJID.removeAll()
        roomRealJIDByNickname.removeAll()
        omemoConfiguredRoomJIDs.removeAll()
        knownChatStatePeers.removeAll()
        negotiatedSASLMechanism = nil
        negotiatedTLSVersion = nil
        negotiatedTLSCipher = nil
        tlsProbeTask?.cancel()
        tlsProbeTask = nil
        channelBindingStore.reset()
        advertisedSASLMechanisms = []
        advertisedSASL2Mechanisms = []

        let account = try account.validated()
        self.account = account

        let client = XMPPClient()
        let omemoStorage = LumaOMEMOStore(accountJID: account.normalizedJID)
        guard let signalContext = SignalContext(withStorage: omemoStorage) else {
            throw LumaXMPPError.omemoInitializationFailed
        }
        // Clean up an invalid self-session left behind by a previous buggy
        // build (one-time migration per account).
        omemoStorage.removeSessionWithOwnDeviceOnce()

        configureModules(client: client, signalContext: signalContext, omemoStorage: omemoStorage)
        configureConnection(client: client, account: account, password: password)
        activePassword = password
        subscribe(to: client, omemoStorage: omemoStorage)

        // The self-session must be rebuilt after the modules exist: the
        // ensureSelfSession lookup goes through the modules manager and
        // crashes on a not-yet-registered OMEMO module.
        ensureSelfSession(client: client, omemoStorage: omemoStorage)

        self.client = client
        self.omemoStorage = omemoStorage
        callEngine.attach(client: client)
        eventHandler?(.connection(.connecting))

        do {
            try await client.loginAndWait()
            let now = Date()
            lastLoginDate = now
            let streamManagement = client.module(.streamManagement)
            if streamManagement.ackEnabled || streamManagement.resumptionEnabled {
                smacksSessionEstablishedDate = now
            }
            eventHandler?(.connection(.connected))
            fetchAvatar(for: account.normalizedJID)
            startArchiveSyncIfAvailable()
        } catch {
            callEngine.detach()
            let message = connectionFailureMessage(for: error)
            eventHandler?(.connection(.disconnected(reason: message)))
            throw LumaXMPPError.connection(message)
        }
    }

    func disconnect() async {
        callEngine.detach()
        finishOlderHistory(result: .failure(LumaXMPPError.notConnected))
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = nil
        archiveAutoRetryCount = 0
        archiveActiveQueryID = nil
        archiveResumeAfter = nil
        archiveWorkBudget = ArchiveSyncWorkBudget()
        archiveHighWatermark = nil
        archiveLastCompletedCursor = archiveSyncCheckpoint?.cursor
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false
        archivePassMutations.removeAll(keepingCapacity: false)
        archiveIsBootstrapQuery = false
        archiveRetrySuppressedUntilActivation = false
        archiveStanzaBuffer.removeAll(keepingCapacity: false)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        archiveStanzaInbox.cancel()
        if archiveSyncStarted, let client {
            client.module(.omemo).mamSyncFinished(for: nil)
        }
        setArchiveSyncIndicator(false)
        archiveSyncStarted = false
        archiveSyncCompletedForConnection = false
        archiveSyncQueryStartedAt = nil
        archivePagination = ArchiveSyncPagination()
        guard let client else { return }
        if client.state == .connected() || client.state == .connecting {
            try? await client.disconnect(force: false)
        }
        self.client = nil
        omemoStorage?.flushPendingPersistence()
        omemoStorage = nil
        cancellables.removeAll()
        avatarRequests.removeAll()
        observedRoomJIDs.removeAll()
        roomOccupantsByJID.removeAll()
        roomRealJIDByNickname.removeAll()
        omemoConfiguredRoomJIDs.removeAll()
        knownChatStatePeers.removeAll()
        connectionStatsModule = nil
        saslFailureModule = nil
        lastLoginDate = nil
        smacksSessionEstablishedDate = nil
        negotiatedSASLMechanism = nil
        negotiatedTLSVersion = nil
        negotiatedTLSCipher = nil
        tlsProbeTask?.cancel()
        tlsProbeTask = nil
        eventHandler?(.connection(.disconnected(reason: nil)))
    }

    func setChatStatesEnabled(_ enabled: Bool) {
        chatStatesEnabled = enabled
    }

    func prepareDirectChat(with recipient: String) {
        guard let client, client.state == .connected() else { return }
        let peer = BareJID(recipient.lowercased())
        let manager = client.module(.message).chatManager
        if manager.chat(for: client, with: peer) == nil {
            _ = manager.createChat(for: client, with: peer)
        }
    }

    func setApplicationActive(_ active: Bool) {
        guard let client, client.state == .connected() else { return }
        _ = client.module(.csi).setState(active)
        if active {
            archiveRetrySuppressedUntilActivation = false
            archiveAutoRetryCount = 0
            archiveSyncRetryTask?.cancel()
            archiveSyncRetryTask = nil
            refreshArchiveIfNeeded(client: client)
        } else {
            // iOS may freeze network callbacks and timeout tasks while the
            // scene is inactive. Close the visible MAM pass now so it cannot
            // return with a stale spinner after the app becomes active again.
            pauseArchiveSync(client: client)
        }
    }

    /// Media staging, encryption and MAM decryption compete for main-thread and
    /// I/O time. Keep MAM finite and paused until camera/gallery work and the
    /// corresponding upload have released their resources.
    func setArchiveSyncSuspendedForMediaWork(_ suspended: Bool) {
        archiveResumeAfterMediaWorkTask?.cancel()
        archiveResumeAfterMediaWorkTask = nil

        if suspended {
            guard !archiveSyncSuspended else { return }
            archiveSyncSuspended = true
            if let client, client.state == .connected() {
                pauseArchiveSync(client: client)
            }
            return
        }

        guard archiveSyncSuspended else { return }
        archiveResumeAfterMediaWorkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: ArchiveSyncRecoveryPolicy.resumeAfterCaptureDelayNanoseconds
            )
            guard !Task.isCancelled, let self else { return }
            self.archiveResumeAfterMediaWorkTask = nil
            self.archiveSyncSuspended = false
            guard let client = self.client,
                client.state == .connected()
            else { return }
            self.startArchiveSyncIfAvailable()
        }
    }

    func reconnectIfNeeded(password: String, archiveCheckpoint: ArchiveSyncCheckpoint? = nil)
        async throws
    {
        guard connectionStatus != .connected, let account else { return }
        if let archiveCheckpoint {
            self.archiveSyncCheckpoint = archiveCheckpoint
        }
        try await connect(
            account: account, password: password, archiveCheckpoint: archiveSyncCheckpoint)
    }

    func startCall(to peerJID: String, withVideo: Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            callEngine.startCall(to: peerJID, withVideo: withVideo) { result in
                continuation.resume(with: result)
            }
        }
    }

    func answerCall() async throws {
        try await withCheckedThrowingContinuation { continuation in
            callEngine.answerCall { result in
                continuation.resume(with: result)
            }
        }
    }

    func rejectCall() {
        callEngine.rejectCall()
    }

    func endCall() {
        callEngine.endCall()
    }

    func setCallMuted(_ muted: Bool) {
        callEngine.setMuted(muted)
    }

    func setCallCameraEnabled(_ enabled: Bool) {
        callEngine.setCameraEnabled(enabled)
    }

    func setCallSpeakerEnabled(_ enabled: Bool) {
        callEngine.setSpeakerEnabled(enabled)
    }

    func switchCallCamera() {
        callEngine.switchCamera()
    }

    func localCallVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        callEngine.localVideoTrack(for: callID)
    }

    func remoteCallVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        callEngine.remoteVideoTrack(for: callID)
    }

    func joinRoom(
        roomJID rawRoomJID: String,
        nickname rawNickname: String,
        password: String? = nil
    ) async throws {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }
        let roomJID = rawRoomJID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = roomJID.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw LumaXMPPError.invalidRoomJID
        }
        let nickname = rawNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else { throw LumaXMPPError.emptyRoomNickname }

        let muc = client.module(.muc)
        let result: RoomJoinResult = try await withCheckedThrowingContinuation { continuation in
            muc.join(
                roomName: String(parts[0]),
                mucServer: String(parts[1]),
                nickname: nickname,
                password: password
            ) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }

        let room: RoomProtocol
        switch result {
        case .created(let createdRoom):
            room = createdRoom
            do {
                try await configureInstantRoom(createdRoom, using: muc)
            } catch {
                try await muc.leave(room: createdRoom)
                throw error
            }
        case .joined(let joinedRoom):
            room = joinedRoom
        }
        observe(room: room)
        enqueueMUCCatchup(roomJID: room.jid)
        
        eventHandler?(
            .roomState(
                RoomStateEnvelope(
                    roomJID: room.jid.stringValue,
                    nickname: room.nickname,
                    joined: room.state == .joined,
                    occupantCount: 0
                )))
    }

    func leaveRoom(roomJID: String) {
        guard let client else { return }
        let normalized = roomJID.lowercased()
        let muc = client.module(.muc)
        guard let room = muc.roomManager.room(for: client, with: BareJID(normalized)) else {
            return
        }
        muc.leave(room: room)
        observedRoomJIDs.remove(normalized)
        roomOccupantsByJID.removeValue(forKey: normalized)
        roomRealJIDByNickname.removeValue(forKey: normalized)
        omemoConfiguredRoomJIDs.remove(normalized)
        eventHandler?(
            .roomState(
                RoomStateEnvelope(
                    roomJID: normalized,
                    nickname: room.nickname,
                    joined: false,
                    occupantCount: 0
                )))
    }

    func inviteMembers(_ jids: [String], to roomJID: String) async throws {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }
        let normalized = roomJID.lowercased()
        let muc = client.module(.muc)
        guard let room = muc.roomManager.room(for: client, with: BareJID(normalized)),
            room.state == .joined
        else {
            throw LumaXMPPError.roomNotJoined
        }
        let invitees = jids.map {
            JID($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        let ownAffiliation = room.occupant(nickname: room.nickname)?.affiliation ?? room.affiliation
        if ownAffiliation == .owner || ownAffiliation == .admin {
            let owners = try? await roomAffiliations(
                in: room,
                affiliation: .owner,
                using: muc
            )
            let admins = try? await roomAffiliations(
                in: room,
                affiliation: .admin,
                using: muc
            )
            if let owners, let admins {
                let privilegedJIDs = Set((owners + admins).map { $0.jid.bareJid })
                let memberships =
                    invitees
                    .filter { !privilegedJIDs.contains($0.bareJid) }
                    .map {
                        MucModule.RoomAffiliation(jid: $0, affiliation: .member)
                    }
                if !memberships.isEmpty {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<Void, Error>) in
                        muc.setRoomAffiliations(to: room, changedAffiliations: memberships) {
                            result in
                            continuation.resume(with: result)
                        }
                    }
                }
            }
        }
        for invitee in invitees {
            try await muc.invite(
                to: room,
                invitee: invitee,
                reason: "Приглашение в групповой чат Luma"
            )
        }
    }

    /// Sends a `<call-history/>` service message to the user's own bare JID
    /// so Carbons deliver it to the other devices and MAM archives it. The
    /// message is plaintext and never reaches the call counterpart.
    func syncCallHistory(_ entry: CallHistoryEntry) {
        guard let client, client.state == .connected(), let account else { return }
        let message = Message()
        message.to = JID(account.normalizedJID)
        message.type = .chat
        message.id = entry.id
        message.body = Self.callHistoryBody(entry)
        addOriginID(entry.id, to: message)
        message.addChild(CallHistorySync.payloadElement(entry: entry))
        client.context.writer.write(message, writeCompleted: nil)
        Logger(subsystem: "Luma", category: "call-sync")
            .info("sent call-history id=\(entry.id) peer=\(entry.peerJID) status=\(entry.outcome.rawValue)")
    }

    /// Sends a `<read-marker/>` service message to the user's own bare JID
    /// so Carbons deliver it to the other devices and MAM archives it. The
    /// message is plaintext and never reaches the chat counterpart; MUC read
    /// state rides the same self-addressed envelope and never enters the room
    /// archive.
    func syncReadState(_ marker: ReadStateSync.Envelope) {
        guard let client, client.state == .connected(), let account else { return }
        let message = Message()
        message.to = JID(account.normalizedJID)
        message.type = .chat
        message.id = marker.id
        message.body = Self.readMarkerBody
        addOriginID(marker.id, to: message)
        message.addChild(ReadStateSync.payloadElement(marker: marker))
        client.context.writer.write(message, writeCompleted: nil)
        Logger(subsystem: "Luma", category: "read-sync")
            .info("sent read-marker id=\(marker.id) message=\(marker.messageID) conversation=\(marker.conversationJID)")
    }

    /// Sends an XEP-0333 `<displayed/>` chat marker so the peer's client can
    /// show the message as read. Markers are never sent to MUC rooms
    /// (XEP-0333 forbids them there); the read state of outgoing MUC messages
    /// only changes when a member's client sends a marker anyway or when
    /// another of the user's devices broadcasts a read-marker sync message.
    func sendDisplayedMarker(messageID: String, to peerJID: String) {
        guard let client, client.state == .connected() else { return }
        let message = Message()
        message.to = JID(peerJID)
        message.type = .chat
        message.chatMarkers = .displayed(id: messageID)
        client.context.writer.write(message, writeCompleted: nil)
    }

    private static let readMarkerBody = "Сообщение прочитано"

    /// Detects OMEMO 2 (`urn:xmpp:omemo:2`) payloads, which the pinned
    /// MartinOMEMO version cannot decrypt (it only speaks the legacy
    /// `eu.siacs.conversations.axolotl` namespace).
    private static func isOMEMO2Payload(_ message: Message) -> Bool {
        message.element.findChild(name: "encrypted", xmlns: "urn:xmpp:omemo:2") != nil
    }

    private static func callHistoryBody(_ entry: CallHistoryEntry) -> String {
        let kind = entry.isVideo ? "Видеозвонок" : "Аудиозвонок"
        switch entry.outcome {
        case .completed: return "\(kind) завершён"
        case .missed: return "Пропущенный \(kind.lowercased())"
        case .declined: return "Отклонённый \(kind.lowercased())"
        case .cancelled: return "Отменённый \(kind.lowercased())"
        case .unanswered: return "\(kind) без ответа"
        case .failed: return "Неудачный \(kind.lowercased())"
        case .answeredElsewhere: return "\(kind) принят на другом устройстве"
        }
    }


    func sendText(
        _ text: String,
        to recipient: String,
        messageID: String,
        encrypted: Bool,
        outOfBandURL: String? = nil,
        replacingMessageID: String? = nil,
        replyTo: ReplyReference? = nil,
        isGroup: Bool = false
    ) async throws -> String? {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }

        let wireBody: String
        let replyFallback: (prefix: String, scalarCount: Int)?
        if let replyTo {
            let fallback = MessageReplyFallback.make(
                author: replyTo.fallbackAuthor,
                preview: replyTo.preview
            )
            wireBody = fallback.prefix + text
            replyFallback = fallback
        } else {
            wireBody = text
            replyFallback = nil
        }

        if isGroup {
            let roomJID = BareJID(recipient.lowercased())
            let muc = client.module(.muc)
            guard let room = muc.roomManager.room(for: client, with: roomJID),
                room.state == .joined
            else {
                throw LumaXMPPError.roomNotJoined
            }
            let message = room.createMessage(text: wireBody, id: messageID)
            addOriginID(messageID, to: message)
            message.lastMessageCorrectionId = replacingMessageID
            if chatStatesEnabled { message.chatState = .active }
            addReply(replyTo, fallback: replyFallback, to: message)
            if !encrypted, let outOfBandURL { message.oob = outOfBandURL }
            if encrypted {
                let recipients = try await groupOMEMORecipients(
                    in: room,
                    using: muc,
                    client: client
                )
                // OMEMO 2 only when every member publishes OMEMO 2 devices;
                // otherwise the legacy protocol keeps legacy members readable.
                // Device lists are fetched on demand so a first message to a
                // room never falls back to legacy just because the lists are
                // not cached yet.
                if let omemo2 = client.moduleOrNil(.omemo2),
                    omemo2.isReady,
                    await Self.allRecipientsPublishOMEMO2(recipients, module: omemo2) {
                    let encryptedMessage = try await encrypt(
                        message,
                        forGroupRecipients: recipients,
                        using: omemo2,
                        roomJID: roomJID
                    )
                    try await room.send(message: encryptedMessage.message)
                    return encryptedMessage.fingerprint
                }
                guard let omemo = client.moduleOrNil(.omemo), omemo.isReady else {
                    throw LumaXMPPError.omemoNotReady
                }
                let encryptedMessage = try await encrypt(
                    message,
                    forGroupRecipients: recipients,
                    using: omemo
                )
                try await room.send(message: encryptedMessage.message)
                return encryptedMessage.fingerprint
            } else {
                try await room.send(message: message)
                return nil
            }
        }

        let peer = BareJID(recipient.lowercased())
        let manager = client.module(.message).chatManager
        guard
            let chat = manager.chat(for: client, with: peer)
                ?? manager.createChat(for: client, with: peer)
        else {
            throw LumaXMPPError.cannotCreateChat
        }

        let message = chat.createMessage(text: wireBody, id: messageID)
        addOriginID(messageID, to: message)
        message.lastMessageCorrectionId = replacingMessageID
        if chatStatesEnabled { message.chatState = .active }
        addReply(replyTo, fallback: replyFallback, to: message)
        if !encrypted, let outOfBandURL {
            message.oob = outOfBandURL
        }
        if encrypted {
            // Prefer OMEMO 2 when the peer publishes OMEMO 2 devices; legacy
            // OMEMO stays as the fallback for legacy-only contacts. The
            // peer's device list is fetched on demand, so the very first
            // message to an OMEMO 2-only contact no longer falls back to
            // legacy.
            if let omemo2 = client.moduleOrNil(.omemo2),
                omemo2.isReady,
                await !(omemo2.deviceIDs(for: peer, fetching: true) ?? []).isEmpty {
                let encryptedMessage = try await encrypt(message, using: omemo2)
                try await chat.send(message: encryptedMessage.message)
                return encryptedMessage.fingerprint
            }
            guard let omemo = client.moduleOrNil(.omemo), omemo.isReady else {
                throw LumaXMPPError.omemoNotReady
            }
            let encryptedMessage = try await encrypt(message, using: omemo)
            try await chat.send(message: encryptedMessage.message)
            return encryptedMessage.fingerprint
        } else {
            try await chat.send(message: message)
            return nil
        }
    }
    
    /// OpenSSL version strings to their user-facing form ("TLSv1.3" →
    /// "TLS 1.3").
    private static func displayTLSVersion(_ version: String) -> String {
        switch version {
        case "TLSv1.3": return "TLS 1.3"
        case "TLSv1.2": return "TLS 1.2"
        case "TLSv1.1": return "TLS 1.1"
        case "TLSv1": return "TLS 1.0"
        default: return version
        }
    }

    /// True when every MUC recipient has a non-empty OMEMO 2 device list.
    /// Fetches the lists from PEP on demand for recipients that have not been
    /// cached yet.
    private static func allRecipientsPublishOMEMO2(
        _ recipients: [BareJID],
        module: LumaOMEMO2Module
    ) async -> Bool {
        for recipient in recipients {
            let devices = await module.deviceIDs(for: recipient, fetching: true) ?? []
            if devices.isEmpty { return false }
        }
        return true
    }

    /// Loads one older MAM page for a single conversation. `before` is the
    /// oldest server/MAM id currently known by the UI. For direct chats the
    /// query is scoped with XEP-0313 `with`; for MUC the IQ is addressed to the
    /// room archive itself. The completion carries the cursor for the next,
    /// older page (RSM <first> of the returned page).
    func loadOlderHistory(
        conversationJID: String,
        isGroup: Bool,
        before: String?,
        completion: @escaping (Result<OlderHistoryScrollPage, Error>) -> Void
    ) {
        guard let client, client.state == .connected() else {
            completion(.failure(LumaXMPPError.notConnected))
            return
        }
        // Interactive backward-history is fully independent from catch-up: it
        // owns a query-ID-scoped inbox entry and its own mutation collector, so
        // it must never wait for an account/MUC catch-up pass to settle.
        performOlderHistoryRequest(
            conversationJID: conversationJID,
            isGroup: isGroup,
            before: before,
            completion: completion
        )
    }
    
    private func performOlderHistoryRequest(
        conversationJID: String,
        isGroup: Bool,
        before: String?,
        completion: @escaping (Result<OlderHistoryScrollPage, Error>) -> Void
    ) {
        guard let client, client.state == .connected() else {
            completion(.failure(LumaXMPPError.notConnected))
            return
        }
        guard let version = client.module(.mam).availableVersions.first else {
            completion(.failure(LumaXMPPError.connection("MAM недоступен")))
            return
        }

        let archive = isGroup
        ? MAMArchiveKey.muc(conversationJID)
        : MAMArchiveKey.account(client.userBareJid.stringValue)
        // Only one interactive backward-history query is allowed at a time.
        // This is independent from the normal account/MUC catch-up query.
        if let previous = olderHistoryCompletion {
            // AppModel normally serializes requests, but never leak the
            // previous completion if a request does slip through.
            previous(.failure(LumaXMPPError.connection("Запрос истории заменён более новым.")))
        }
        olderHistoryTimeoutTask?.cancel()
        olderHistoryTimeoutTask = nil
        interactiveHistoryMutations = nil
        let queryID = UUID().uuidString
        olderHistoryQueryID = queryID
        olderHistoryCompletion = completion
        archiveStanzaInbox.begin(
            queryID: queryID,
            allowedSources: allowedMAMSources(for: archive, client: client)
        )
        scheduleOlderHistoryTimeout(
            client: client,
            queryID: queryID,
            conversationJID: conversationJID
        )

        // Martin 3.2.4's convenience overload accidentally clears `with`.
        // Construct MAMQueryForm explicitly so direct-chat history is truly
        // scoped to this peer.
        let form = MAMQueryForm(version: version)
        if !isGroup {
            form.with = JID(conversationJID.lowercased())
        }
        let componentJID: JID? = isGroup ? JID(conversationJID.lowercased()) : nil
        let rsm: RSM.Query = before.map {
            RSM.Query(before: $0, max: archivePageSize)
        } ?? RSM.Query(lastItems: archivePageSize)

        client.module(.mam).queryItems(
            version: version,
            componentJid: componentJID,
            query: form,
            queryId: queryID,
            rsm: rsm
        ) { [weak self, weak client] result in
            DispatchQueue.main.async {
                guard let self else {
                    completion(.failure(LumaXMPPError.notConnected))
                    return
                }
                guard let client, self.client === client else {
                    self.finishOlderHistory(result: .failure(LumaXMPPError.notConnected))
                    return
                }
                guard self.olderHistoryQueryID == queryID else {
                    // A newer request, a timeout, or a disconnect already owns
                    // the slot and has released this completion.
                    return
                }
                self.olderHistoryTimeoutTask?.cancel()
                self.olderHistoryTimeoutTask = nil
                let page = self.archiveStanzaInbox.take(queryID: queryID)
                guard !page.overflowed, !page.rejectedSource else {
                    self.finishOlderHistory(
                        result: .failure(LumaXMPPError.connection("Некорректная MAM history page"))
                    )
                    return
                }

                Task { @MainActor [weak self, weak client] in
                    guard let self else { return }
                    guard let client, self.client === client else {
                        self.finishOlderHistory(result: .failure(LumaXMPPError.notConnected))
                        return
                    }
                    // Collect this page's mutations in a dedicated buffer so a
                    // concurrently-running catch-up pass never interleaves its
                    // mutations with the interactive page.
                    self.interactiveHistoryMutations = []
                    for stanza in page.stanzas {
                        if stanza.message.type == .groupchat,
                           let roomJID = stanza.message.from?.bareJid {
                            await self.handle(
                                groupMessage: stanza.message,
                                archivedRoomJID: roomJID,
                                archivedTimestamp: stanza.timestamp,
                                archiveID: stanza.archiveID,
                                isArchived: true
                            )
                        } else {
                            await self.handle(
                                message: stanza.message,
                                timestamp: stanza.timestamp,
                                archiveID: stanza.archiveID,
                                isArchived: true,
                                archivedPeerJID: isGroup ? nil : BareJID(conversationJID.lowercased())
                            )
                        }
                    }
                    let historyMutations = self.interactiveHistoryMutations ?? []
                    self.interactiveHistoryMutations = nil
                    if !historyMutations.isEmpty {
                        self.eventHandler?(.archiveBatch(historyMutations))
                    }
                    switch result {
                    case .success(let response):
                        // The next page's anchor is the server's RSM <first>
                        // of this page. Pages that insert nothing (reactions,
                        // retractions, duplicates) still advance the cursor,
                        // so the next scroll requests genuinely older history
                        // instead of the same page again.
                        self.finishOlderHistory(
                            result: .success(
                                OlderHistoryScrollPolicy.page(
                                    complete: response.complete,
                                    pageFirstID: response.rsm?.first
                                )
                            ))
                    case .failure(let error):
                        // Do not leave the UI in the loading state. A failed
                        // interactive query is recoverable by the next scroll.
                        self.finishOlderHistory(result: .failure(error))
                    }
                }
            }
        }
    }

    private func scheduleOlderHistoryTimeout(
        client: XMPPClient,
        queryID: String,
        conversationJID: String
    ) {
        olderHistoryTimeoutTask?.cancel()
        olderHistoryTimeoutTask = Task { @MainActor [weak self, weak client] in
            try? await Task.sleep(nanoseconds: self?.olderHistoryQueryTimeoutNanoseconds ?? 15_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  let client,
                  self.client === client,
                  self.olderHistoryQueryID == queryID
            else {
                return
            }

            self.archiveStanzaInbox.cancel(queryID: queryID)
            self.eventHandler?(
                .recoverableError(
                    "Не удалось загрузить более старую историю чата \(conversationJID): MAM не ответил за 15 секунд."
                )
            )
            self.finishOlderHistory(
                result: .failure(
                    LumaXMPPError.connection(
                        "MAM не ответил вовремя. Повторите прокрутку вверх."
                    )
                )
            )
        }
    }

    /// Releases the in-flight interactive backward-history request exactly once.
    /// Every terminal path (success, failure, timeout, disconnect, background)
    /// funnels through here so the UI's "loading older history" spinner can
    /// never be left stuck.
    private func finishOlderHistory(result: Result<OlderHistoryScrollPage, Error>) {
        guard olderHistoryCompletion != nil else { return }
        let completion = olderHistoryCompletion
        olderHistoryCompletion = nil
        olderHistoryQueryID = nil
        olderHistoryTimeoutTask?.cancel()
        olderHistoryTimeoutTask = nil
        interactiveHistoryMutations = nil
        completion?(result)
    }

    func sendRetraction(
        to recipient: String,
        targetID: String,
        retractionID: String,
        encrypted: Bool
    ) async throws {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }

        let peer = BareJID(recipient.lowercased())
        let manager = client.module(.message).chatManager
        guard
            let chat = manager.chat(for: client, with: peer)
                ?? manager.createChat(for: client, with: peer)
        else {
            throw LumaXMPPError.cannotCreateChat
        }

        let fallbackText =
            "/me удалил(а) сообщение. Обновите клиент, если оно всё ещё отображается."
        let message = chat.createMessage(text: fallbackText, id: retractionID)
        let retract = Element(name: "retract", xmlns: Self.retractionNamespace)
        retract.setAttribute("id", value: targetID)
        message.addChild(retract)

        let fallback = Element(name: "fallback", xmlns: Self.fallbackNamespace)
        fallback.setAttribute("for", value: Self.retractionNamespace)
        message.addChild(fallback)
        message.hints = [.store]

        if encrypted {
            guard let omemo = client.moduleOrNil(.omemo), omemo.isReady else {
                throw LumaXMPPError.omemoNotReady
            }
            let encryptedMessage = try await encrypt(message, using: omemo)
            try await chat.send(message: encryptedMessage.message)
        } else {
            try await chat.send(message: message)
        }
    }

    func sendReactions(
        to recipient: String,
        targetID: String,
        emojis: [String],
        reactionMessageID: String,
        isGroup: Bool
    ) async throws {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }
        let normalizedTarget = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTarget.isEmpty else { return }

        let reactions = Element(name: "reactions", xmlns: Self.reactionsNamespace)
        reactions.setAttribute("id", value: normalizedTarget)
        for emoji in MessageReactionPolicy.sanitized(emojis) {
            reactions.addChild(Element(name: "reaction", cdata: emoji))
        }

        if isGroup {
            let roomJID = BareJID(recipient.lowercased())
            let muc = client.module(.muc)
            guard let room = muc.roomManager.room(for: client, with: roomJID),
                room.state == .joined
            else {
                throw LumaXMPPError.roomNotJoined
            }
            let message = room.createMessage(id: reactionMessageID, type: .groupchat)
            message.addChild(reactions)
            message.hints = [.store]
            try await room.send(message: message)
            return
        }

        let peer = BareJID(recipient.lowercased())
        let manager = client.module(.message).chatManager
        guard
            let chat = manager.chat(for: client, with: peer)
                ?? manager.createChat(for: client, with: peer)
        else {
            throw LumaXMPPError.cannotCreateChat
        }
        let message = chat.createMessage(id: reactionMessageID, type: .chat)
        message.addChild(reactions)
        message.hints = [.store]
        try await chat.send(message: message)
    }

    func sendChatState(
        _ state: ChatTypingState,
        to recipient: String,
        isGroup: Bool
    ) async throws {
        guard chatStatesEnabled,
            let client,
            client.state == .connected()
        else { return }

        let martinState = Self.martinChatState(state)
        if isGroup {
            let roomJID = BareJID(recipient.lowercased())
            let muc = client.module(.muc)
            guard let room = muc.roomManager.room(for: client, with: roomJID),
                room.state == .joined
            else { return }
            let message = room.createMessage(id: UUID().uuidString, type: .groupchat)
            message.chatState = martinState
            try await room.send(message: message)
            return
        }

        let peer = BareJID(recipient.lowercased())
        let chatStateModule = client.module(.chatStateNotifications)
        let hasSupport =
            knownChatStatePeers.contains(peer.stringValue.lowercased())
            || chatStateModule.hasSupport(jid: peer)
        guard hasSupport else { return }

        let manager = client.module(.message).chatManager
        guard
            let chat = manager.chat(for: client, with: peer)
                ?? manager.createChat(for: client, with: peer)
        else { return }
        let message = chat.createMessage(id: UUID().uuidString, type: .chat)
        message.chatState = martinState
        try await chat.send(message: message)
    }

    func uploadAndSendMedia(
        data: Data,
        filename: String,
        mimeType: String,
        kind: ChatMessage.Kind,
        duration: TimeInterval?,
        to recipient: String,
        messageID: String,
        encrypted: Bool,
        isGroup: Bool = false
    ) async throws -> MediaSendResult {
        guard let client, client.state == .connected() else {
            throw LumaXMPPError.notConnected
        }

        let uploadData: Data
        let uploadFilename: String
        let uploadMimeType: String
        var decryptionFragment: String?
        let transportFilename = MediaMetadata.transportFilename(
            originalFilename: filename,
            kind: kind,
            duration: duration
        )
        if encrypted {
            guard let omemo = client.moduleOrNil(.omemo), omemo.isReady else {
                throw LumaXMPPError.omemoNotReady
            }
            switch omemo.encryptFile(data: data) {
            case .success(let value):
                uploadData = value.0
                decryptionFragment = value.1
            case .failure:
                throw LumaXMPPError.fileEncryptionFailed
            }
            // XEP-0454 uses aesgcm as the URI scheme, not as a filename
            // extension. Keeping the original extension lets Conversations,
            // Monal and other clients recover the media type after decrypting.
            uploadFilename = transportFilename
            uploadMimeType = "application/octet-stream"
        } else {
            uploadData = data
            uploadFilename = transportFilename
            uploadMimeType = mimeType
        }

        let uploadModule = client.module(.httpFileUpload)
        let components: [HttpFileUploadModule.UploadComponent]
        do {
            components = try await uploadModule.findHttpUploadComponents()
        } catch {
            throw LumaXMPPError.uploadDiscoveryFailed(error.localizedDescription)
        }
        guard
            let component =
                components
                .filter({ $0.maxSize >= uploadData.count })
                .max(by: { $0.maxSize < $1.maxSize })
        else {
            throw LumaXMPPError.uploadUnavailable(size: uploadData.count)
        }

        let slot: HttpFileUploadModule.Slot
        do {
            slot = try await uploadModule.requestUploadSlot(
                componentJid: component.jid,
                filename: uploadFilename,
                size: uploadData.count,
                contentType: uploadMimeType
            )
        } catch {
            throw LumaXMPPError.uploadSlotFailed(error.localizedDescription)
        }
        guard slot.putUri.scheme?.lowercased() == "https",
            slot.getUri.scheme?.lowercased() == "https"
        else {
            throw LumaXMPPError.insecureUploadURL
        }

        var request = URLRequest(url: slot.putUri)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue(uploadMimeType, forHTTPHeaderField: "Content-Type")
        for (name, value) in slot.putHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let response: URLResponse
        let uploadConfiguration = URLSessionConfiguration.ephemeral
        uploadConfiguration.timeoutIntervalForRequest = 120
        uploadConfiguration.timeoutIntervalForResource = 300
        uploadConfiguration.waitsForConnectivity = false
        let uploadSession = URLSession(configuration: uploadConfiguration)
        defer { uploadSession.finishTasksAndInvalidate() }
        do {
            let (_, receivedResponse) = try await uploadSession.upload(
                for: request, from: uploadData)
            response = receivedResponse
        } catch {
            throw LumaXMPPError.uploadTransportFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LumaXMPPError.uploadFailed(statusCode: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LumaXMPPError.uploadFailed(statusCode: http.statusCode)
        }

        guard var urlComponents = URLComponents(url: slot.getUri, resolvingAgainstBaseURL: false)
        else {
            throw LumaXMPPError.invalidUploadURL
        }
        if let decryptionFragment {
            urlComponents.scheme = "aesgcm"
            urlComponents.fragment = decryptionFragment
        }

        guard let remoteURL = urlComponents.string else {
            throw LumaXMPPError.invalidUploadURL
        }
        let fingerprint = try await sendText(
            remoteURL,
            to: recipient,
            messageID: messageID,
            encrypted: encrypted,
            outOfBandURL: encrypted ? nil : remoteURL,
            isGroup: isGroup
        )
        return MediaSendResult(remoteURL: remoteURL, fingerprint: fingerprint)
    }

    func downloadAttachment(_ remoteURL: String) async throws -> Data {
        guard var components = URLComponents(string: remoteURL) else {
            throw LumaXMPPError.invalidUploadURL
        }
        let encrypted = components.scheme?.lowercased() == "aesgcm"
        let fragment = components.fragment
        if encrypted {
            components.scheme = "https"
            components.fragment = nil
        } else if components.scheme?.lowercased() != "https" {
            throw LumaXMPPError.invalidUploadURL
        }
        guard let url = components.url else {
            throw LumaXMPPError.invalidUploadURL
        }

        let (downloadedData, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LumaXMPPError.downloadFailed
        }
        guard encrypted else { return downloadedData }
        guard let omemo = client?.moduleOrNil(.omemo), let fragment else {
            throw LumaXMPPError.fileDecryptionFailed
        }
        switch omemo.decryptFile(data: downloadedData, fragment: fragment) {
        case .success(let data):
            return data
        case .failure:
            throw LumaXMPPError.fileDecryptionFailed
        }
    }

    func devices(for jid: String) -> [OMEMODevice] {
        omemoStorage?.devices(for: jid) ?? []
    }

    func setDeviceVerified(_ verified: Bool, jid: String, deviceID: Int32) {
        guard omemoStorage?.setVerified(verified, jid: jid, deviceID: deviceID) == true else {
            return
        }
        eventHandler?(
            .omemo(
                ready: client?.moduleOrNil(.omemo)?.isReady ?? false,
                ownFingerprint: omemoStorage?.ownFingerprint))
    }

    /// Negotiated TLS version of the current connection, probing the
    /// server with a parallel handshake when the underlying library does not
    /// expose it. Single-flight: the first caller starts the probe, later
    /// callers (and later screen refreshes) reuse the stored result.
    private func currentTLSVersion() async -> String? {
        // Prefer the negotiated parameters of the live connection, captured
        // by the OpenSSL TLS processor.
        if let state = channelBindingStore.negotiatedState {
            negotiatedTLSVersion = Self.displayTLSVersion(state.version)
            negotiatedTLSCipher = state.cipher
            return negotiatedTLSVersion
        }
        if let existing = tlsProbeTask {
            return await existing.value?.version
        }
        guard let client, client.state == .connected() else {
            return negotiatedTLSVersion
        }
        let endpointHost: String
        let endpointPort: Int
        if let endpoint = client.connector?.currentEndpoint as? SocketConnector.Endpoint {
            endpointHost = endpoint.host
            endpointPort = endpoint.port
        } else if let account {
            endpointHost = account.manualHost ?? account.domain ?? account.normalizedJID
            endpointPort = account.manualPort ?? (account.usesDirectTLS ? 5223 : 5222)
        } else {
            return negotiatedTLSVersion
        }
        let directTLS = account?.usesDirectTLS ?? (endpointPort == 5223)
        let domain = account?.domain ?? client.userBareJid.domain
        let task = Task.detached(priority: .utility) { () -> TLSProbeResult? in
            await withCheckedContinuation { continuation in
                TLSVersionProbe.run(
                    host: endpointHost,
                    port: UInt32(endpointPort),
                    directTLS: directTLS,
                    expectedDomain: domain
                ) { result in
                    continuation.resume(returning: result)
                }
            }
        }
        tlsProbeTask = task
        let result = await task.value
        if let result {
            negotiatedTLSVersion = result.version
            negotiatedTLSCipher = result.cipher
        }
        return negotiatedTLSVersion
    }

    /// Queries the server's capabilities to populate the "server information"
    /// settings screen: XEP-0030 disco#info (server + account), XEP-0092
    /// software version, conference (MUC) services via disco#items, and
    /// STUN/TURN services via XEP-0215.
    func fetchServerInformation() async throws -> ServerInformation {
        guard let client, client.state == .connected(), let account else {
            throw LumaXMPPError.notConnected
        }
        let disco = client.module(.disco)
        let versionModule = client.module(.softwareVersion)
        let serverDomain = account.domain ?? client.userBareJid.domain

        // Discover features, software version, server components and external
        // services in parallel. The version/components/services queries are
        // best-effort: not every server implements those XEPs, so they degrade
        // to nil instead of failing the whole screen.
        async let serverInfo = disco.serverFeatures()
        async let accountInfo = disco.accountFeatures()
        async let software = try? versionModule.checkSoftwareVersion(
            for: JID(serverDomain)
        )
        async let components = try? disco.serverComponents()
        async let services = try? client.module(.externalServiceDiscovery)
            .discover(from: nil, type: nil)

        let server = try await serverInfo
        let accountDisco = try await accountInfo
        let version = await software
        let componentItems = await components
        let extServices = await services

        // Resolve each server component to its disco identity. Keep conference
        // (MUC) services, and also detect HTTP File Upload when it is announced
        // on a component (e.g. upload.<domain>) rather than the main domain.
        var conferenceServers: [ServerInformation.ConferenceServer] = []
        var uploadOnComponent = false
        if let componentItems {
            for item in componentItems.items {
                guard let info = try? await disco.info(for: item.jid) else { continue }
                if info.features.contains("urn:xmpp:http:upload:0")
                    || info.features.contains("http://jabber.org/protocol/httpupload")
                {
                    uploadOnComponent = true
                }
                for identity in info.identities where identity.category == "conference" {
                    conferenceServers.append(
                        ServerInformation.ConferenceServer(
                            jid: item.jid.stringValue,
                            name: identity.name,
                            type: identity.type,
                            category: identity.category
                        )
                    )
                }
            }
        }

        let externalServices = (extServices ?? []).filter {
            ["stun", "turn", "stuns", "turns"].contains($0.type.lowercased())
        }.map {
            ServerInformation.ExternalService(
                type: $0.type,
                host: $0.host,
                port: $0.port,
                transport: $0.transport?.rawValue
            )
        }

        // SASL mechanisms and Client State Indication are advertised in the raw
        // stream <features>, not in disco#info, so read them from there.
        let streamFeaturesElement = client.module(.streamFeatures).streamFeatures.element
        let saslMechanisms: [String]
        if !advertisedSASLMechanisms.isEmpty {
            // Includes both classic SASL and SASL2 mechanisms when the server
            // advertises them in separate stream-feature elements.
            saslMechanisms = advertisedSASLMechanisms
        } else {
            saslMechanisms = streamFeaturesElement?
                .findChild(name: "mechanisms", xmlns: "urn:ietf:params:xml:ns:xmpp-sasl")?
                .children
                .filter { $0.name == "mechanism" }
                .compactMap { $0.value } ?? []
        }
        // Same fallback pattern for SASL2 mechanisms, channel-binding types
        // and XEP-0474: prefer the values captured from the pre-auth stream
        // features, and only fall back to the live features element when the
        // capture never ran (e.g. the session was resumed without a fresh
        // login).
        let sasl2ForDisplay: [String]
        if !advertisedSASL2Mechanisms.isEmpty {
            sasl2ForDisplay = advertisedSASL2Mechanisms
        } else {
            sasl2ForDisplay = streamFeaturesElement?
                .findChild(name: "authentication", xmlns: "urn:xmpp:sasl:2")?
                .children
                .filter { $0.name == "mechanism" }
                .compactMap { $0.value } ?? []
        }
        let channelBindingTypesForDisplay: [String]
        if !channelBindingStore.advertisedChannelBindingTypes.isEmpty {
            channelBindingTypesForDisplay = Array(
                channelBindingStore.advertisedChannelBindingTypes
            ).sorted()
        } else {
            channelBindingTypesForDisplay = streamFeaturesElement?
                .findChild(name: "sasl-channel-binding", xmlns: "urn:xmpp:sasl-cb:0")?
                .children
                .filter { $0.name == "channel-binding" }
                .compactMap { $0.getAttribute("type") } ?? []
        }
        // XEP-0474 support is detected during the SCRAM exchange: the server
        // includes its downgrade-protection hash in the `h` attribute of the
        // server-first message.
        let downgradeProtectionForDisplay = channelBindingStore.isDowngradeProtectionDetected

        let supportsCSI = streamFeaturesElement?
            .findChild(name: "csi", xmlns: "urn:xmpp:csi:0") != nil
        let supportsRosterVersioning = streamFeaturesElement?
            .findChild(name: "ver", xmlns: "urn:xmpp:features:rosterver") != nil
        let supportsRosterPreApproval = streamFeaturesElement?
            .findChild(name: "sub", xmlns: "urn:xmpp:features:pre-approval") != nil

        let uploadOnServer = server.features.contains("urn:xmpp:http:upload:0")
            || server.features.contains("http://jabber.org/protocol/httpupload")
        let supportsHTTPUpload = uploadOnServer || uploadOnComponent

        let stats = connectionStatsModule?.snapshot
            ?? LumaConnectionStatsModule.Snapshot(sent: 0, acknowledged: 0, received: 0)

        let tlsVersion = await currentTLSVersion()
        // Show the channel-binding type alongside a PLUS mechanism, so the
        // screen reflects how the exchange was actually bound to the TLS
        // channel (tls-exporter preferred, tls-server-end-point fallback).
        let displaySASLMechanism: String?
        if let negotiatedSASLMechanism {
            if negotiatedSASLMechanism.hasSuffix("-PLUS"),
                let bindingType = channelBindingStore.preferredChannelBindingType
            {
                displaySASLMechanism = negotiatedSASLMechanism + " · " + bindingType
            } else {
                displaySASLMechanism = negotiatedSASLMechanism
            }
        } else {
            displaySASLMechanism = nil
        }

        return ServerInformation(
            serverDomain: serverDomain,
            software: ServerInformation.Software(
                name: version?.name,
                version: version?.version,
                os: version?.os
            ),
            identities: server.identities.map {
                ServerInformation.Identity(
                    category: $0.category,
                    type: $0.type,
                    name: $0.name
                )
            },
            serverFeatures: server.features,
            accountFeatures: accountDisco.features,
            conferenceServers: conferenceServers,
            externalServices: externalServices,
            connectionStats: ServerInformation.ConnectionStats(
                lastLogin: lastLoginDate,
                smacksSessionEstablished: smacksSessionEstablishedDate,
                sent: stats.sent,
                acknowledged: stats.acknowledged,
                received: stats.received
            ),
            saslMethods: saslMechanisms,
            sasl2Methods: sasl2ForDisplay,
            channelBindingTypes: channelBindingTypesForDisplay,
            usedChannelBindingType:
                (negotiatedSASLMechanism?.hasSuffix("-PLUS") == true)
                ? channelBindingStore.preferredChannelBindingType
                : nil,
            supportsSCRAMDowngradeProtection: downgradeProtectionForDisplay,
            usedSASLMechanism: negotiatedSASLMechanism,
            tlsVersion: tlsVersion,
            tlsCipher: negotiatedTLSCipher,
            saslMechanism: displaySASLMechanism,
            supportsStreamManagement: client.module(.streamManagement).isAvailable,
            supportsCarbons: client.module(.messageCarbons).isAvailable,
            supportsClientState: supportsCSI,
            supportsHTTPUpload: supportsHTTPUpload,
            supportsRosterVersioning: supportsRosterVersioning,
            supportsRosterPreApproval: supportsRosterPreApproval
        )
    }

    func addToRoster(jid: String, name: String?) {
        guard let client, client.state == .connected() else { return }
        client.module(.roster).addItem(
            jid: JID(jid), name: name, groups: [], completionHandler: nil)
        client.module(.presence).subscribe(to: JID(jid))
        fetchAvatar(for: jid)
    }

    func fetchAvatar(for jid: String, force: Bool = false) {
        guard let client, client.state == .connected() else { return }
        let normalized = jid.lowercased()
        if force {
            avatarRequests.remove(normalized)
        }
        guard avatarRequests.insert(normalized).inserted else { return }

        Task { [weak self] in
            guard let self else { return }
            let data: Data?
            if let pepData = await self.retrievePEPAvatar(for: normalized, client: client) {
                data = pepData
            } else {
                data = await self.retrieveLegacyAvatar(for: normalized, client: client)
            }
            if let data {
                self.eventHandler?(.avatar(jid: normalized, data: data))
            }
        }
    }

    func updateOwnAvatar(pngData: Data) async throws {
        guard let client, client.state == .connected(), let account else {
            throw LumaXMPPError.notConnected
        }
        do {
            let avatar = PEPUserAvatarModule.Avatar(data: pngData, mimeType: "image/png")
            _ = try await client.module(.pepUserAvatar).publishAvatar(avatar: [avatar])
        } catch {
            throw LumaXMPPError.avatarUpdateFailed(error.localizedDescription)
        }

        eventHandler?(.avatar(jid: account.normalizedJID, data: pngData))

        // XEP-0084 is authoritative. vCard-temp is updated as a best-effort
        // compatibility bridge for older clients.
        Task {
            let vcardModule = client.module(.vcardTemp)
            let vcard = (try? await vcardModule.retrieveVCard(from: nil as JID?)) ?? VCard()
            vcard.photos = [VCard.Photo(type: "image/png", binval: pngData.base64EncodedString())]
            _ = try? await vcardModule.publish(vcard: vcard, to: nil)
        }
    }

    /// Rebuilds the self-session from our own published bundle when it is
    /// missing, so encrypt-to-self keeps working after the migration purge.
    private func ensureSelfSession(
        client: XMPPClient,
        omemoStorage: LumaOMEMOStore
    ) {
        let registrationID = omemoStorage.localRegistrationID
        guard registrationID != 0 else { return }
        let address = SignalAddress(
            name: omemoStorage.accountJID,
            deviceId: Int32(bitPattern: registrationID)
        )
        guard !omemoStorage.hasSession(for: address) else { return }
        client.module(.omemo).buildSession(forAddress: address)
    }

    private func configureModules(
        client: XMPPClient,
        signalContext: SignalContext,
        omemoStorage: LumaOMEMOStore
    ) {
        _ = client.modulesManager.register(AuthModule())
        _ = client.modulesManager.register(StreamFeaturesModule())
        // Registered before StreamManagementModule so it can observe the
        // server's `<a h='N'>` acknowledgements for the stanza statistics.
        connectionStatsModule = client.modulesManager.register(
            LumaConnectionStatsModule()
        )
        _ = client.modulesManager.register(StreamManagementModule())
        // Registered before SaslModule so the raw RFC 6120 failure condition
        // is captured before Martin collapses it into SaslError.
        saslFailureModule = client.modulesManager.register(LumaSaslFailureModule())
        // Watches the raw SASL <challenge/> for the XEP-0474 `h=` attribute so
        // the server screen can report downgrade protection regardless of the
        // SCRAM mechanism implementation in use.
        _ = client.modulesManager.register(
            LumaSaslChallengeModule { [weak self] challenge in
                guard let data = Data(base64Encoded: challenge),
                    let text = String(data: data, encoding: .utf8),
                    let parsed = try? SCRAMSHA512.parseServerFirst(
                        text,
                        expectedNoncePrefix: ""
                    ),
                    parsed.downgradeProtectionHash != nil
                else { return }
                self?.channelBindingStore.markDowngradeProtectionDetected()
            }
        )
        // Channel-binding SCRAM first (tls-exporter / tls-server-end-point
        // over the live TLS 1.3 connection), then SCRAM-SHA-512: Martin only
        // ships SHA-1/SHA-256, while modern servers prefer SHA-512. A
        // mechanism is only eligible when the server advertises it, and the
        // PLUS variants additionally gate on available binding data.
        let sasl = client.modulesManager.register(SaslModule())
        sasl.addMechanism(
            LumaScramPlusMechanism(hash: .sha1, channelBindingStore: channelBindingStore),
            first: true
        )
        sasl.addMechanism(
            LumaScramPlusMechanism(hash: .sha256, channelBindingStore: channelBindingStore),
            first: true
        )
        sasl.addMechanism(
            LumaScramPlusMechanism(hash: .sha512, channelBindingStore: channelBindingStore),
            first: true
        )
        sasl.addMechanism(
            LumaScramSha512Mechanism(channelBindingStore: channelBindingStore),
            first: true
        )
        _ = client.modulesManager.register(ResourceBinderModule())
        _ = client.modulesManager.register(SessionEstablishmentModule())
        _ = client.modulesManager.register(
            DiscoveryModule(identity: .init(category: "client", type: "phone", name: "Luma"))
        )
        _ = client.modulesManager.register(
            SoftwareVersionModule(
                version: .init(name: "Luma", version: "0.10.6", os: Self.platformName))
        )
        _ = client.modulesManager.register(PingModule())
        _ = client.modulesManager.register(ClientStateIndicationModule())
        //        _ = client.modulesManager.register(ClientStateIndicationModule())
        _ = client.modulesManager.register(
            RosterModule(rosterManager: RosterManagerBase(store: LumaRosterStore()))
        )
        _ = client.modulesManager.register(PresenceModule(store: DefaultPresenceStore()))
        _ = client.modulesManager.register(
            CapabilitiesModule(additionalFeatures: [
                .lastMessageCorrection,
                .init(rawValue: Self.replyNamespace),
                .init(rawValue: Self.fallbackNamespace),
                .init(rawValue: Self.retractionNamespace),
                .init(rawValue: Self.reactionsNamespace),
                .init(rawValue: ChatStateNotificationsModule.XMLNS),
                .init(rawValue: Self.stanzaIDNamespace),
            ])
        )
        _ = client.modulesManager.register(PubSubModule())
        _ = client.modulesManager.register(PEPUserAvatarModule())
        _ = client.modulesManager.register(VCardTempModule())
        _ = client.modulesManager.register(
            MessageModule(chatManager: ChatManagerBase(store: DefaultChatStore()))
        )
        _ = client.modulesManager.register(ChatStateNotificationsModule())
        _ = client.modulesManager.register(
            MucModule(roomManager: RoomManagerBase(store: LumaRoomStore()))
        )
        _ = client.modulesManager.register(MessageCarbonsModule())
        _ = client.modulesManager.register(MessageArchiveManagementModule())
        let receipts = client.modulesManager.register(MessageDeliveryReceiptsModule())
        receipts.sendReceived = true
        _ = client.modulesManager.register(ChatMarkersModule())
        _ = client.modulesManager.register(HttpFileUploadModule())
        let jingle = client.modulesManager.register(JingleModule(sessionManager: callEngine))
        jingle.register(
            transport: Jingle.Transport.ICEUDPTransport.self,
            features: [
                Jingle.Transport.ICEUDPTransport.XMLNS,
                "urn:xmpp:jingle:apps:dtls:0",
            ]
        )
        jingle.register(
            description: Jingle.RTP.Description.self,
            features: [
                "urn:xmpp:jingle:apps:rtp:1",
                "urn:xmpp:jingle:apps:rtp:audio",
                "urn:xmpp:jingle:apps:rtp:video",
            ]
        )
        jingle.supportsMessageInitiation = true
        _ = client.modulesManager.register(ExternalServiceDiscoveryModule())
        _ = client.modulesManager.register(
            OMEMOModule(
                aesGCMEngine: CryptoKitAESGCMEngine(),
                signalContext: signalContext,
                signalStorage: omemoStorage
            )
        )
        // OMEMO 2 (urn:xmpp:omemo:2) shares the signal storage with the
        // legacy module: Double Ratchet sessions are per-device and
        // namespace-agnostic.
        _ = client.modulesManager.register(
            LumaOMEMO2Module(signalContext: signalContext, signalStorage: omemoStorage)
        )
    }

    private func configureConnection(
        client: XMPPClient,
        account: AccountConfiguration,
        password: String
    ) {
        client.connectionConfiguration.userJid = BareJID(account.normalizedJID)
        client.connectionConfiguration.resource = account.effectiveResource
        client.connectionConfiguration.nickname =
            account.displayName.isEmpty ? nil : account.displayName
        client.connectionConfiguration.credentials = .password(
            password: password,
            authenticationName: nil,
            cache: nil
        )
        let expectedDomain = account.domain ?? account.normalizedJID
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnector.Options.self) {
            options in
            options.conntectionTimeout = 20
            options.sslCertificateValidation = .customValidator { trust in
                CertificateTrustEvaluator.evaluateServerTrust(
                    trust,
                    expectedDomain: expectedDomain
                )
            }
            // SecureTransport caps stream TLS at 1.2 and has no keying
            // exporter, so Luma supplies its own OpenSSL TLS 1.3 processor
            // (TLS 1.3 + STARTTLS + channel binding). Certificate trust is
            // still evaluated through the custom validator above.
            options.networkProcessorProviders = [
                LumaTLSNetworkProcessorProvider(channelBindingStore: channelBindingStore),
            ]
            if let host = account.manualHost {
                let defaultPort = account.usesDirectTLS ? 5223 : 5222
                options.dnsResolver = StaticDNSSrvResolver(
                    host: host,
                    port: account.manualPort ?? defaultPort,
                    directTLS: account.usesDirectTLS
                )
            }
        }
    }

    private func subscribe(to client: XMPPClient, omemoStorage: LumaOMEMOStore) {
        client.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state: state)
            }
            .store(in: &cancellables)

        // When the server advertises SCRAM, swap the password in the
        // connection configuration for its RFC 4013 (SASLprep) form before
        // the challenge response is computed. Martin's SCRAM hashes the raw
        // UTF-8 password, which mismatches SASLprep-compliant servers for
        // passwords with non-ASCII spaces, soft hyphens, fullwidth forms, …
        client.module(.streamFeatures).$streamFeatures
            .compactMap { $0.element }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak client] features in
                guard let self, let client else { return }
                self.applySASLprepIfNeeded(client: client, features: features)
            }
            .store(in: &cancellables)

        client.module(.roster).events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                switch action {
                case .addedOrUpdated(let item):
                    let jid = item.jid.bareJid.stringValue
                    self?.eventHandler?(.rosterItem(jid: jid, name: item.name))
                    self?.fetchAvatar(for: jid)
                case .removed(let jid):
                    self?.eventHandler?(.rosterRemoved(jid: jid.bareJid.stringValue))
                }
            }
            .store(in: &cancellables)

        client.module(.pepUserAvatar).avatarChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.fetchAvatar(for: change.jid.bareJid.stringValue, force: true)
            }
            .store(in: &cancellables)

        client.module(.presence).presencePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.eventHandler?(
                    .presence(
                        jid: change.jid.bareJid.stringValue,
                        online: change.presence.type != .unavailable
                    ))
            }
            .store(in: &cancellables)

        client.module(.message).messagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] incoming in
                Task { @MainActor [weak self] in
                    await self?.deliverOrDelayDirect(incoming.message, timestamp: Date())
                }
            }
            .store(in: &cancellables)

        client.module(.muc).messagesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] incoming in
                Task { @MainActor [weak self] in
                    await self?.deliverOrDelayGroup(incoming.message, room: incoming.room)
                }
            }
            .store(in: &cancellables)

        client.module(.muc).inivitationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invitation in
                self?.eventHandler?(
                    .roomInvitation(
                        RoomInvitationEnvelope(
                            roomJID: invitation.roomJid.stringValue,
                            inviterJID: invitation.inviter?.stringValue,
                            reason: invitation.reason,
                            password: invitation.password
                        )))
            }
            .store(in: &cancellables)

        client.module(.messageCarbons).carbonsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] carbon in
                Task { @MainActor [weak self] in
                    await self?.deliverOrDelayDirect(carbon.message, timestamp: Date())
                }
            }
            .store(in: &cancellables)

        client.module(.messageCarbons).$isAvailable
            .filter { $0 }
            .prefix(1)
            .receive(on: DispatchQueue.main)
            .sink { [weak client] _ in
                client?.module(.messageCarbons).enable()
            }
            .store(in: &cancellables)

        client.module(.messageDeliveryReceipts).receiptsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receipt in
                self?.eventHandler?(.delivered(messageID: receipt.messageId))
            }
            .store(in: &cancellables)

        // XEP-0333 chat markers. Martin republishes markers found on live
        // stanzas, Carbons copies and archived messages through one publisher,
        // so `<displayed/>` markers the server carbon-copies to the user's
        // other devices reach this handler there as well.
        client.module(.chatMarkers).markersPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] received in
                self?.handleChatMarker(received)
            }
            .store(in: &cancellables)

        // Do not enqueue every archived stanza onto DispatchQueue.main. Martin
        // publishes all results before the final IQ callback, so a locked inbox
        // can receive the whole page on the parser queue and hand it to the
        // main actor once. This mirrors Monal's delayed-stanza queue and avoids
        // flooding SwiftUI's run loop on large histories.
        let archiveStanzaInbox = self.archiveStanzaInbox
        client.module(.mam).archivedMessagesPublisher
            .sink { archived in
                archiveStanzaInbox.append(
                    queryID: archived.query.id,
                    source: archived.source,
                    message: archived.message,
                    timestamp: archived.timestamp,
                    archiveID: archived.messageId
                )
            }
            .store(in: &cancellables)

        client.module(.mam).$availableVersions
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.startArchiveSyncIfAvailable()
            }
            .store(in: &cancellables)

        // The UI is ready for encrypted messaging once either protocol
        // has published its keys.
        Publishers.CombineLatest(
            client.module(.omemo).$isReady,
            client.module(.omemo2).$isReady
        )
        .map { legacyReady, omemo2Ready in legacyReady || omemo2Ready }
        .removeDuplicates()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] ready in
            self?.eventHandler?(
                .omemo(ready: ready, ownFingerprint: omemoStorage.ownFingerprint))
        }
        .store(in: &cancellables)
    }

    private func deliverOrDelayDirect(_ message: Message, timestamp: Date) async {
        guard let client else { return }
        let archive = MAMArchiveKey.account(client.userBareJid.stringValue)
        if archiveSyncStarted {
            delayedLiveByArchive[archive, default: []].append(
                .direct(message: message, timestamp: timestamp)
            )
            return
        }
        await handle(message: message, timestamp: timestamp, archiveID: nil)
    }
    
    private func deliverOrDelayGroup(_ message: Message, room: RoomProtocol) async {
        let archive = MAMArchiveKey.muc(room.jid.stringValue)
        if activeMUCCatchup == archive {
            delayedLiveByArchive[archive, default: []].append(
                .group(message: message, room: room)
            )
            return
        }
        await handle(groupMessage: message, room: room)
    }
    
    private func replayDelayedLive(for archive: MAMArchiveKey) async {
        let delayed = delayedLiveByArchive.removeValue(forKey: archive) ?? []
        for item in delayed {
            switch item {
            case .direct(let message, let timestamp):
                await handle(message: message, timestamp: timestamp, archiveID: nil)
            case .group(let message, let room):
                await handle(groupMessage: message, room: room)
            }
        }
    }

    /// XEP-0333 chat markers: `<displayed/>` marks an outgoing message as read,
    /// `<received/>` as delivered. MUC markers are best effort — few clients
    /// send them, but the room stanza-id maps them to the right outgoing
    /// message.
    private func handleChatMarker(_ received: ChatMarkersModule.ChatMarkerReceived) {
        let message = received.message
        guard message.type != .error else { return }
        switch received.marker {
        case .displayed(let id):
            guard let conversationJID = markerConversationJID(for: message) else { return }
            eventHandler?(.read(conversationJID: conversationJID, messageID: id))
        case .received(let id):
            eventHandler?(.delivered(messageID: id))
        case .acknowledged:
            break
        }
    }

    /// Bare JID of the conversation a marker references. Peer markers arrive
    /// with the peer in `from`; our own displayed markers carbon-copied from
    /// another device carry our JID in `from` and the peer in `to`. Groupchat
    /// markers reference the room.
    private func markerConversationJID(for message: Message) -> String? {
        if message.type == .groupchat {
            return message.from?.bareJid.stringValue
        }
        if let from = message.from?.bareJid {
            if let client, from == client.userBareJid {
                return message.to?.bareJid.stringValue ?? from.stringValue
            }
            return from.stringValue
        }
        return message.to?.bareJid.stringValue
    }

    /// Runs OMEMO decryption off the main actor and resumes with the raw
    /// result. Kept as a thin wrapper so `handle` keeps its existing switch
    /// logic and only the expensive `decode` call leaves the main thread.
    private func decodeOmemoOffMain(
        _ message: Message,
        from sender: BareJID,
        serverMsgId: String?,
        module: OMEMOModule
    ) async -> DecryptionResult<Message, SignalError> {
        let queue = omemoDecodeQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = module.decode(message: message, from: sender, serverMsgId: serverMsgId)
                continuation.resume(returning: result)
            }
        }
    }

    /// OMEMO 2 twin of `decodeOmemoOffMain`.
    private func decodeOmemo2OffMain(
        _ message: Message,
        from sender: BareJID,
        serverMsgId: String?,
        module: LumaOMEMO2Module
    ) async -> DecryptionResult<Message, SignalError> {
        let queue = omemoDecodeQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = module.decode(message: message, from: sender, serverMsgId: serverMsgId)
                continuation.resume(returning: result)
            }
        }
    }

    private func handle(state: XMPPClient.State) {
        switch state {
        case .connecting, .disconnecting:
            eventHandler?(.connection(.connecting))
        case .connected:
            eventHandler?(.connection(.connected))
            startArchiveSyncIfAvailable()
        case .disconnected(let reason):
            suspendArchiveSyncForDisconnect()
            eventHandler?(.connection(.disconnected(reason: reasonText(reason))))
        }
    }

    private func handle(
        message: Message,
        timestamp: Date,
        archiveID: String?,
        isArchived: Bool = false,
        archivedPeerJID: BareJID? = nil
    ) async {
        // Call-history service messages sync call cards between the user's
        // devices; they never become ordinary chat messages.
        if let sync = CallHistorySync.envelope(from: message) {
            Logger(subsystem: "Luma", category: "call-sync")
                .info("received call-history id=\(sync.id) peer=\(sync.peerJID) status=\(sync.outcome.rawValue)")
            eventHandler?(.callHistorySync(sync))
            return
        }
        // Read-marker service messages sync read receipts between the user's
        // devices the same way: Carbons deliver them live, MAM replays them
        // after reinstalls. They never become ordinary chat messages.
        if let marker = ReadStateSync.envelope(from: message) {
            Logger(subsystem: "Luma", category: "read-sync")
                .info("received read-marker id=\(marker.id) message=\(marker.messageID) conversation=\(marker.conversationJID)")
            eventHandler?(.readState(marker))
            return
        }
        guard message.type != .error,
            message.type != .groupchat,
            let client,
            let sender = message.from?.bareJid
        else { return }

        let ownJID = client.userBareJid
        let outgoing = sender == ownJID
        // guard let peer = outgoing ? message.to?.bareJid : message.from?.bareJid else { return }
//        let peer: BareJID?
//        if outgoing {
        let peer: BareJID?
        if isArchived, let archivedPeerJID {
            peer = archivedPeerJID
        } else if outgoing {
            peer = message.to?.bareJid ?? message.from?.bareJid
        } else {
            peer = message.from?.bareJid
        }
        guard let peer else { return }

        let security: ChatMessage.Security
        let fingerprint: String?
        let contentMessage: Message?
        let decryptionResult = await (
            Self.isOMEMO2Payload(message)
                ? decodeOmemo2OffMain(
                    message,
                    from: sender,
                    serverMsgId: archiveID,
                    module: client.module(.omemo2)
                )
                : decodeOmemoOffMain(
                    message,
                    from: sender,
                    serverMsgId: archiveID,
                    module: client.module(.omemo)
                )
        )
        switch decryptionResult {
        case .successMessage(let decodedMessage, let value):
            security = .omemo
            fingerprint = value
            contentMessage = decodedMessage
        case .successTransportKey(_, _):
            return
        case .failure(let error):
            switch error {
            case .notEncrypted:
                security = .plaintext
                fingerprint = nil
                contentMessage = message
            case .duplicateMessage:
                // The Double Ratchet message key is single-use: `.duplicateMessage`
                // means this exact stanza was already decrypted on an earlier
                // delivery (carbon, SMACK resend or a previous MAM pass), and its
                // content was handled then. Emitting another bubble here turned the
                // archived echoes of our own receipts, chat markers and resent
                // copies into phantom "Не удалось расшифровать сообщение"
                // placeholders that do not exist on the server. Mirrors the group
                // message path.
                return
            default:
                // Some clients include a plaintext <body> fallback alongside the
                // OMEMO <encrypted> payload. When decryption fails, prefer that
                // fallback so a readable message is never shown as undecryptable.
                if message.body?.isEmpty == false {
                    security = .plaintext
                    fingerprint = nil
                    contentMessage = message
                } else {
                    // An undecryptable outgoing stanza is still part of the
                    // user's own history — e.g. messages written on another
                    // device whose keys this device never had. Dropping them
                    // silently made such conversations look empty even though
                    // the archive has history, so surface them as a
                    // decryption-failed placeholder instead. Echoes of
                    // messages sent from this device carry the same origin-id
                    // as the local optimistic copy and are merged there, so
                    // they never produce a second bubble.
                    security = .decryptionFailed
                    fingerprint = nil
                    contentMessage = nil
                }
            }
        }

        let payload = contentMessage ?? message
        if !isArchived,
            let state = Self.chatTypingState(payload.chatState ?? message.chatState)
        {
            knownChatStatePeers.insert(peer.stringValue.lowercased())
            if !outgoing {
                eventHandler?(
                    .chatState(
                        ChatStateEnvelope(
                            peerJID: peer.stringValue,
                            senderJID: sender.stringValue,
                            senderDisplayName: nil,
                            state: state,
                            isGroupMessage: false
                        )))
            }
        }

        if let reactions = payload.firstChild(name: "reactions", xmlns: Self.reactionsNamespace)
            ?? message.firstChild(name: "reactions", xmlns: Self.reactionsNamespace),
            let targetID = reactions.getAttribute("id"),
            !targetID.isEmpty
        {
            emitReaction(
                ReactionEnvelope(
                    peerJID: peer.stringValue,
                    senderJID: sender.stringValue,
                    targetID: targetID,
                    emojis: reactions.children.compactMap { child in
                        guard child.name == "reaction" else { return nil }
                        return child.value
                    },
                    timestamp: timestamp,
                    isOutgoing: outgoing,
                    isGroupMessage: false
                ),
                isArchived: isArchived
            )
            return
        }

        if let retract = payload.firstChild(name: "retract", xmlns: Self.retractionNamespace)
            ?? message.firstChild(name: "retract", xmlns: Self.retractionNamespace),
            let targetID = retract.getAttribute("id"),
            !targetID.isEmpty
        {
            emitRetraction(
                peer: peer,
                sender: sender,
                targetID: targetID,
                retractionID: payload.id ?? message.id ?? archiveID ?? UUID().uuidString,
                timestamp: timestamp,
                outgoing: outgoing,
                isArchived: isArchived
            )
            return
        }

        if payload.firstChild(name: "retracted", xmlns: Self.retractionNamespace) != nil
            || message.firstChild(name: "retracted", xmlns: Self.retractionNamespace) != nil
        {
            guard let targetID = message.originId ?? message.id ?? archiveID else { return }
            let tombstone =
                payload.firstChild(name: "retracted", xmlns: Self.retractionNamespace)
                ?? message.firstChild(name: "retracted", xmlns: Self.retractionNamespace)
            emitRetraction(
                peer: peer,
                sender: sender,
                targetID: targetID,
                retractionID: tombstone?.getAttribute("id") ?? UUID().uuidString,
                timestamp: timestamp,
                outgoing: outgoing,
                isArchived: isArchived
            )
            return
        }

        let rawBody =
            contentMessage?.body
            ?? (security == .decryptionFailed ? "Не удалось расшифровать сообщение" : nil)
        guard let body = rawBody, !body.isEmpty else { return }

        let reply =
            payload.firstChild(name: "reply", xmlns: Self.replyNamespace)
            ?? message.firstChild(name: "reply", xmlns: Self.replyNamespace)
        let replyFallback =
            payload.children.first { child in
                child.name == "fallback"
                    && child.xmlns == Self.fallbackNamespace
                    && child.getAttribute("for") == Self.replyNamespace
            }
            ?? message.children.first { child in
                child.name == "fallback"
                    && child.xmlns == Self.fallbackNamespace
                    && child.getAttribute("for") == Self.replyNamespace
            }
        let fallbackBody = replyFallback?.findChild(name: "body")
        let parsedReply = MessageReplyFallback.parse(
            body: body,
            fallbackStart: fallbackBody?.getAttribute("start").flatMap(Int.init),
            fallbackEnd: fallbackBody?.getAttribute("end").flatMap(Int.init)
        )
        let visibleBody = parsedReply.body

        let isEncryptedAttachment =
            visibleBody.hasPrefix("aesgcm://")
            && visibleBody.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && URLComponents(string: visibleBody)?.scheme?.lowercased() == "aesgcm"
        let oob = payload.oob ?? message.oob
        let standardOOB = oob?.hasPrefix("https://") == true ? oob : nil
        let attachmentURL = isEncryptedAttachment ? visibleBody : standardOOB
        let transportFilename = attachmentURL.flatMap { value -> String? in
            guard let url = URL(string: value) else { return nil }
            guard var filename = url.lastPathComponent.removingPercentEncoding else { return nil }
            if filename.hasSuffix(".aesgcm") {
                filename = String(filename.dropLast(".aesgcm".count))
            }
            return filename
        }
        let inferred = transportFilename.map(MediaMetadata.infer(from:))
        let kind = inferred?.kind ?? (GeoLocation(uri: visibleBody) == nil ? .text : .location)
        let displayBody =
            attachmentURL == nil
            ? visibleBody
            : Self.displayBody(kind: kind, filename: transportFilename ?? "Вложение")

        // Live 1:1 messages carry their server archive UID in a <stanza-id>
        // element (by = own bare JID). Surface it so the interactive MAM
        // "before" cursor and dedup match the IDs the archive later returns.
        let stanzaID = archiveID ?? Self.accountStanzaID(in: message, accountJID: ownJID)
        let id = message.originId ?? message.id ?? archiveID ?? UUID().uuidString
        emitMessage(
            MessageEnvelope(
                id: id,
                peerJID: peer.stringValue,
                senderJID: sender.stringValue,
                body: displayBody,
                timestamp: timestamp,
                isOutgoing: outgoing,
                security: security,
                kind: kind,
                remoteAttachmentURL: attachmentURL,
                localFilename: transportFilename,
                mimeType: inferred?.mimeType,
                duration: inferred?.duration,
                byteCount: nil,
                fingerprint: fingerprint,
                correctionTargetID: payload.lastMessageCorrectionId
                    ?? message.lastMessageCorrectionId,
                replyToID: reply?.getAttribute("id"),
                replyToJID: reply?.getAttribute("to"),
                replyPreview: parsedReply.preview,
                originID: message.originId,
                stanzaID: stanzaID,
                senderDisplayName: nil,
                isGroupMessage: false,
                isArchived: isArchived
            ), isArchived: isArchived)
    }

    private func handle(
        groupMessage message: Message,
        room: RoomProtocol? = nil,
        archivedRoomJID: BareJID? = nil,
        archivedTimestamp: Date? = nil,
        archiveID: String? = nil,
        isArchived: Bool = false
    ) async {
        guard message.type != .error,
            let client,
            let from = message.from,
            let roomBareJID = room?.jid ?? archivedRoomJID ?? message.from?.bareJid
        else { return }

        let nickname = from.resource ?? "Участник"
//        let outgoing = nickname == room.nickname
//        let roomJID = room.jid.stringValue.lowercased()
        let disclosedSender = Self.originalSenderJID(in: message)
        ?? XMucUserElement.extract(from: message)?.jid?.bareJid
        let outgoing = room.map { nickname == $0.nickname }
        ?? (disclosedSender == client.userBareJid)
        let roomJID = roomBareJID.stringValue.lowercased()
        // In a MUC the author address used by XEP-0461 is the full occupant
        // JID (room@service/nickname), not the participant's disclosed real JID.
        let senderJID = from.stringValue
//        let stanzaID = Self.roomStanzaID(in: message, roomJID: room.jid)
        let stanzaID = Self.roomStanzaID(in: message, roomJID: roomBareJID) ?? archiveID
        let id =
            outgoing
            ? (message.originId ?? message.id ?? stanzaID ?? UUID().uuidString)
            : (stanzaID ?? message.originId ?? message.id ?? UUID().uuidString)

        let encrypted = message.firstChild(name: "encrypted", xmlns: OMEMOModule.XMLNS) != nil
            || message.firstChild(name: "encrypted", xmlns: LumaOMEMO2Module.XMLNS) != nil
        let realSender: BareJID?
        if outgoing {
            realSender = client.userBareJid
        } else if let disclosed = Self.originalSenderJID(in: message) {
            realSender = disclosed
            roomRealJIDByNickname[roomJID, default: [:]][nickname] = disclosed
        } else if let disclosed = XMucUserElement.extract(from: message)?.jid?.bareJid {
            realSender = disclosed
            roomRealJIDByNickname[roomJID, default: [:]][nickname] = disclosed
            //        } else if let disclosed = room.occupant(nickname: nickname)?.jid?.bareJid {
        } else if let disclosed = room?.occupant(nickname: nickname)?.jid?.bareJid {
            realSender = disclosed
            roomRealJIDByNickname[roomJID, default: [:]][nickname] = disclosed
        } else {
            realSender = roomRealJIDByNickname[roomJID]?[nickname]
        }

        let security: ChatMessage.Security
        let fingerprint: String?
        let contentMessage: Message?
        if let realSender {
            let decryptionResult = await (
                Self.isOMEMO2Payload(message)
                    ? decodeOmemo2OffMain(
                        message,
                        from: realSender,
                        serverMsgId: stanzaID,
                        module: client.module(.omemo2)
                    )
                    : decodeOmemoOffMain(
                        message,
                        from: realSender,
                        serverMsgId: stanzaID,
                        module: client.module(.omemo)
                    )
            )
            switch decryptionResult {
            case .successMessage(let decodedMessage, let value):
                security = .omemo
                fingerprint = value
                contentMessage = decodedMessage
            case .successTransportKey(_, _):
                return
            case .failure(let error):
                switch error {
                case .notEncrypted:
                    security = .plaintext
                    fingerprint = nil
                    contentMessage = message
                case .duplicateMessage:
                    emitGroupEchoIfPossible(
                        roomJID: roomJID,
                        messageID: id,
                        stanzaID: stanzaID,
                        senderJID: senderJID
                    )
                    return
                default:
                    if outgoing {
                        // Register the room-assigned stanza-id for future
                        // replies even when this device cannot decrypt the
                        // payload. Fall through to the placeholder path: the
                        // message is part of the room's history and must not
                        // vanish from the timeline.
                        emitGroupEchoIfPossible(
                            roomJID: roomJID,
                            messageID: id,
                            stanzaID: stanzaID,
                            senderJID: senderJID
                        )
                    }
                    if message.body?.isEmpty == false {
                        security = .plaintext
                        fingerprint = nil
                        contentMessage = message
                    } else {
                        security = .decryptionFailed
                        fingerprint = nil
                        contentMessage = nil
                    }
                }
            }
        } else if encrypted {
            security = .decryptionFailed
            fingerprint = nil
            contentMessage = nil
        } else {
            security = .plaintext
            fingerprint = nil
            contentMessage = message
        }

        let payload = contentMessage ?? message
//        if let state = Self.chatTypingState(payload.chatState ?? message.chatState) {
        if !isArchived, let state = Self.chatTypingState(payload.chatState ?? message.chatState) {
            knownChatStatePeers.insert(roomJID)
            if !outgoing {
                eventHandler?(
                    .chatState(
                        ChatStateEnvelope(
                            peerJID: roomJID,
                            senderJID: senderJID,
                            senderDisplayName: nickname,
                            state: state,
                            isGroupMessage: true
                        )))
            }
        }

        if let reactions = payload.firstChild(name: "reactions", xmlns: Self.reactionsNamespace)
            ?? message.firstChild(name: "reactions", xmlns: Self.reactionsNamespace),
            let targetID = reactions.getAttribute("id"),
            !targetID.isEmpty
        {
            let reactionSender =
                outgoing
                ? client.userBareJid.stringValue
                : (realSender?.stringValue ?? senderJID)
            emitReaction(
                ReactionEnvelope(
                    peerJID: roomJID,
                    senderJID: reactionSender,
                    targetID: targetID,
                    emojis: reactions.children.compactMap { child in
                        guard child.name == "reaction" else { return nil }
                        return child.value
                    },
//                    timestamp: message.delay?.stamp ?? Date(),
                    timestamp: archivedTimestamp ?? message.delay?.stamp ?? Date(),
                    isOutgoing: outgoing,
                    isGroupMessage: true
                ),
//                isArchived: false
                isArchived: isArchived
            )
            return
        }

        let rawBody =
            contentMessage?.body
            ?? (security == .decryptionFailed ? "Не удалось расшифровать групповое сообщение" : nil)
        guard let rawBody, !rawBody.isEmpty else { return }
        let reply =
            payload.firstChild(name: "reply", xmlns: Self.replyNamespace)
            ?? message.firstChild(name: "reply", xmlns: Self.replyNamespace)
        let replyFallback =
            payload.children.first { child in
                child.name == "fallback"
                    && child.xmlns == Self.fallbackNamespace
                    && child.getAttribute("for") == Self.replyNamespace
            }
            ?? message.children.first { child in
                child.name == "fallback"
                    && child.xmlns == Self.fallbackNamespace
                    && child.getAttribute("for") == Self.replyNamespace
            }
        let fallbackBody = replyFallback?.findChild(name: "body")
        let parsedReply = MessageReplyFallback.parse(
            body: rawBody,
            fallbackStart: fallbackBody?.getAttribute("start").flatMap(Int.init),
            fallbackEnd: fallbackBody?.getAttribute("end").flatMap(Int.init)
        )
        let visibleBody = parsedReply.body

        let isEncryptedAttachment =
            visibleBody.hasPrefix("aesgcm://")
            && visibleBody.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && URLComponents(string: visibleBody)?.scheme?.lowercased() == "aesgcm"
        let oob = payload.oob ?? message.oob
        let standardOOB = oob?.hasPrefix("https://") == true ? oob : nil
        let attachmentURL = isEncryptedAttachment ? visibleBody : standardOOB
        let transportFilename = attachmentURL.flatMap { value -> String? in
            guard let url = URL(string: value) else { return nil }
            guard var filename = url.lastPathComponent.removingPercentEncoding else { return nil }
            if filename.hasSuffix(".aesgcm") {
                filename = String(filename.dropLast(".aesgcm".count))
            }
            return filename
        }
        let inferred = transportFilename.map(MediaMetadata.infer(from:))
        let kind = inferred?.kind ?? (GeoLocation(uri: visibleBody) == nil ? .text : .location)
        let displayBody =
            attachmentURL == nil
            ? visibleBody
            : Self.displayBody(kind: kind, filename: transportFilename ?? "Вложение")
//        eventHandler?(
        emitMessage(
//            .message(
                MessageEnvelope(
                    id: id,
//                    peerJID: room.jid.stringValue,
                    peerJID: roomBareJID.stringValue,
                    senderJID: senderJID,
                    body: displayBody,
//                    timestamp: message.delay?.stamp ?? Date(),
                    timestamp: archivedTimestamp ?? message.delay?.stamp ?? Date(),
                    isOutgoing: outgoing,
                    security: security,
                    kind: kind,
                    remoteAttachmentURL: attachmentURL,
                    localFilename: transportFilename,
                    mimeType: inferred?.mimeType,
                    duration: inferred?.duration,
                    byteCount: nil,
                    fingerprint: fingerprint,
                    correctionTargetID: payload.lastMessageCorrectionId
                        ?? message.lastMessageCorrectionId,
                    replyToID: reply?.getAttribute("id"),
                    replyToJID: reply?.getAttribute("to"),
                    replyPreview: parsedReply.preview,
                    originID: message.originId,
                    stanzaID: stanzaID,
                    senderDisplayName: nickname,
                    isGroupMessage: true,
                    //                    isArchived: false
                    //                )))
                    isArchived: isArchived
                ), isArchived: isArchived)
    }

    private func observe(room: RoomProtocol) {
        let roomJID = room.jid.stringValue.lowercased()
        guard observedRoomJIDs.insert(roomJID).inserted else { return }

        room.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak room] state in
                guard let room else { return }
                self?.eventHandler?(
                    .roomState(
                        RoomStateEnvelope(
                            roomJID: roomJID,
                            nickname: room.nickname,
                            joined: state == .joined,
                            occupantCount: 0
                        )))
            }
            .store(in: &cancellables)

        room.occupantsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak room] occupants in
                guard let self, let room else { return }
                self.roomOccupantsByJID[roomJID] = occupants
                var knownAuthors = self.roomRealJIDByNickname[roomJID] ?? [:]
                for occupant in occupants {
                    if let realJID = occupant.jid?.bareJid {
                        knownAuthors[occupant.nickname] = realJID
                    }
                }
                self.roomRealJIDByNickname[roomJID] = knownAuthors
                self.eventHandler?(
                    .roomState(
                        RoomStateEnvelope(
                            roomJID: roomJID,
                            nickname: room.nickname,
                            joined: room.state == .joined,
                            occupantCount: occupants.count
                        )))
            }
            .store(in: &cancellables)
    }

    private func configureInstantRoom(_ room: RoomProtocol, using muc: MucModule) async throws {
        _ = try await configureRoomForOMEMO(
            room,
            using: muc,
            makeMembersOnly: true
        )
    }

    @discardableResult
    private func configureRoomForOMEMO(
        _ room: RoomProtocol,
        using muc: MucModule,
        makeMembersOnly: Bool
    ) async throws -> Bool {
        let roomJID = JID(room.jid)
        let roomConfig: RoomConfig = try await withCheckedThrowingContinuation { continuation in
            muc.roomConfiguration(roomJid: roomJID) { result in
                continuation.resume(with: result)
            }
        }

        var supportsNonAnonymousRooms = false

        if roomConfig.hasField(for: "muc#roomconfig_whois") {
            roomConfig.whois = .anyone
            supportsNonAnonymousRooms = true
        }

        if roomConfig.hasField(for: "muc#roomconfig_getmemberlist") {
            let current = roomConfig.getMemberList ?? []
            roomConfig.getMemberList = Array(Set(current + ["moderator", "participant"])).sorted()
        }

        if makeMembersOnly, roomConfig.hasField(for: "muc#roomconfig_membersonly") {
            roomConfig.membersOnly = true
        }

        if makeMembersOnly, roomConfig.hasField(for: "muc#roomconfig_persistentroom") {
            roomConfig.persistentRoom = true
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            muc.setRoomConfiguration(roomJid: roomJID, configuration: roomConfig) { result in
                continuation.resume(with: result)
            }
        }

        if supportsNonAnonymousRooms {
            omemoConfiguredRoomJIDs.insert(room.jid.stringValue.lowercased())
        }

        return supportsNonAnonymousRooms
    }

    private func groupOMEMORecipients(
        in room: RoomProtocol,
        using muc: MucModule,
        client: XMPPClient
    ) async throws -> [BareJID] {
        let roomJID = room.jid.stringValue.lowercased()
        try await ensureRoomIsNonAnonymous(room, using: muc, client: client)

        var occupantsByNickname = Dictionary(
            uniqueKeysWithValues: (roomOccupantsByJID[roomJID] ?? []).map {
                ($0.nickname, $0)
            }
        )
        // `receive(on:)` delivers the cached publisher value on the next main
        // queue turn. Read RoomBase synchronously as well so a send immediately
        // after joining cannot miss already-present open-room occupants.
        if let currentOccupants = (room as? RoomBase)?.occupants {
            for occupant in currentOccupants {
                occupantsByNickname[occupant.nickname] = occupant
            }
        }
        let occupants = Array(occupantsByNickname.values)
        let hiddenOccupants = occupants.filter {
            $0.nickname != room.nickname && $0.role != .none && $0.jid == nil
        }
        guard hiddenOccupants.isEmpty else {
            throw LumaXMPPError.groupEncryptionParticipantsHidden(
                hiddenOccupants.map(\.nickname).sorted()
            )
        }

        var recipients = Set(occupants.compactMap { $0.jid?.bareJid })
        var knownAuthors = roomRealJIDByNickname[roomJID] ?? [:]
        for affiliation in [MucAffiliation.member, .admin, .owner] {
            let values: [MucModule.RoomAffiliation]
            do {
                values = try await roomAffiliations(
                    in: room,
                    affiliation: affiliation,
                    using: muc
                )
            } catch {
                throw LumaXMPPError.groupEncryptionMemberListUnavailable(
                    error.localizedDescription
                )
            }
            for value in values {
                recipients.insert(value.jid.bareJid)
                if let nickname = value.nickname, !nickname.isEmpty {
                    knownAuthors[nickname] = value.jid.bareJid
                }
            }
        }
        roomRealJIDByNickname[roomJID] = knownAuthors

        // MartinOMEMO automatically adds the sender's other devices in
        // _encode(..., forSelf: true). Remove the sender from the occupant
        // set: its published device list also contains the active device and
        // would incorrectly require a Signal session with itself.
        recipients.remove(client.userBareJid)
        recipients.remove(room.jid)
        return recipients.sorted { $0.stringValue < $1.stringValue }
    }

    private func ensureRoomIsNonAnonymous(
        _ room: RoomProtocol,
        using muc: MucModule,
        client: XMPPClient
    ) async throws {
        let roomJID = room.jid.stringValue.lowercased()
        if omemoConfiguredRoomJIDs.contains(roomJID) { return }

        let info = try? await client.module(.disco).info(for: JID(room.jid))
        if info?.features.contains("muc_nonanonymous") == true {
            omemoConfiguredRoomJIDs.insert(roomJID)
            return
        }

        let ownAffiliation = room.occupant(nickname: room.nickname)?.affiliation ?? room.affiliation
        if ownAffiliation == .owner {
            let configured = try await configureRoomForOMEMO(
                room,
                using: muc,
                makeMembersOnly: false
            )
            guard configured else {
                throw LumaXMPPError.groupEncryptionConfigurationUnsupported
            }
            eventHandler?(
                .recoverableError(
                    "Комната переведена в неанонимный режим, необходимый для группового OMEMO."
                ))
            return
        }

        throw LumaXMPPError.groupEncryptionRequiresNonAnonymousRoom
    }

    private func roomAffiliations(
        in room: RoomProtocol,
        affiliation: MucAffiliation,
        using muc: MucModule
    ) async throws -> [MucModule.RoomAffiliation] {
        try await withCheckedThrowingContinuation { continuation in
            muc.getRoomAffiliations(from: room, with: affiliation) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func addReply(
        _ replyTo: ReplyReference?,
        fallback replyFallback: (prefix: String, scalarCount: Int)?,
        to message: Message
    ) {
        guard let replyTo, let replyFallback else { return }
        let reply = Element(name: "reply", xmlns: Self.replyNamespace)
        reply.setAttribute("id", value: replyTo.id)
        if let authorJID = replyTo.authorJID {
            reply.setAttribute("to", value: authorJID)
        }
        message.addChild(reply)

        let fallback = Element(name: "fallback", xmlns: Self.fallbackNamespace)
        fallback.setAttribute("for", value: Self.replyNamespace)
        let bodyRange = Element(name: "body")
        bodyRange.setAttribute("start", value: "0")
        bodyRange.setAttribute("end", value: String(replyFallback.scalarCount))
        fallback.addChild(bodyRange)
        message.addChild(fallback)
    }
    
    private func addOriginID(_ id: String, to message: Message) {
        guard message.originId == nil else { return }
        let origin = Element(name: "origin-id", xmlns: Self.stanzaIDNamespace)
        origin.setAttribute("id", value: id)
        message.addChild(origin)
    }

    private static func roomStanzaID(in message: Message, roomJID: BareJID) -> String? {
        message.children.first { child in
            guard child.name == "stanza-id", child.xmlns == Self.stanzaIDNamespace else {
                return false
            }
            guard let by = child.getAttribute("by")?.lowercased() else { return false }
            return by == roomJID.stringValue.lowercased()
        }?.getAttribute("id")
    }

    private static func accountStanzaID(in message: Message, accountJID: BareJID) -> String? {
        message.children.first { child in
            guard child.name == "stanza-id", child.xmlns == Self.stanzaIDNamespace else {
                return false
            }
            guard let by = child.getAttribute("by")?.lowercased() else { return false }
            return by == accountJID.stringValue.lowercased()
        }?.getAttribute("id")
    }

    private static func originalSenderJID(in message: Message) -> BareJID? {
        guard
            let address = message.firstChild(
                name: "addresses",
                xmlns: Self.extendedAddressingNamespace
            )?.children.first(where: { child in
                child.name == "address"
                    && child.getAttribute("type") == "ofrom"
                    && child.getAttribute("jid") != nil
            }),
            let value = address.getAttribute("jid")
        else { return nil }
        return JID(value).bareJid
    }

    private static func martinChatState(_ state: ChatTypingState) -> ChatState {
        switch state {
        case .active: return .active
        case .composing: return .composing
        case .paused: return .paused
        case .inactive: return .inactive
        case .gone: return .gone
        }
    }

    private static func chatTypingState(_ state: ChatState?) -> ChatTypingState? {
        guard let state else { return nil }
        switch state {
        case .active: return .active
        case .composing: return .composing
        case .paused: return .paused
        case .inactive: return .inactive
        case .gone: return .gone
        }
    }

    private func emitGroupEchoIfPossible(
        roomJID: String,
        messageID: String,
        stanzaID: String?,
        senderJID: String
    ) {
        guard let stanzaID, !stanzaID.isEmpty else { return }
        eventHandler?(
            .groupMessageEcho(
                roomJID: roomJID,
                messageID: messageID,
                stanzaID: stanzaID,
                senderJID: senderJID
            ))
    }

    private func emitRetraction(
        peer: BareJID,
        sender: BareJID,
        targetID: String,
        retractionID: String,
        timestamp: Date,
        outgoing: Bool,
        isArchived: Bool
    ) {
        let envelope = RetractionEnvelope(
            peerJID: peer.stringValue,
            senderJID: sender.stringValue,
            targetID: targetID,
            retractionID: retractionID,
            timestamp: timestamp,
            isOutgoing: outgoing
        )
        if isArchived {
            appendArchiveMutation(.retraction(envelope))
        } else {
            eventHandler?(.retraction(envelope))
        }
    }

    private func emitReaction(
        _ envelope: ReactionEnvelope,
        isArchived: Bool
    ) {
        if isArchived {
            appendArchiveMutation(.reaction(envelope))
        } else {
            eventHandler?(.reaction(envelope))
        }
    }

    private func emitMessage(_ envelope: MessageEnvelope, isArchived: Bool) {
        if isArchived {
            appendArchiveMutation(.message(envelope))
        } else {
            eventHandler?(.message(envelope))
        }
    }

    /// Archived mutations normally belong to the active account/MUC catch-up
    /// pass. While an interactive backward-history page is being applied, its
    /// mutations are collected in a dedicated buffer so the two flows never
    /// interleave and never steal each other's mutations.
    private func appendArchiveMutation(_ mutation: ArchiveMutation) {
        if interactiveHistoryMutations != nil {
            interactiveHistoryMutations?.append(mutation)
        } else {
            archivePassMutations.append(mutation)
        }
    }

    private func retrievePEPAvatar(for jid: String, client: XMPPClient) async -> Data? {
        do {
            let avatarModule = client.module(.pepUserAvatar)
            let info = try await avatarModule.retrieveAvatarMetadata(
                from: BareJID(jid),
                fireEvents: false
            )
            guard info.size > 0, info.size <= 2 * 1_024 * 1_024 else { return nil }
            let (_, data) = try await avatarModule.retrieveAvatar(
                from: BareJID(jid), itemId: info.id)
            return data.count <= 2 * 1_024 * 1_024 ? data : nil
        } catch {
            return nil
        }
    }

    private func retrieveLegacyAvatar(for jid: String, client: XMPPClient) async -> Data? {
        do {
            let card = try await client.module(.vcardTemp).retrieveVCard(from: JID(jid))
            guard let encoded = card.photos.first(where: { $0.binval != nil })?.binval,
                let data = Data(base64Encoded: encoded),
                data.count <= 2 * 1_024 * 1_024
            else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func displayBody(kind: ChatMessage.Kind, filename: String) -> String {
        switch kind {
        case .attachment:
            return filename
        case .photo:
            return "Фото"
        case .video:
            return "Видео"
        case .audio:
            return filename
        case .voice:
            return "Голосовое сообщение"
        case .videoNote:
            return "Видеосообщение"
        case .location, .text, .system:
            return filename
        }
    }

    private func encrypt(_ message: Message, using omemo: OMEMOModule) async throws -> (
        message: Message, fingerprint: String?
    ) {
        try await withCheckedThrowingContinuation { continuation in
            omemo.encode(message: message, withStoreHint: true) { result in
                switch result {
                case .successMessage(let message, let fingerprint):
                    continuation.resume(returning: (message, fingerprint))
                case .failure(let error):
                    continuation.resume(
                        throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                }
            }
        }
    }

    /// OMEMO 2 twin of `encrypt(_:using:)`.
    private func encrypt(
        _ message: Message,
        using omemo: LumaOMEMO2Module
    ) async throws -> (message: Message, fingerprint: String?) {
        try await withCheckedThrowingContinuation { continuation in
            omemo.encode(message: message, withStoreHint: true) { result in
                switch result {
                case .successMessage(let message, let fingerprint):
                    continuation.resume(returning: (message, fingerprint))
                case .failure(let error):
                    continuation.resume(
                        throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                }
            }
        }
    }

    /// OMEMO 2 twin of `encrypt(_:forGroupRecipients:using:)`. Keys are
    /// nested in `<keys jid>` groups, so the per-device validation walks the
    /// header's groups.
    private func encrypt(
        _ message: Message,
        forGroupRecipients recipients: [BareJID],
        using omemo: LumaOMEMO2Module,
        roomJID: BareJID
    ) async throws -> (message: Message, fingerprint: String?) {
        let fetchedAddresses: [SignalAddress] = try await withCheckedThrowingContinuation {
            continuation in
            omemo.addresses(for: recipients) { result in
                switch result {
                case .success(let addresses):
                    continuation.resume(returning: addresses)
                case .failure(let error):
                    continuation.resume(
                        throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                }
            }
        }
        let addresses = Array(Set(fetchedAddresses))

        let availableJIDs = Set(addresses.map { $0.name.lowercased() })
        let missingJIDs =
            recipients
            .map(\.stringValue)
            .filter { !availableJIDs.contains($0.lowercased()) }
        guard missingJIDs.isEmpty else {
            throw LumaXMPPError.groupOMEMODevicesUnavailable(missingJIDs.sorted())
        }

        let addressesWithoutSessions = addresses.filter {
            omemoStorage?.hasSession(for: $0) != true
        }
        guard addressesWithoutSessions.isEmpty else {
            throw LumaXMPPError.groupOMEMOSessionsUnavailable(
                addressesWithoutSessions
                    .map { "\($0.name)/\($0.deviceId)" }
                    .sorted()
            )
        }

        let encryptedMessage: (message: Message, fingerprint: String?) =
            try await withCheckedThrowingContinuation { continuation in
                omemo.encode(
                    message: message,
                    forAddresses: addresses,
                    roomJID: roomJID,
                    withStoreHint: true
                ) { result in
                    switch result {
                    case .successMessage(let message, let fingerprint):
                        continuation.resume(returning: (message, fingerprint))
                    case .failure(let error):
                        continuation.resume(
                            throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                    }
                }
            }

        var encryptedKeyCounts: [Int32: Int] = [:]
        if let encrypted = encryptedMessage.message.firstChild(
            name: "encrypted", xmlns: LumaOMEMO2Module.XMLNS
        ), let header = encrypted.findChild(name: "header") {
            var keyElements: [Element] = []
            for keysEl in header.getChildren(where: { $0.name == "keys" }) {
                keyElements.append(contentsOf: keysEl.getChildren(where: { $0.name == "key" }))
            }
            keyElements
                .compactMap { $0.getAttribute("rid").flatMap(Int32.init) }
                .forEach { encryptedKeyCounts[$0, default: 0] += 1 }
        }

        var unavailableAddresses: [String] = []
        for address in addresses {
            let availableCount = encryptedKeyCounts[address.deviceId, default: 0]
            if availableCount > 0 {
                encryptedKeyCounts[address.deviceId] = availableCount - 1
            } else {
                unavailableAddresses.append("\(address.name)/\(address.deviceId)")
            }
        }
        guard unavailableAddresses.isEmpty else {
            throw LumaXMPPError.groupOMEMOSessionsUnavailable(unavailableAddresses.sorted())
        }
        return encryptedMessage
    }

    private func encrypt(
        _ message: Message,
        forGroupRecipients recipients: [BareJID],
        using omemo: OMEMOModule
    ) async throws -> (message: Message, fingerprint: String?) {
        let fetchedAddresses: [SignalAddress] = try await withCheckedThrowingContinuation {
            continuation in
            omemo.addresses(for: recipients) { result in
                switch result {
                case .success(let addresses):
                    continuation.resume(returning: addresses)
                case .failure(let error):
                    continuation.resume(
                        throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                }
            }
        }
        let addresses = Array(Set(fetchedAddresses))

        let availableJIDs = Set(addresses.map { $0.name.lowercased() })
        let missingJIDs =
            recipients
            .map(\.stringValue)
            .filter { !availableJIDs.contains($0.lowercased()) }
        guard missingJIDs.isEmpty else {
            throw LumaXMPPError.groupOMEMODevicesUnavailable(missingJIDs.sorted())
        }

        let addressesWithoutSessions = addresses.filter {
            omemoStorage?.hasSession(for: $0) != true
        }
        guard addressesWithoutSessions.isEmpty else {
            throw LumaXMPPError.groupOMEMOSessionsUnavailable(
                addressesWithoutSessions
                    .map { "\($0.name)/\($0.deviceId)" }
                    .sorted()
            )
        }

        let encryptedMessage: (message: Message, fingerprint: String?) =
            try await withCheckedThrowingContinuation { continuation in
                omemo.encode(message: message, forAddresses: addresses, withStoreHint: true) {
                    result in
                    switch result {
                    case .successMessage(let message, let fingerprint):
                        continuation.resume(returning: (message, fingerprint))
                    case .failure(let error):
                        continuation.resume(
                            throwing: LumaXMPPError.omemoEncryptionFailed(error.rawValue))
                    }
                }
            }

        var encryptedKeyCounts: [Int32: Int] = [:]
        encryptedMessage.message
            .firstChild(name: "encrypted", xmlns: OMEMOModule.XMLNS)?
            .findChild(name: "header")?
            .children
            .filter { $0.name == "key" }
            .compactMap { $0.getAttribute("rid").flatMap(Int32.init) }
            .forEach { encryptedKeyCounts[$0, default: 0] += 1 }

        var unavailableAddresses: [String] = []
        for address in addresses {
            let availableCount = encryptedKeyCounts[address.deviceId, default: 0]
            if availableCount > 0 {
                encryptedKeyCounts[address.deviceId] = availableCount - 1
            } else {
                unavailableAddresses.append("\(address.name)/\(address.deviceId)")
            }
        }
        guard unavailableAddresses.isEmpty else {
            throw LumaXMPPError.groupOMEMOSessionsUnavailable(unavailableAddresses.sorted())
        }
        return encryptedMessage
    }
    
    /// Single Martin-specific MAM entry point. Martin 3.2.4 supports
    /// `componentJid:` and writes it to IQ `to`, which is required for MUC MAM.
    private func queryMAM(
        client: XMPPClient,
        archive: MAMArchiveKey,
        start: Date?,
        queryID: String,
        rsm: RSM.Query?,
        completion: @escaping (Result<MessageArchiveManagementModule.QueryResult, XMPPError>) -> Void
    ) {
        let componentJID: JID?
        switch archive.kind {
        case .account:
            componentJID = nil
        case .muc:
            componentJID = JID(archive.jid)
        }
        
        client.module(.mam).queryItems(
            componentJid: componentJID,
            start: start,
            queryId: queryID,
            rsm: rsm,
            completionHandler: completion
        )
    }
    
    private func allowedMAMSources(
        for archive: MAMArchiveKey,
        client: XMPPClient
    ) -> Set<String> {
        switch archive.kind {
        case .account:
            return [
                client.userBareJid.stringValue.lowercased(),
                client.userBareJid.domain.lowercased(),
            ]
        case .muc:
            return [archive.jid.lowercased()]
        }
    }

    private func startArchiveSyncIfAvailable() {
        guard let client,
            client.state == .connected(),
            !archiveSyncSuspended,
            !archiveRetrySuppressedUntilActivation,
            !client.module(.mam).availableVersions.isEmpty
        else { return }
        startArchiveSync(client: client)
    }

    private func startArchiveSync(client: XMPPClient) {
        guard !archiveSyncStarted,
            !archiveSyncCompletedForConnection,
            !archiveSyncSuspended,
            !archiveRetrySuppressedUntilActivation,
            self.client === client
        else { return }
        archiveSyncStarted = true
        if archiveSyncQueryStartedAt == nil {
            archiveSyncQueryStartedAt = Date()
        }
        archiveIsBootstrapQuery = archiveSyncCheckpoint == nil
        archiveWorkBudget = ArchiveSyncWorkBudget()
        archiveHighWatermark = nil
        archiveLastCompletedCursor = archiveSyncCheckpoint?.cursor
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false
        archivePassMutations.removeAll(keepingCapacity: true)
        archivePagination = ArchiveSyncPagination()
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = nil
        archiveActiveQueryID = nil
        archiveStanzaBuffer.removeAll(keepingCapacity: true)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        // Do NOT blanket-cancel the inbox here: an interactive backward-history
        // query may be in flight and must keep its own query-ID-scoped buffer.
        // Show the visible "Синхронизация истории…" banner only for the
        // one-page bootstrap window. Incremental catch-up continues silently so
        // a large backlog never leaves the spinner visible for the whole pass.
        if archiveIsBootstrapQuery {
            setArchiveSyncIndicator(true)
        }
        client.module(.omemo).mamSyncStarted(for: nil)
        let initialPosition = ArchiveSyncCursorPolicy.requestPosition(
            checkpoint: archiveSyncCheckpoint,
            resumeAfter: archiveResumeAfter,
            overlap: ArchiveSyncRecoveryPolicy.incrementalOverlap
        )
        queryArchive(
            client: client,
            after: archiveIsBootstrapQuery ? nil : initialPosition.after,
            retry: 0
        )
    }
    
    private func enqueueMUCCatchup(roomJID: BareJID) {
        let archive = MAMArchiveKey.muc(roomJID.stringValue)
        guard activeMUCCatchup != archive,
              !pendingMUCCatchups.contains(archive) else { return }
        pendingMUCCatchups.append(archive)
        startNextMUCCatchupIfPossible()
    }
    
    /// Keep this first version serialized with the account pass. It prevents
    /// archive mutations from different namespaces sharing the legacy batch.
    /// Patch 0007 makes live delivery archive-aware while catch-up runs.
    private func startNextMUCCatchupIfPossible() {
        guard activeMUCCatchup == nil,
              !archiveSyncStarted,
              let client,
              client.state == .connected(),
              !client.module(.mam).availableVersions.isEmpty,
              !pendingMUCCatchups.isEmpty else { return }
        
        let archive = pendingMUCCatchups.removeFirst()
        activeMUCCatchup = archive
        mucCatchupHighWatermark = nil
        mucCatchupLastCursor = mamCheckpoints[archive]?.cursor
        queryMUCArchivePage(
            archive: archive,
            after: mamCheckpoints[archive]?.cursor,
            client: client
        )
    }
    
    private func queryMUCArchivePage(
        archive: MAMArchiveKey,
        after: String?,
        client: XMPPClient
    ) {
        guard activeMUCCatchup == archive else { return }
        let queryID = UUID().uuidString
        archiveStanzaInbox.begin(
            queryID: queryID,
            allowedSources: allowedMAMSources(for: archive, client: client)
        )
        
        let checkpoint = mamCheckpoints[archive]
        let start = after == nil
        ? checkpoint?.timestamp.addingTimeInterval(-ArchiveSyncRecoveryPolicy.incrementalOverlap)
        : nil
        let rsm = checkpoint == nil
        ? RSM.Query(lastItems: archiveBootstrapMessageLimit)
        : RSM.Query(after: after, max: archivePageSize)
        
        queryMAM(
            client: client,
            archive: archive,
            start: start,
            queryID: queryID,
            rsm: rsm
        ) { [weak self, weak client] result in
            DispatchQueue.main.async {
                guard let self, let client,
                      self.activeMUCCatchup == archive else { return }
                let page = self.archiveStanzaInbox.take(queryID: queryID)
                guard !page.overflowed, !page.rejectedSource else {
                    self.finishMUCCatchup(archive: archive, succeeded: false)
                    return
                }
                Task { @MainActor [weak self, weak client] in
                    guard let self, let client,
                          self.activeMUCCatchup == archive else { return }
                    for stanza in page.stanzas {
                        self.mucCatchupHighWatermark = max(
                            self.mucCatchupHighWatermark ?? .distantPast,
                            stanza.timestamp
                        )
                        guard stanza.message.type == .groupchat,
                              let roomJID = stanza.message.from?.bareJid else { continue }
                        await self.handle(
                            groupMessage: stanza.message,
                            archivedRoomJID: roomJID,
                            archivedTimestamp: stanza.timestamp,
                            archiveID: stanza.archiveID,
                            isArchived: true
                        )
                    }

                    switch result {
                    case .failure:
                        // Same recovery principle as account MAM: a retained
                        // local UID may have expired on the server. Retry once
                        // from the durable timestamp overlap, never loop
                        // cursor<->time.
                        if self.mamCheckpoints[archive]?.cursor != nil,
                           self.mucCursorFallbackArchives.insert(archive).inserted,
                           let old = self.mamCheckpoints[archive] {
                            self.mamCheckpoints[archive] = MAMArchiveCheckpoint(
                                timestamp: old.timestamp,
                                cursor: nil
                            )
                            self.queryMUCArchivePage(
                                archive: archive,
                                after: nil,
                                client: client
                            )
                        } else {
                            self.finishMUCCatchup(archive: archive, succeeded: false)
                        }
                    case .success(let response):
                        self.mucCatchupLastCursor =
                            response.rsm?.last ?? self.mucCatchupLastCursor
                        if !response.complete, let next = response.rsm?.last, next != after {
                            self.queryMUCArchivePage(archive: archive, after: next, client: client)
                        } else {
                            self.finishMUCCatchup(archive: archive, succeeded: true)
                        }
                    }
                }
            }
        }
    }
    
    private func finishMUCCatchup(archive: MAMArchiveKey, succeeded: Bool) {
        defer {
            activeMUCCatchup = nil
            mucCatchupHighWatermark = nil
            mucCatchupLastCursor = nil
            Task { @MainActor [weak self] in
                await self?.replayDelayedLive(for: archive)
            }
            startNextMUCCatchupIfPossible()
        }
        // MUC catch-up decodes into archivePassMutations just like the account
        // pass. Publish them once the room catch-up settles, otherwise group
        // history fetched via MAM is decoded and then silently dropped.
        if succeeded, !archivePassMutations.isEmpty {
            let mutations = archivePassMutations
            archivePassMutations.removeAll(keepingCapacity: true)
            eventHandler?(.archiveBatch(mutations))
        } else {
            archivePassMutations.removeAll(keepingCapacity: true)
        }
        guard succeeded else { return }
        let checkpoint = MAMArchiveCheckpoint(
            timestamp: max(mucCatchupHighWatermark ?? .distantPast, Date()),
            cursor: mucCatchupLastCursor
        )
        mamCheckpoints[archive] = checkpoint
        mucCursorFallbackArchives.remove(archive)
        eventHandler?(.mucArchiveSyncCompleted(archive: archive, checkpoint: checkpoint))
    }

    private func queryArchive(client: XMPPClient, after: String?, retry: Int) {
        guard archiveSyncStarted,
            self.client === client,
            client.state == .connected()
        else {
            if archiveSyncStarted, self.client === client {
                finishArchiveSync(client: client, succeeded: false)
            } else {
                setArchiveSyncIndicator(false)
            }
            return
        }
        let queryID = UUID().uuidString
        archiveActiveQueryID = queryID
        archiveStanzaBuffer.removeAll(keepingCapacity: true)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        let accountArchive = MAMArchiveKey.account(client.userBareJid.stringValue)
        archiveStanzaInbox.begin(
            queryID: queryID,
//            allowedSources: [
//                client.userBareJid.stringValue,
//                client.userBareJid.domain,
//            ]
            allowedSources: allowedMAMSources(for: accountArchive, client: client)
        )
        scheduleArchiveQueryTimeout(client: client, queryID: queryID)
        let start =
            archiveIsBootstrapQuery
            ? nil
            : (after == nil
                ? archiveSyncCheckpoint?.timestamp.addingTimeInterval(
                    -ArchiveSyncRecoveryPolicy.incrementalOverlap
                ) : nil)
        let resultSet =
            archiveIsBootstrapQuery
            ? RSM.Query(lastItems: archiveBootstrapMessageLimit)
            : RSM.Query(after: after, max: archivePageSize)
//        client.module(.mam).queryItems(
        queryMAM(
            client: client,
            archive: accountArchive,
            start: start,
            queryID: queryID,
            rsm: resultSet
        ) { [weak self, weak client] result in
            // XEP-0313 guarantees that the final IQ follows every result. The
            // parser-queue inbox is therefore complete before this single main
            // actor hand-off runs.
            DispatchQueue.main.async {
                guard let self,
                    let client,
                    self.archiveSyncStarted,
                    self.archiveActiveQueryID == queryID,
                    self.client === client
                else { return }
                self.archiveQueryTimeoutTask?.cancel()
                self.archiveQueryTimeoutTask = nil
                let page = self.archiveStanzaInbox.take(queryID: queryID)
                self.archiveStanzaBuffer = page.stanzas
                self.archiveBufferOverflowed = page.overflowed
                self.archiveRejectedSource = page.rejectedSource

                guard case .success = result,
                    !page.overflowed,
                    !page.rejectedSource
                else {
                    self.archiveActiveQueryID = nil
                    self.completeArchivePage(
                        result,
                        client: client,
                        requestedAfter: after,
                        retry: retry
                    )
                    return
                }

                self.scheduleArchiveApplyTimeout(client: client, queryID: queryID)
                self.archiveQueryCompletionTask?.cancel()
                self.archiveQueryCompletionTask = Task { @MainActor [weak self, weak client] in
                    guard let self, let client else { return }
                    let applied = await self.drainArchiveStanzas(queryID: queryID)
                    guard !Task.isCancelled,
                        applied,
                        self.archiveSyncStarted,
                        self.archiveActiveQueryID == queryID,
                        self.client === client
                    else { return }
                    self.archiveQueryTimeoutTask?.cancel()
                    self.archiveQueryTimeoutTask = nil
                    self.archiveQueryCompletionTask = nil
                    self.archiveActiveQueryID = nil
                    self.completeArchivePage(
                        result,
                        client: client,
                        requestedAfter: after,
                        retry: retry
                    )
                }
            }
        }
    }

    private func drainArchiveStanzas(queryID: String) async -> Bool {
        while archiveSyncStarted,
            archiveActiveQueryID == queryID,
            !Task.isCancelled
        {
            guard !archiveStanzaBuffer.isEmpty else { return true }
            let count = min(archiveApplyBatchSize, archiveStanzaBuffer.count)
            let batch = Array(archiveStanzaBuffer.prefix(count))
            archiveStanzaBuffer.removeFirst(count)

            for stanza in batch where stanza.queryID == queryID {
                if let current = archiveHighWatermark {
                    archiveHighWatermark = max(current, stanza.timestamp)
                } else {
                    archiveHighWatermark = stanza.timestamp
                }
                // handle(
                //     message: stanza.message,
                //     timestamp: stanza.timestamp,
                //     archiveID: stanza.archiveID,
                //     isArchived: true
                // )
                if stanza.message.type == .groupchat,
//                    let roomJID = stanza.message.from?.bareJid,
//                    let room = client?.module(.muc).roomManager.room(for: client!, with: roomJID)
                    let roomJID = stanza.message.from?.bareJid
                {
                    // Some servers include MUC messages in the account MAM.
                    // Route them through the same group handler instead of
                    // dropping them in the direct-message handler.
//                    handle(groupMessage: stanza.message, room: room)
                    await handle(
                        groupMessage: stanza.message,
                        archivedRoomJID: roomJID,
                        archivedTimestamp: stanza.timestamp,
                        archiveID: stanza.archiveID,
                        isArchived: true
                    )
                } else {
                    await handle(
                        message: stanza.message,
                        timestamp: stanza.timestamp,
                        archiveID: stanza.archiveID,
                        isArchived: true
                    )
                }
            }

            // Give SwiftUI, UIScrollView and AVFoundation delegate tasks a
            // chance to run after every decryption.
            await Task.yield()
            try? await Task.sleep(
                nanoseconds: ArchiveMessageBatchPolicy.interSliceDelayNanoseconds
            )
        }
        return false
    }

    private func completeArchivePage(
        _ result: Result<MessageArchiveManagementModule.QueryResult, XMPPError>,
        client: XMPPClient,
        requestedAfter after: String?,
        retry: Int
    ) {
        if archiveBufferOverflowed {
            archiveBufferOverflowed = false
            archiveStanzaBuffer.removeAll(keepingCapacity: true)
            archivePassMutations.removeAll(keepingCapacity: true)
            eventHandler?(
                .recoverableError(
                    "Сервер вернул слишком большую страницу MAM; синхронизация остановлена без потери контрольной точки."
                ))
            finishArchiveSync(client: client, succeeded: false)
            return
        }
        if archiveRejectedSource {
            archiveRejectedSource = false
            archiveStanzaBuffer.removeAll(keepingCapacity: true)
            archivePassMutations.removeAll(keepingCapacity: true)
            eventHandler?(
                .recoverableError(
                    "MAM вернул результат от неожиданного отправителя; страница отклонена."
                ))
            finishArchiveSync(client: client, succeeded: false)
            return
        }

        switch result {
        case .success(let response):
            archiveHasCompletedPage = true
            let workBudgetReached = archiveWorkBudget.recordCompletedPage()
            if archiveIsBootstrapQuery {
                // Like Monal, start from a small recent window backed by local
                // storage instead of replaying the whole account archive.
                let checkpoint = resolvedArchiveCheckpoint(
                    cursor: response.rsm?.last,
                    caughtUp: true
                )
                archiveLastCompletedCursor = checkpoint.cursor
                finishArchiveSync(
                    client: client,
                    succeeded: true,
                    checkpoint: checkpoint
                )
                return
            }
            switch archivePagination.decision(
                complete: response.complete,
                lastCursor: response.rsm?.last,
                requestedAfter: after
            ) {
            case .finished:
                let checkpoint = resolvedArchiveCheckpoint(
                    cursor: response.rsm?.last ?? after,
                    caughtUp: true
                )
                archiveLastCompletedCursor = checkpoint.cursor
                finishArchiveSync(
                    client: client,
                    succeeded: true,
                    checkpoint: checkpoint
                )
            case .next(let cursor):
                archiveResumeAfter = cursor
                let checkpoint = resolvedArchiveCheckpoint(
                    cursor: cursor,
                    caughtUp: false
                )
                archiveLastCompletedCursor = checkpoint.cursor
                if workBudgetReached {
                    guard checkpoint.advances(over: archiveSyncCheckpoint) else {
                        archivePassMutations.removeAll(keepingCapacity: true)
                        eventHandler?(
                            .recoverableError(
                                "MAM не продвинул контрольную точку; синхронизация приостановлена."
                            ))
                        finishArchiveSync(client: client, succeeded: false)
                        return
                    }

                    // Flush the accumulated mutations so the UI advances
                    // incrementally, then keep catching up in the background.
                    // The visible sync banner is only shown for the bootstrap
                    // window, so a large backlog never leaves a spinner hanging.
                    if !archivePassMutations.isEmpty {
                        let mutations = archivePassMutations
                        archivePassMutations.removeAll(keepingCapacity: true)
                        eventHandler?(.archiveBatch(mutations))
                    }
                    archiveSyncCheckpoint = checkpoint
                    archiveWorkBudget = ArchiveSyncWorkBudget()
                    scheduleArchiveNextPage(client: client, after: cursor)
                } else {
                    scheduleArchiveNextPage(client: client, after: cursor)
                }
            case .invalidCursor:
                // An incomplete page without a new UID cannot be committed
                // atomically. Drop its decoded mutations so the next attempt
                // can safely request the same page again.
                archivePassMutations.removeAll(keepingCapacity: true)
                eventHandler?(
                    .recoverableError(
                        "MAM вернул некорректный курсор; страница отклонена без изменения истории."
                    ))
                finishArchiveSync(client: client, succeeded: false)
            }
        case .failure(let error):
            if retry < ArchiveSyncRecoveryPolicy.pageRetryLimit {
                scheduleArchivePageRetry(
                    client: client,
                    after: after,
                    retry: retry + 1
                )
            } else if ArchiveSyncCursorPolicy.shouldFallbackFromStoredCursor(
                requestedAfter: after,
                checkpoint: archiveSyncCheckpoint,
                hasCompletedPage: archiveHasCompletedPage,
                fallbackAlreadyUsed: archiveCursorFallbackUsed
            ) {
                // The server may have expired the UID because of archive
                // retention. Fall back once to the legacy timestamp overlap;
                // never loop between the two strategies automatically.
                archiveCursorFallbackUsed = true
                archivePagination = ArchiveSyncPagination()
                archiveResumeAfter = nil
                archiveHighWatermark = nil
                archivePassMutations.removeAll(keepingCapacity: true)
                queryArchive(client: client, after: nil, retry: 0)
            } else {
                eventHandler?(
                    .recoverableError(
                        "MAM: \(error.localizedDescription). Продолжим после следующего открытия приложения."
                    ))
                finishArchiveSync(client: client, succeeded: false)
            }
        }
    }

    private func resolvedArchiveCheckpoint(
        cursor: String?,
        caughtUp: Bool
    ) -> ArchiveSyncCheckpoint {
        ArchiveSyncCursorPolicy.resolvedCheckpoint(
            previous: archiveSyncCheckpoint,
            cursor: cursor ?? archiveLastCompletedCursor,
            highWatermark: archiveHighWatermark,
            queryStartedAt: archiveSyncQueryStartedAt ?? Date(),
            caughtUp: caughtUp
        )
    }

    private func scheduleArchivePageRetry(
        client: XMPPClient,
        after: String?,
        retry: Int
    ) {
        archiveRetryTask?.cancel()
        archiveRetryTask = Task { @MainActor [weak self, weak client] in
            let delaySeconds = min(8, 1 << max(0, retry - 1))
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            guard !Task.isCancelled,
                let self,
                let client,
                self.archiveSyncStarted,
                self.client === client
            else { return }
            self.queryArchive(client: client, after: after, retry: retry)
        }
    }

    private func scheduleArchiveNextPage(client: XMPPClient, after: String) {
        archiveRetryTask?.cancel()
        archiveRetryTask = Task { @MainActor [weak self, weak client] in
            // A short hand-off between MAM pages lets SwiftUI render and lets
            // the archive consumer apply the previous batch. Without it a
            // large server archive can monopolize the main run loop.
            try? await Task.sleep(
                nanoseconds: ArchiveSyncRecoveryPolicy.interPageDelayNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                let client,
                self.archiveSyncStarted,
                self.client === client
            else { return }
            self.queryArchive(client: client, after: after, retry: 0)
        }
    }

    private func scheduleArchiveQueryTimeout(client: XMPPClient, queryID: String) {
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = Task { @MainActor [weak self, weak client] in
            try? await Task.sleep(
                nanoseconds: ArchiveSyncRecoveryPolicy.queryTimeoutNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                let client,
                self.archiveSyncStarted,
                self.archiveActiveQueryID == queryID,
                self.client === client
            else { return }
            self.archiveQueryCompletionTask?.cancel()
            self.archiveQueryCompletionTask = nil
            self.archiveStanzaInbox.cancel(queryID: queryID)
            self.archiveActiveQueryID = nil
            self.archiveResumeAfter = self.archiveSyncCheckpoint?.cursor
            self.archiveStanzaBuffer.removeAll(keepingCapacity: true)
            self.archiveBufferOverflowed = false
            self.archiveRejectedSource = false
            self.archivePassMutations.removeAll(keepingCapacity: true)
            self.eventHandler?(
                .recoverableError(
                    "MAM не ответил вовремя; синхронизация остановлена до следующего открытия приложения."
                ))
            self.finishArchiveSync(client: client, succeeded: false)
        }
    }

    private func scheduleArchiveApplyTimeout(client: XMPPClient, queryID: String) {
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = Task { @MainActor [weak self, weak client] in
            try? await Task.sleep(
                nanoseconds: ArchiveSyncRecoveryPolicy.pageApplyTimeoutNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                let client,
                self.archiveSyncStarted,
                self.archiveActiveQueryID == queryID,
                self.client === client
            else { return }
            self.archiveQueryCompletionTask?.cancel()
            self.archiveQueryCompletionTask = nil
            self.archiveStanzaInbox.cancel(queryID: queryID)
            self.archiveActiveQueryID = nil
            self.archiveResumeAfter = self.archiveSyncCheckpoint?.cursor
            self.archiveStanzaBuffer.removeAll(keepingCapacity: true)
            self.archiveBufferOverflowed = false
            self.archiveRejectedSource = false
            self.archivePassMutations.removeAll(keepingCapacity: true)
            self.eventHandler?(
                .recoverableError(
                    "Обработка MAM заняла слишком много времени; синхронизация приостановлена."
                ))
            self.finishArchiveSync(client: client, succeeded: false)
        }
    }

    private func finishArchiveSync(
        client: XMPPClient,
        succeeded: Bool,
        checkpoint: ArchiveSyncCheckpoint? = nil
    ) {
        guard archiveSyncStarted, self.client === client else {
            if !archiveSyncStarted {
                setArchiveSyncIndicator(false)
            }
            return
        }
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        // Do NOT blanket-cancel the inbox here: an interactive backward-history
        // query may be in flight and must keep its own query-ID-scoped buffer.
        archiveActiveQueryID = nil
        archiveStanzaBuffer.removeAll(keepingCapacity: true)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        client.module(.omemo).mamSyncFinished(for: nil)

        if succeeded, !archivePassMutations.isEmpty {
            let mutations = archivePassMutations
            archivePassMutations.removeAll(keepingCapacity: true)
            eventHandler?(.archiveBatch(mutations))
        } else {
            archivePassMutations.removeAll(keepingCapacity: true)
        }
        setArchiveSyncIndicator(false)
        archiveSyncStarted = false
        archiveIsBootstrapQuery = false
        archiveHighWatermark = nil
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false

        if succeeded {
            let resolvedCheckpoint =
                checkpoint
                ?? ArchiveSyncCheckpoint(
                    timestamp: archiveSyncQueryStartedAt ?? Date(),
                    cursor: archiveLastCompletedCursor ?? archiveSyncCheckpoint?.cursor
                )
            archiveSyncCheckpoint = resolvedCheckpoint
            archiveLastCompletedCursor = resolvedCheckpoint.cursor
            archiveSyncQueryStartedAt = nil
            archiveSyncCompletedForConnection = true
            archiveResumeAfter = nil
            archiveRetrySuppressedUntilActivation = false
            archiveAutoRetryCount = 0
            eventHandler?(.archiveSyncCompleted(resolvedCheckpoint))
            Task { @MainActor [weak self, weak client] in
                guard let self, let client else { return }
                await self.replayDelayedLive(for: .account(client.userBareJid.stringValue))
            }
            startNextMUCCatchupIfPossible()
            return
        }

        archiveSyncQueryStartedAt = nil
        archiveSyncCompletedForConnection = false
        archiveResumeAfter = archiveSyncCheckpoint?.cursor
        archiveLastCompletedCursor = archiveSyncCheckpoint?.cursor
        if archiveAutoRetryCount < ArchiveSyncRecoveryPolicy.maximumAutomaticRetries {
            // A single slow/timed-out page must not leave history unloaded
            // until the next app activation. Retry automatically a bounded
            // number of times while still connected and foregrounded.
            archiveAutoRetryCount += 1
            archiveRetrySuppressedUntilActivation = false
            scheduleArchiveSyncRetry(client: client)
        } else {
            archiveAutoRetryCount = 0
            archiveRetrySuppressedUntilActivation = true
            eventHandler?(
                .recoverableError(
                    "Синхронизация истории приостановлена. Luma продолжит после возврата в приложение."
                ))
        }
    }

    private func scheduleArchiveSyncRetry(client: XMPPClient) {
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = Task { @MainActor [weak self, weak client] in
            try? await Task.sleep(
                nanoseconds: ArchiveSyncRecoveryPolicy.retryAfterFailureDelayNanoseconds
            )
            guard !Task.isCancelled,
                let self,
                let client,
                self.client === client,
                client.state == .connected(),
                !self.archiveSyncSuspended
            else { return }
            self.archiveSyncRetryTask = nil
            self.refreshArchiveIfNeeded(client: client)
        }
    }

    private func refreshArchiveIfNeeded(client: XMPPClient) {
        guard !archiveSyncStarted,
            !archiveSyncSuspended,
            self.client === client
        else { return }
        if !archiveSyncCompletedForConnection {
            archiveRetrySuppressedUntilActivation = false
            startArchiveSync(client: client)
            return
        }
        let lastCheckpoint = archiveSyncCheckpoint?.timestamp ?? .distantPast
        guard Date().timeIntervalSince(lastCheckpoint) >= archiveForegroundRefreshInterval else {
            return
        }
        archiveSyncCompletedForConnection = false
        archiveResumeAfter = nil
        archiveSyncQueryStartedAt = nil
        startArchiveSync(client: client)
    }

    private func suspendArchiveSyncForDisconnect() {
        setArchiveSyncIndicator(false)
        finishOlderHistory(result: .failure(LumaXMPPError.notConnected))
        archiveStanzaInbox.cancel()
        guard let client else {
            archiveSyncStarted = false
//            archiveStanzaInbox.cancel()
            archiveActiveQueryID = nil
            archiveStanzaBuffer.removeAll(keepingCapacity: false)
            archiveBufferOverflowed = false
            archiveRejectedSource = false
            archivePassMutations.removeAll(keepingCapacity: false)
            return
        }
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = nil
        if archiveSyncStarted {
            archiveResumeAfter = archiveSyncCheckpoint?.cursor
            client.module(.omemo).mamSyncFinished(for: nil)
        }
        archiveStanzaInbox.cancel()
        archiveActiveQueryID = nil
        archiveSyncStarted = false
        archiveSyncCompletedForConnection = false
        archiveRetrySuppressedUntilActivation = false
        archiveSyncQueryStartedAt = nil
        archiveWorkBudget = ArchiveSyncWorkBudget()
        archiveHighWatermark = nil
        archiveLastCompletedCursor = archiveSyncCheckpoint?.cursor
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false
        archivePassMutations.removeAll(keepingCapacity: false)
        archiveIsBootstrapQuery = false
        archiveStanzaBuffer.removeAll(keepingCapacity: false)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
    }

    private func pauseArchiveSync(client: XMPPClient) {
        setArchiveSyncIndicator(false)
        // An in-flight interactive history request must not survive into the
        // background with a dangling spinner; finish it before the catch-up
        // guard below, which may early-return when no catch-up is active.
        finishOlderHistory(result: .failure(LumaXMPPError.notConnected))
        guard archiveSyncStarted, self.client === client else { return }
        archiveRetryTask?.cancel()
        archiveRetryTask = nil
        archiveQueryTimeoutTask?.cancel()
        archiveQueryTimeoutTask = nil
        archiveQueryCompletionTask?.cancel()
        archiveQueryCompletionTask = nil
        archiveSyncRetryTask?.cancel()
        archiveSyncRetryTask = nil
        archiveStanzaInbox.cancel()
        archiveResumeAfter = archiveSyncCheckpoint?.cursor
        archiveActiveQueryID = nil
        archiveSyncStarted = false
        archiveSyncCompletedForConnection = false
        archiveSyncQueryStartedAt = nil
        archivePagination = ArchiveSyncPagination()
        archiveWorkBudget = ArchiveSyncWorkBudget()
        archiveHighWatermark = nil
        archiveLastCompletedCursor = archiveSyncCheckpoint?.cursor
        archiveHasCompletedPage = false
        archiveCursorFallbackUsed = false
        archivePassMutations.removeAll(keepingCapacity: true)
        archiveIsBootstrapQuery = false
        archiveStanzaBuffer.removeAll(keepingCapacity: true)
        archiveBufferOverflowed = false
        archiveRejectedSource = false
        client.module(.omemo).mamSyncFinished(for: nil)
    }

    private func setArchiveSyncIndicator(_ visible: Bool) {
        guard archiveSyncIndicatorVisible != visible else { return }
        archiveSyncIndicatorVisible = visible
        eventHandler?(.archiveSyncing(visible))
    }

    private static var platformName: String {
        #if os(macOS)
            return "macOS"
        #else
            return "iOS/iPadOS"
        #endif
    }

    private func reasonText(_ reason: XMPPClient.State.DisconnectionReason) -> String? {
        switch reason {
        case .none:
            return nil
        case .authenticationFailure(let error):
            return SaslFailureMessage.describe(
                error: error,
                condition: saslFailureModule?.lastFailure?.condition,
                serverText: saslFailureModule?.lastFailure?.text
            )
        case .sslCertError:
            return "Сертификат сервера не прошёл проверку доверия."
        case .timeout:
            return "Сервер не ответил вовремя."
        case .noRouteToServer:
            return "Сервер недоступен по сети."
        default:
            return reason.localizedDescription
        }
    }

    private func connectionFailureMessage(for error: Error) -> String {
        if let reason = error as? XMPPClient.State.DisconnectionReason {
            return reasonText(reason) ?? error.localizedDescription
        }
        return error.localizedDescription
    }

    private func applySASLprepIfNeeded(client: XMPPClient, features: Element) {
        // Classic RFC 6120 mechanisms, SASL2 (RFC 9050) mechanisms and the
        // XEP-0440 channel-binding types are three separate stream-feature
        // elements; collect all three so the selection and the server screen
        // see the complete picture.
        let mechanisms =
            features
            .findChild(name: "mechanisms", xmlns: "urn:ietf:params:xml:ns:xmpp-sasl")?
            .children
            .filter { $0.name == "mechanism" }
            .compactMap { $0.value } ?? []
        let sasl2Mechanisms =
            features
            .findChild(name: "authentication", xmlns: "urn:xmpp:sasl:2")?
            .children
            .filter { $0.name == "mechanism" }
            .compactMap { $0.value } ?? []
        let channelBindingTypesOrdered =
            features
            .findChild(name: "sasl-channel-binding", xmlns: "urn:xmpp:sasl-cb:0")?
            .children
            .filter { $0.name == "channel-binding" }
            .compactMap { $0.getAttribute("type") } ?? []
        let channelBindingTypes = Set(channelBindingTypesOrdered)
        // Post-auth stream features (SMACK resumption) carry no SASL elements;
        // refreshing the captured state from them would wipe the screen to
        // "no methods / no channel binding". Only pre-auth features (those
        // carrying any SASL-related element) update the state.
        let hasSASLElements = !mechanisms.isEmpty
            || !sasl2Mechanisms.isEmpty
            || !channelBindingTypes.isEmpty
        if hasSASLElements {
            channelBindingStore.setAdvertisedChannelBindingTypes(channelBindingTypes)
            channelBindingStore.setSASLContext(
                mechanisms: mechanisms,
                channelBindingTypes: channelBindingTypesOrdered
            )
            advertisedSASLMechanisms = Array(Set(mechanisms + sasl2Mechanisms))
            advertisedSASL2Mechanisms = sasl2Mechanisms
        }
        // Record the mechanism the SASL layer picks for this connection: the
        // strongest password-based one the server advertises
        // (SCRAM-*-PLUS > SCRAM-SHA-512 > … > PLAIN). Keep the previous value
        // when the server sends features without mechanisms (e.g. stream
        // resumption after SMACK), so the screen does not flip to unknown.
        if let selected = SASLMechanismPreference.selected(
            among: mechanisms,
            allowsChannelBinding: channelBindingStore.canUseChannelBinding
        ) {
            negotiatedSASLMechanism = selected
        }
        guard let activePassword, !activePassword.isEmpty else { return }
        guard mechanisms.contains(where: { $0.hasPrefix("SCRAM-") }) else { return }
        guard case .password(let currentPassword, _, _) = client.connectionConfiguration.credentials,
            let prepared = try? SASLprep.prepare(activePassword),
            prepared != currentPassword
        else { return }
        client.connectionConfiguration.credentials = .password(
            password: prepared,
            authenticationName: nil,
            cache: nil
        )
    }
}

enum LumaXMPPError: LocalizedError {
    case notConnected
    case connection(String)
    case omemoInitializationFailed
    case omemoNotReady
    case omemoEncryptionFailed(Int)
    case cannotCreateChat
    case invalidRoomJID
    case emptyRoomNickname
    case roomNotJoined
    case groupEncryptionRequiresNonAnonymousRoom
    case groupEncryptionConfigurationUnsupported
    case groupEncryptionParticipantsHidden([String])
    case groupEncryptionMemberListUnavailable(String)
    case groupOMEMODevicesUnavailable([String])
    case groupOMEMOSessionsUnavailable([String])
    case fileEncryptionFailed
    case fileDecryptionFailed
    case uploadDiscoveryFailed(String)
    case uploadUnavailable(size: Int)
    case uploadSlotFailed(String)
    case uploadTransportFailed(String)
    case uploadFailed(statusCode: Int?)
    case downloadFailed
    case invalidUploadURL
    case insecureUploadURL
    case avatarUpdateFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Нет соединения с XMPP-сервером."
        case .connection(let message):
            return "Не удалось подключиться: \(message)"
        case .omemoInitializationFailed:
            return "Не удалось инициализировать хранилище OMEMO."
        case .omemoNotReady:
            return "OMEMO ещё не готов. Подождите публикации ключей на сервере."
        case .omemoEncryptionFailed(let code):
            return code == SignalError.noSession.rawValue
                ? "У контакта нет доступных OMEMO-устройств."
                : "Не удалось зашифровать сообщение OMEMO (код \(code))."
        case .cannotCreateChat:
            return "Не удалось открыть чат с этим JID."
        case .invalidRoomJID:
            return "Введите адрес комнаты в формате room@conference.example.org."
        case .emptyRoomNickname:
            return "Введите псевдоним для группового чата."
        case .roomNotJoined:
            return "Сначала подключитесь к групповой комнате."
        case .groupEncryptionRequiresNonAnonymousRoom:
            return
                "Групповое OMEMO требует неанонимную MUC-комнату. Попросите владельца включить показ реальных JID (muc#roomconfig_whois = anyone)."
        case .groupEncryptionConfigurationUnsupported:
            return
                "Сервер не предлагает настройку неанонимной MUC-комнаты, необходимую для группового OMEMO."
        case .groupEncryptionParticipantsHidden(let nicknames):
            return
                "Нельзя безопасно зашифровать сообщение: комната скрывает JID участников \(nicknames.joined(separator: ", ")). Переподключитесь после включения неанонимного режима."
        case .groupEncryptionMemberListUnavailable(let message):
            return
                "Сообщение не отправлено: сервер не отдал полный список участников комнаты для OMEMO (\(message))."
        case .groupOMEMODevicesUnavailable(let jids):
            return
                "Сообщение не отправлено: OMEMO-устройства отсутствуют у \(jids.joined(separator: ", "))."
        case .groupOMEMOSessionsUnavailable(let devices):
            return
                "Сообщение не отправлено: не удалось создать OMEMO-сессию для \(devices.joined(separator: ", "))."
        case .fileEncryptionFailed:
            return "Не удалось зашифровать вложение."
        case .fileDecryptionFailed:
            return "Не удалось расшифровать вложение."
        case .uploadDiscoveryFailed(let message):
            return "Не удалось найти XEP-0363 HTTP Upload на сервере: \(message)"
        case .uploadUnavailable(let size):
            return
                "Сервер не предлагает HTTP Upload для файла размером \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))."
        case .uploadSlotFailed(let message):
            return "Prosody не выдал слот для загрузки: \(message)"
        case .uploadTransportFailed(let message):
            return "Не удалось отправить файл в HTTP Upload: \(message)"
        case .uploadFailed(let statusCode):
            if let statusCode {
                return "HTTP Upload отклонил файл (HTTP \(statusCode))."
            }
            return "HTTP Upload вернул некорректный ответ."
        case .downloadFailed:
            return "Не удалось скачать вложение."
        case .invalidUploadURL:
            return "Получена некорректная ссылка на вложение."
        case .insecureUploadURL:
            return "Сервер предложил небезопасный HTTP Upload URL. Требуется HTTPS."
        case .avatarUpdateFailed(let message):
            return "Не удалось обновить аватар: \(message)"
        }
    }
}
