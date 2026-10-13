import AVFoundation
import Foundation
import Martin
import WebRTC

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Owns one active 1:1 Jingle RTP session and bridges Martin to WebRTC.
/// Incoming calls are available while the XMPP connection is alive; production
/// wake-up for a terminated iOS app still requires VoIP push infrastructure.
final class LumaCallEngine: NSObject, @unchecked Sendable {
    var snapshotHandler: (@MainActor (CallSnapshot?) -> Void)?
    var historyHandler: (@MainActor (CallHistoryEntry) -> Void)?
    var errorHandler: (@MainActor (String) -> Void)?

    private let queue = DispatchQueue(label: "app.luma.call-engine")
    private let queueKey = DispatchSpecificKey<UInt8>()
    fileprivate let peerConnectionFactory: RTCPeerConnectionFactory
    private weak var client: XMPPClient?
    private var sessions: [String: LumaJingleSession] = [:]
    private var activeCall: LumaWebRTCCall?
    private var timeoutWorkItem: DispatchWorkItem?

    override init() {
        RTCInitializeSSL()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
        queue.setSpecific(key: queueKey, value: 1)
    }

    func attach(client: XMPPClient) {
        performSync {
            self.client = client
        }
    }

    func detach() {
        queue.async {
            self.finishActiveCall(
                cause: .connectionDetached,
                sendTermination: false,
                trigger: "XMPP engine detached"
            )
            self.sessions.removeAll()
            self.client = nil
        }
    }

    func startCall(
        to peerJID: String,
        withVideo: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        queue.async {
            guard self.activeCall == nil else {
                completion(.failure(LumaCallError.callAlreadyActive))
                return
            }
            guard let client = self.client, client.state == .connected() else {
                completion(.failure(LumaCallError.notConnected))
                return
            }

            let peer = BareJID(peerJID.lowercased())
            let media: Set<CallMedia> = withVideo ? [.audio, .video] : [.audio]
            do {
                let destination = try self.destination(
                    for: peer,
                    media: media,
                    client: client
                )
                #if DEBUG
                    print(
                        "Luma Call: selected \(destination.jid.stringValue) via "
                            + (destination.usesMessageInitiation ? "JMI" : "direct Jingle")
                            + " for \(media.map(\.rawValue).sorted().joined(separator: "+"))."
                    )
                #endif
                let sid = UUID().uuidString.lowercased()
                let initiationType: JingleSessionInitiationType =
                    destination.usesMessageInitiation
                    ? .message
                    : .iq
                let session = self.makeSession(
                    context: client,
                    jid: destination.jid,
                    sid: sid,
                    role: .initiator,
                    initiationType: initiationType
                )
                let call = LumaWebRTCCall(
                    engine: self,
                    session: session,
                    peerJID: peer.stringValue,
                    direction: .outgoing,
                    media: media
                )
                self.activeCall = call
                self.publish(call)
                self.scheduleTimeout(for: call.id, after: 60, stage: "ringing")

                if destination.usesMessageInitiation {
                    Task {
                        do {
                            try await session.initiate(
                                descriptions:
                                    media
                                    .sorted { $0.rawValue < $1.rawValue }
                                    .map {
                                        Jingle.MessageInitiationAction.Description(
                                            xmlns: "urn:xmpp:jingle:apps:rtp:1",
                                            media: $0.rawValue
                                        )
                                    })
                            completion(.success(()))
                        } catch {
                            self.queue.async {
                                self.fail(call, error: error)
                            }
                            completion(.failure(error))
                        }
                    }
                } else {
                    call.preparePeerConnection { result in
                        switch result {
                        case .success:
                            call.bindSessionActions()
                            call.sendOffer { result in
                                if case .failure(let error) = result {
                                    self.fail(call, error: error)
                                }
                                completion(result)
                            }
                        case .failure(let error):
                            self.fail(call, error: error)
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func answerCall(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            guard let call = self.activeCall,
                call.direction == .incoming,
                call.phase == .ringing
            else {
                completion(.failure(LumaCallError.noIncomingCall))
                return
            }
            call.preparePeerConnection { result in
                switch result {
                case .success:
                    call.phase = .connecting
                    call.session.accept()
                    call.bindSessionActions()
                    self.scheduleTimeout(
                        for: call.id,
                        after: 90,
                        stage: "incoming negotiation"
                    )
                    self.publish(call)
                    completion(.success(()))
                case .failure(let error):
                    self.fail(call, error: error)
                    completion(.failure(error))
                }
            }
        }
    }

    func rejectCall() {
        queue.async {
            guard self.activeCall != nil else { return }
            self.finishActiveCall(
                reason: .decline,
                cause: .localRejected,
                sendTermination: true,
                trigger: "local reject button"
            )
        }
    }

    func endCall() {
        queue.async {
            self.finishActiveCall(
                reason: .success,
                cause: .localEnded,
                sendTermination: true,
                trigger: "local end button"
            )
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async {
            guard let call = self.activeCall else { return }
            call.isMuted = muted
            call.localAudioTrack?.isEnabled = !muted
            self.publish(call)
        }
    }

    func setCameraEnabled(_ enabled: Bool) {
        queue.async {
            guard let call = self.activeCall, call.media.contains(.video) else { return }
            call.isCameraEnabled = enabled
            call.localVideoTrack?.isEnabled = enabled
            self.publish(call)
        }
    }

    func setSpeakerEnabled(_ enabled: Bool) {
        queue.async {
            guard let call = self.activeCall else { return }
            do {
                try call.configureSpeaker(enabled)
                call.isSpeakerEnabled = enabled
                self.publish(call)
            } catch {
                self.report(error)
            }
        }
    }

    func switchCamera() {
        queue.async {
            self.activeCall?.switchCamera()
        }
    }

    func localVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        performSync {
            guard activeCall?.id == callID else { return nil }
            return activeCall?.localVideoTrack
        }
    }

    func remoteVideoTrack(for callID: UUID) -> RTCVideoTrack? {
        performSync {
            guard activeCall?.id == callID else { return nil }
            return activeCall?.remoteVideoTrack
        }
    }

    fileprivate func iceServers(
        for client: XMPPClient,
        completion: @escaping ([RTCIceServer]) -> Void
    ) {
        let fallback = Self.publicSTUNServers()
        guard let module = client.moduleOrNil(.externalServiceDiscovery), module.isAvailable else {
            completion(fallback)
            return
        }
        module.discover(from: nil, type: nil) { result in
            let servers: [RTCIceServer]
            switch result {
            case .success(let services):
                servers = services.compactMap { $0.rtcIceServer }
            case .failure:
                servers = []
            }
            completion(servers.isEmpty ? fallback : servers)
        }
    }

    fileprivate static func publicSTUNServers() -> [RTCIceServer] {
        [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
    }

    fileprivate func publish(_ call: LumaWebRTCCall?) {
        let snapshot = call?.snapshot
        Task { @MainActor [weak self] in
            self?.snapshotHandler?(snapshot)
        }
    }

    fileprivate func callDidConnect(_ call: LumaWebRTCCall) {
        queue.async {
            guard self.activeCall === call else { return }
            self.timeoutWorkItem?.cancel()
            call.phase = .connected
            if call.connectedAt == nil { call.connectedAt = Date() }
            self.publish(call)
        }
    }

    fileprivate func callDidLoseConnection(_ call: LumaWebRTCCall) {
        queue.async {
            guard self.activeCall === call else { return }
            self.fail(call, error: LumaCallError.connectionLost)
        }
    }

    fileprivate func callDidFail(_ call: LumaWebRTCCall, error: Error) {
        queue.async {
            guard self.activeCall === call else { return }
            self.fail(call, error: error)
        }
    }

    fileprivate func callVideoTracksDidChange(_ call: LumaWebRTCCall) {
        queue.async {
            guard self.activeCall === call else { return }
            self.publish(call)
        }
    }

    private func destination(
        for peer: BareJID,
        media: Set<CallMedia>,
        client: XMPPClient
    ) throws -> (jid: JID, usesMessageInitiation: Bool) {
        let presences = client.module(.presence).store.presences(for: peer, context: client)
        guard !presences.isEmpty else { throw LumaCallError.contactOffline }

        let capabilities = client.module(.caps)
        let candidates = presences.compactMap(\.from).filter { jid in
            guard capabilities.isFeatureSupported(JingleModule.XMLNS, by: jid),
                capabilities.isFeatureSupported(Jingle.Transport.ICEUDPTransport.XMLNS, by: jid),
                capabilities.isFeatureSupported("urn:xmpp:jingle:apps:rtp:audio", by: jid)
            else {
                return false
            }
            return !media.contains(.video)
                || capabilities.isFeatureSupported("urn:xmpp:jingle:apps:rtp:video", by: jid)
        }
        guard let directJID = candidates.first else {
            throw LumaCallError.unsupportedByContact
        }
        let jmiJID = candidates.first {
            capabilities.isFeatureSupported(JingleModule.MESSAGE_INITIATION_XMLNS, by: $0)
        }
        // A proposal addressed to the bare JID can return a bare `proceed` on
        // some server/client combinations. We would then have no safe endpoint
        // for transport-info: sending it to the bare JID produces
        // item-not-found, while waiting for a resource leaves ICE without any
        // candidates. Address JMI to one advertised full JID instead. It still
        // uses XEP-0353, but every stanza now belongs to the same resource.
        if let jmiJID {
            return (jid: jmiJID, usesMessageInitiation: true)
        }
        return (jid: directJID, usesMessageInitiation: false)
    }

    private func makeSession(
        context: Context,
        jid: JID,
        sid: String,
        role: Jingle.Content.Creator,
        initiationType: JingleSessionInitiationType
    ) -> LumaJingleSession {
        let session = LumaJingleSession(
            context: context,
            jid: jid,
            sid: sid,
            role: role,
            initiationType: initiationType
        )
        sessions[sid] = session
        return session
    }

    private func scheduleTimeout(
        for callID: UUID,
        after delay: TimeInterval,
        stage: String
    ) {
        timeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.activeCall?.id == callID else { return }
            #if DEBUG
                print("Luma Call: timeout during \(stage) after \(Int(delay)) seconds.")
            #endif
            self.fail(self.activeCall, error: LumaCallError.timedOut)
        }
        timeoutWorkItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func fail(_ call: LumaWebRTCCall?, error: Error) {
        guard call == nil || activeCall === call else { return }
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        #if DEBUG
            print("Luma Call: failure: \(text)")
        #endif
        report(error)
        let cause: CallTerminationCause
        if let callError = error as? LumaCallError, case .timedOut = callError {
            cause = .timedOut
        } else {
            cause = .failed
        }
        finishActiveCall(
            reason: .failedApplication,
            cause: cause,
            sendTermination: true,
            trigger: "failure: \(text)"
        )
    }

    private func report(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Task { @MainActor [weak self] in
            self?.errorHandler?(text)
        }
    }

    private func finishActiveCall(
        reason: JingleSessionTerminateReason = .success,
        cause: CallTerminationCause,
        sendTermination: Bool,
        trigger: String
    ) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        guard let call = activeCall else {
            publish(nil)
            return
        }
        #if DEBUG
            print(
                "Luma Call: closing sid=\(call.session.sid) "
                    + "direction=\(String(describing: call.direction)) "
                    + "phase=\(String(describing: call.phase)) "
                    + "peer=\(call.session.jid.stringValue) trigger=\(trigger)."
            )
        #endif
        let endedAt = Date()
        let outcome = CallHistoryPolicy.outcome(
            direction: call.direction,
            phase: call.phase,
            connectedAt: call.connectedAt,
            cause: cause
        )
        let historyEntry = CallHistoryEntry(
            id: "call-\(call.peerJID)-\(call.session.sid)",
            peerJID: call.peerJID,
            direction: call.direction,
            isVideo: call.media.contains(.video),
            startedAt: call.startedAt,
            endedAt: endedAt,
            duration: call.connectedAt.map { max(0, endedAt.timeIntervalSince($0)) },
            outcome: outcome
        )
        activeCall = nil
        sessions.removeValue(forKey: call.session.sid)
        if sendTermination {
            call.session.finish(reason: reason)
        } else {
            call.session.terminated()
        }
        call.closePeerConnection()
        publish(nil)
        publish(historyEntry)
    }

    private func publish(_ historyEntry: CallHistoryEntry) {
        Task { @MainActor [weak self] in
            self?.historyHandler?(historyEntry)
        }
    }

    private func performSync<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try operation()
        }
        return try queue.sync(execute: operation)
    }
}

// MARK: - Martin Jingle session manager

extension LumaCallEngine: JingleSessionManager {
    func messageInitiation(
        for context: Context,
        from jid: JID,
        action: Jingle.MessageInitiationAction
    ) throws {
        try performSync {
            switch action {
            case .propose(let id, let descriptions):
                guard activeCall == nil else {
                    context.module(.jingle).sendMessageInitiation(action: .reject(id: id), to: jid)
                    return
                }
                let media = Set(descriptions.compactMap { CallMedia(rawValue: $0.media) })
                guard media.contains(.audio) else {
                    context.module(.jingle).sendMessageInitiation(action: .reject(id: id), to: jid)
                    throw XMPPError.feature_not_implemented
                }
                let session = makeSession(
                    context: context,
                    jid: jid,
                    sid: id,
                    role: .responder,
                    initiationType: .message
                )
                let call = LumaWebRTCCall(
                    engine: self,
                    session: session,
                    peerJID: jid.bareJid.stringValue,
                    direction: .incoming,
                    media: media
                )
                activeCall = call
                publish(call)
                scheduleTimeout(for: call.id, after: 60, stage: "incoming ringing")

            case .proceed(let id):
                guard let session = sessions[id],
                    let call = activeCall,
                    call.session === session,
                    call.direction == .outgoing,
                    call.phase == .ringing,
                    session.pinPeerResource(jid)
                else {
                    #if DEBUG
                        print(
                            "Luma Jingle: ignored duplicate or foreign proceed for session \(id).")
                    #endif
                    return
                }
                call.phase = .connecting
                #if DEBUG
                    print("Luma Jingle: proceed from \(jid.stringValue) for session \(id).")
                #endif
                scheduleTimeout(
                    for: call.id,
                    after: 90,
                    stage: "outgoing negotiation"
                )
                publish(call)
                call.preparePeerConnection { result in
                    switch result {
                    case .success:
                        call.bindSessionActions()
                        call.sendOffer { result in
                            if case .failure(let error) = result {
                                self.fail(call, error: error)
                            }
                        }
                    case .failure(let error):
                        self.fail(call, error: error)
                    }
                }

            case .retract(let id):
                guard let session = sessions[id],
                    session.matchesPeerEndpoint(jid)
                else { return }
                finishActiveCall(
                    cause: .remoteCancelled,
                    sendTermination: false,
                    trigger: "remote JMI retract from \(jid.stringValue)"
                )

            case .reject(let id):
                guard let session = sessions[id],
                    let call = activeCall,
                    call.session === session,
                    session.matchesPeerEndpoint(jid)
                else { return }
                // A JMI proposal is delivered to every online resource. Once a
                // resource has proceeded, a delayed reject from a sibling must
                // not tear down the session that already owns the call.
                guard call.phase == .ringing else {
                    #if DEBUG
                        print("Luma Jingle: ignored late reject after proceed for session \(id).")
                    #endif
                    return
                }
                finishActiveCall(
                    cause: .remoteRejected,
                    sendTermination: false,
                    trigger: "remote JMI reject from \(jid.stringValue)"
                )

            case .accept(let id):
                // A carbon from another local resource means that device
                // answered the incoming proposal.
                guard jid.bareJid == context.userBareJid, sessions[id] != nil else { return }
                finishActiveCall(
                    cause: .answeredElsewhere,
                    sendTermination: false,
                    trigger: "answered on another local resource \(jid.stringValue)"
                )
            }
        }
    }

    func sessionInitiated(
        for context: Context,
        with jid: JID,
        sid: String,
        contents: [Jingle.Content],
        bundle: [String]?
    ) throws {
        try performSync {
            let media = Set(
                contents.compactMap { CallMedia(rawValue: $0.description?.media ?? "") })
            guard media.contains(.audio) else { throw XMPPError.feature_not_implemented }

            if let existing = sessions[sid] {
                guard existing.pinPeerResource(jid) else {
                    throw XMPPError.item_not_found
                }
                existing.initiated(contents: contents, bundle: bundle)
                if let call = activeCall, call.session === existing {
                    scheduleTimeout(
                        for: call.id,
                        after: 90,
                        stage: "incoming offer negotiation"
                    )
                }
                return
            }
            guard activeCall == nil else {
                throw XMPPError.resource_constraint("Другой звонок уже активен")
            }

            let session = makeSession(
                context: context,
                jid: jid,
                sid: sid,
                role: .responder,
                initiationType: .iq
            )
            session.initiated(contents: contents, bundle: bundle)
            let call = LumaWebRTCCall(
                engine: self,
                session: session,
                peerJID: jid.bareJid.stringValue,
                direction: .incoming,
                media: media
            )
            activeCall = call
            publish(call)
            scheduleTimeout(for: call.id, after: 60, stage: "incoming ringing")
        }
    }

    func sessionAccepted(
        for context: Context,
        with jid: JID,
        sid: String,
        contents: [Jingle.Content],
        bundle: [String]?
    ) throws {
        try performSync {
            guard let session = sessions[sid],
                session.pinPeerResource(jid)
            else {
                throw XMPPError.item_not_found
            }
            // JMI may initially address a bare JID. session-accept is the first
            // IQ guaranteed to identify the resource that owns this Jingle
            // session, so keep every later transport-info stanza on it.
            #if DEBUG
                let acceptedMedia = contents.map {
                    "\($0.name):\($0.description?.media ?? "unknown")"
                }.joined(separator: ",")
                print(
                    "Luma Jingle: session-accept from \(jid.stringValue) "
                        + "sid=\(sid) contents=[\(acceptedMedia)]."
                )
            #endif
            session.accepted(contents: contents, bundle: bundle)
            if let call = activeCall, call.session === session {
                call.phase = .connecting
                scheduleTimeout(
                    for: call.id,
                    after: 90,
                    stage: "ICE negotiation"
                )
                publish(call)
            }
        }
    }

    func sessionTerminated(for context: Context, with jid: JID, sid: String) throws {
        try performSync {
            guard let session = sessions[sid],
                session.matchesPeerEndpoint(jid)
            else {
                throw XMPPError.item_not_found
            }
            if activeCall?.session.sid == sid {
                finishActiveCall(
                    cause: .remoteEnded,
                    sendTermination: false,
                    trigger: "remote session-terminate from \(jid.stringValue)"
                )
            } else {
                session.terminated()
                sessions.removeValue(forKey: sid)
            }
        }
    }

    func transportInfo(
        for context: Context,
        with jid: JID,
        sid: String,
        contents: [Jingle.Content]
    ) throws {
        try performSync {
            guard let session = sessions[sid],
                session.pinPeerResource(jid)
            else {
                throw XMPPError.item_not_found
            }
            // Also learn the endpoint from an early candidate sent by the
            // selected resource. This covers clients that trickle before their
            // session-accept reaches us.
            for content in contents {
                for transport in content.transports {
                    guard let ice = transport as? Jingle.Transport.ICEUDPTransport else { continue }
                    ice.candidates.forEach { session.addCandidate($0, contentName: content.name) }
                }
            }
        }
    }

    func contentModified(
        for context: Context,
        with jid: JID,
        sid: String,
        action: Jingle.ContentAction,
        contents: [Jingle.Content],
        bundle: [String]?
    ) throws {
        try performSync {
            guard let session = sessions[sid],
                session.matchesPeerEndpoint(jid)
            else {
                throw XMPPError.item_not_found
            }
            session.contentModified(action: action, contents: contents, bundle: bundle)
        }
    }

    func sessionInfo(
        for context: Context,
        with jid: JID,
        sid: String,
        info: [Jingle.SessionInfo]
    ) throws {
        try performSync {
            guard let session = sessions[sid],
                session.matchesPeerEndpoint(jid)
            else {
                throw XMPPError.item_not_found
            }
            session.sessionInfoReceived(info: info)
        }
    }
}

// MARK: - Session action queue

private final class LumaJingleSession: JingleSession {
    enum Action {
        case contentSet(SDP)
        case contentApply(Jingle.ContentAction, SDP)
        case transportAdd(Jingle.Transport.ICEUDPTransport.Candidate, String)
        case sessionInfo([Jingle.SessionInfo])
    }

    private let lock = NSLock()
    private weak var owningContext: Context?
    private var pendingActions: [Action] = []
    private var actionHandler: ((Action) -> Void)?

    override init(
        context: Context,
        jid: JID,
        sid: String,
        role: Jingle.Content.Creator,
        initiationType: JingleSessionInitiationType
    ) {
        owningContext = context
        super.init(
            context: context,
            jid: jid,
            sid: sid,
            role: role,
            initiationType: initiationType
        )
    }

    func finish(reason: JingleSessionTerminateReason) {
        guard state != .terminated else { return }
        guard initiationType == .message, state != .accepted else {
            terminate(reason: reason)
            return
        }
        let action: Jingle.MessageInitiationAction =
            role == .initiator
            ? .retract(id: sid)
            : .reject(id: sid)
        owningContext?.module(.jingle).sendMessageInitiation(action: action, to: jid)
        terminated()
    }

    /// Pins a JMI session to the concrete endpoint that answered the call.
    /// Martin intentionally exposes `jid` as read-only; `accepted(by:)` is its
    /// supported resource-rebinding operation.
    @discardableResult
    func pinPeerResource(_ peer: JID) -> Bool {
        guard peer.bareJid == jid.bareJid else { return false }
        guard peer.resource != nil else { return true }
        if jid.resource != nil {
            return peer == jid
        }
        #if DEBUG
            print("Luma Jingle: pinned session \(sid) to resource \(peer.stringValue).")
        #endif
        accepted(by: peer)
        return true
    }

    func matchesPeerEndpoint(_ peer: JID) -> Bool {
        guard peer.bareJid == jid.bareJid else { return false }
        guard jid.resource != nil, peer.resource != nil else { return true }
        return peer == jid
    }

    func setActionHandler(_ handler: @escaping (Action) -> Void) {
        lock.lock()
        actionHandler = handler
        let actions = pendingActions
        pendingActions.removeAll()
        lock.unlock()
        actions.forEach(handler)
    }

    private func emit(_ action: Action) {
        lock.lock()
        guard let actionHandler else {
            pendingActions.append(action)
            lock.unlock()
            return
        }
        lock.unlock()
        actionHandler(action)
    }

    override func initiated(contents: [Jingle.Content], bundle: [String]?) {
        super.initiated(contents: contents, bundle: bundle)
        emit(.contentSet(SDP(contents: contents, bundle: bundle)))
    }

    override func accepted(contents: [Jingle.Content], bundle: [String]?) {
        super.accepted(contents: contents, bundle: bundle)
        emit(.contentSet(SDP(contents: contents, bundle: bundle)))
    }

    override func contentModified(
        action: Jingle.ContentAction,
        contents: [Jingle.Content],
        bundle: [String]?
    ) {
        emit(.contentApply(action, SDP(contents: contents, bundle: bundle)))
    }

    override func sessionInfoReceived(info: [Jingle.SessionInfo]) {
        emit(.sessionInfo(info))
    }

    func addCandidate(
        _ candidate: Jingle.Transport.ICEUDPTransport.Candidate,
        contentName: String
    ) {
        emit(.transportAdd(candidate, contentName))
    }
}

// MARK: - Live WebRTC call

private final class LumaWebRTCCall: NSObject, RTCPeerConnectionDelegate, @unchecked Sendable {
    let id = UUID()
    let startedAt = Date()
    unowned let engine: LumaCallEngine
    let session: LumaJingleSession
    let peerJID: String
    let direction: CallDirection
    let media: Set<CallMedia>

    var phase: CallPhase = .ringing
    var connectedAt: Date?
    var isMuted = false
    var isCameraEnabled: Bool
    var isSpeakerEnabled = false
    var localAudioTrack: RTCAudioTrack?
    var localVideoTrack: RTCVideoTrack?
    var remoteVideoTrack: RTCVideoTrack?

    private var peerConnection: RTCPeerConnection?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localVideoSource: RTCVideoSource?
    private var cameraDeviceID: String?
    private var localSDP: SDP?
    private var remoteSDP: SDP?
    private var localCandidates: [RTCIceCandidate] = []
    private var remoteCandidates: [(Jingle.Transport.ICEUDPTransport.Candidate, String)] = []
    private var initialDescriptionWasSignaled = false
    private var connectionFailureWorkItem: DispatchWorkItem?
    private var isPreparingPeerConnection = false
    private var prepareCallbacks: [(Result<Void, Error>) -> Void] = []
    private let webRTCSID = String(UInt64.random(in: UInt64.min...UInt64.max))

    init(
        engine: LumaCallEngine,
        session: LumaJingleSession,
        peerJID: String,
        direction: CallDirection,
        media: Set<CallMedia>
    ) {
        self.engine = engine
        self.session = session
        self.peerJID = peerJID
        self.direction = direction
        self.media = media
        self.isCameraEnabled = media.contains(.video)
        self.isSpeakerEnabled = media.contains(.video)
        super.init()
    }

    var snapshot: CallSnapshot {
        CallSnapshot(
            id: id,
            peerJID: peerJID,
            direction: direction,
            media: media,
            phase: phase,
            connectedAt: connectedAt,
            isMuted: isMuted,
            isCameraEnabled: isCameraEnabled,
            isSpeakerEnabled: isSpeakerEnabled,
            hasLocalVideo: localVideoTrack != nil,
            hasRemoteVideo: remoteVideoTrack != nil
        )
    }

    func preparePeerConnection(completion: @escaping (Result<Void, Error>) -> Void) {
        if peerConnection != nil {
            completion(.success(()))
            return
        }
        prepareCallbacks.append(completion)
        guard !isPreparingPeerConnection else { return }
        isPreparingPeerConnection = true
        guard let client = engine.performAttachedClient() else {
            completePreparation(.failure(LumaCallError.notConnected))
            return
        }
        engine.iceServers(for: client) { [weak self] servers in
            guard let self else { return }
            self.engine.performOnQueue {
                do {
                    try self.createPeerConnection(iceServers: servers)
                    self.completePreparation(.success(()))
                } catch {
                    self.completePreparation(.failure(error))
                }
            }
        }
    }

    func bindSessionActions() {
        session.setActionHandler { [weak self] action in
            guard let self else { return }
            self.engine.performOnQueue {
                self.receive(action)
            }
        }
    }

    func sendOffer(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let peerConnection else {
            completion(.failure(LumaCallError.mediaEngineUnavailable))
            return
        }
        generateDescription(type: .offer, peerConnection: peerConnection) { result in
            switch result {
            case .success(let sdp):
                Task {
                    do {
                        try await self.session.initiate(contents: sdp.contents, bundle: sdp.bundle)
                        self.engine.performOnQueue {
                            self.initialDescriptionWasSignaled = true
                            self.sendLocalCandidates()
                            completion(.success(()))
                        }
                    } catch {
                        self.engine.performOnQueue {
                            completion(.failure(error))
                        }
                    }
                }
            case .failure(let error):
                self.engine.performOnQueue {
                    completion(.failure(error))
                }
            }
        }
    }

    func configureSpeaker(_ enabled: Bool) throws {
        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.overrideOutputAudioPort(enabled ? .speaker : .none)
            try audioSession.setActive(true)
        #else
            _ = enabled
        #endif
    }

    func switchCamera() {
        guard let capturer = videoCapturer else { return }
        let currentPosition =
            RTCCameraVideoCapturer.captureDevices()
            .first(where: { $0.uniqueID == cameraDeviceID })?.position ?? .front
        guard
            let device = RTCCameraVideoCapturer.captureDevices().first(where: {
                $0.position != currentPosition && $0.position != .unspecified
            }), let format = Self.preferredFormat(for: device)
        else { return }
        cameraDeviceID = device.uniqueID
        capturer.startCapture(with: device, format: format, fps: Self.preferredFPS(for: format))
    }

    func closePeerConnection() {
        connectionFailureWorkItem?.cancel()
        connectionFailureWorkItem = nil
        videoCapturer?.stopCapture()
        videoCapturer = nil
        localVideoSource = nil
        peerConnection?.close()
        peerConnection = nil
        localAudioTrack = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        #endif
    }

    private func createPeerConnection(iceServers: [RTCIceServer]) throws {
        // libwebrtc rejects the complete RTCConfiguration when even one ICE URL
        // is malformed or a TURN entry has incomplete credentials. Prosody
        // modules and older XEP-0215 implementations occasionally publish such
        // entries, so retry with a known STUN server and finally host candidates.
        var attempts: [(name: String, servers: [RTCIceServer])] = []
        if !iceServers.isEmpty {
            attempts.append(("XEP-0215", iceServers))
        }
        attempts.append(("public STUN", LumaCallEngine.publicSTUNServers()))
        attempts.append(("host candidates", []))

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        var createdPeerConnection: RTCPeerConnection?
        for (index, attempt) in attempts.enumerated() {
            let configuration = RTCConfiguration()
            configuration.iceServers = attempt.servers
            configuration.sdpSemantics = .unifiedPlan
            configuration.bundlePolicy = .maxCompat
            configuration.rtcpMuxPolicy = .require
            configuration.iceCandidatePoolSize = 0

            if let candidate = engine.peerConnectionFactory.peerConnection(
                with: configuration,
                constraints: constraints,
                delegate: self
            ) {
                createdPeerConnection = candidate
                #if DEBUG
                    if index > 0 {
                        print("Luma WebRTC: RTCConfiguration recovered with \(attempt.name).")
                    }
                #endif
                break
            }
            #if DEBUG
                print(
                    "Luma WebRTC: RTCConfiguration rejected "
                        + "\(attempt.name) (\(attempt.servers.count) ICE server(s))."
                )
            #endif
        }

        guard let peerConnection = createdPeerConnection else {
            throw LumaCallError.mediaEngineUnavailable
        }
        self.peerConnection = peerConnection

        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            let audioOptions: AVAudioSession.CategoryOptions = [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
            ]
            try audioSession.setCategory(
                .playAndRecord,
                mode: media.contains(.video) ? .videoChat : .voiceChat,
                options: audioOptions
            )
            try audioSession.setActive(true)
            if media.contains(.video) {
                try audioSession.overrideOutputAudioPort(.speaker)
            }
        #endif

        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let audioSource = engine.peerConnectionFactory.audioSource(with: audioConstraints)
        let audioTrack = engine.peerConnectionFactory.audioTrack(
            with: audioSource,
            trackId: "luma-audio-\(id.uuidString)"
        )
        localAudioTrack = audioTrack
        peerConnection.add(audioTrack, streamIds: ["luma-stream"])

        if media.contains(.video) {
            let source = engine.peerConnectionFactory.videoSource()
            localVideoSource = source
            let track = engine.peerConnectionFactory.videoTrack(
                with: source,
                trackId: "luma-video-\(id.uuidString)"
            )
            localVideoTrack = track
            peerConnection.add(track, streamIds: ["luma-stream"])
            let capturer = RTCCameraVideoCapturer(delegate: source)
            videoCapturer = capturer
            if let device = Self.preferredCamera(), let format = Self.preferredFormat(for: device) {
                cameraDeviceID = device.uniqueID
                capturer.startCapture(
                    with: device,
                    format: format,
                    fps: Self.preferredFPS(for: format)
                )
            }
        }
        engine.callVideoTracksDidChange(self)
    }

    private func completePreparation(_ result: Result<Void, Error>) {
        isPreparingPeerConnection = false
        let callbacks = prepareCallbacks
        prepareCallbacks.removeAll()
        callbacks.forEach { $0(result) }
    }

    private func receive(_ action: LumaJingleSession.Action) {
        guard let peerConnection else { return }
        switch action {
        case .transportAdd(let candidate, let contentName):
            guard remoteSDP != nil else {
                remoteCandidates.append((candidate, contentName))
                return
            }
            addRemoteCandidate(candidate, contentName: contentName, to: peerConnection)

        case .contentSet(let sdp):
            applyRemoteSDP(sdp, to: peerConnection)

        case .contentApply(let action, let diff):
            guard let remoteSDP else { return }
            applyRemoteSDP(remoteSDP.applyDiff(action: action, diff: diff), to: peerConnection)

        case .sessionInfo:
            break
        }
    }

    private func applyRemoteSDP(_ sdp: SDP, to peerConnection: RTCPeerConnection) {
        let normalizedSDP: SDP
        do {
            normalizedSDP = try normalizeInitialRemoteAnswer(sdp)
        } catch {
            engine.callDidFail(self, error: error)
            return
        }
        let type: RTCSdpType = direction == .incoming ? .offer : .answer
        let text = normalizedSDP.toString(
            withSid: webRTCSID,
            localRole: session.role,
            direction: .incoming
        )
        peerConnection.setRemoteDescription(
            RTCSessionDescription(type: type, sdp: text)
        ) { [weak self] error in
            guard let self else { return }
            self.engine.performOnQueue {
                if let error {
                    #if DEBUG
                        print(
                            "Luma WebRTC: setRemoteDescription failed: \(error.localizedDescription)"
                        )
                    #endif
                    self.engine.callDidFail(self, error: error)
                    return
                }
                self.remoteSDP = normalizedSDP
                let candidates = self.remoteCandidates
                self.remoteCandidates.removeAll()
                candidates.forEach {
                    self.addRemoteCandidate($0.0, contentName: $0.1, to: peerConnection)
                }
                // For an outgoing call session-initiate may already be
                // acknowledged. Flush only now, after session-accept supplied
                // both the answer and the exact full JID of its owner.
                self.sendLocalCandidates()
                if peerConnection.signalingState == .haveRemoteOffer {
                    self.generateDescription(type: .answer, peerConnection: peerConnection) {
                        result in
                        switch result {
                        case .success(let local):
                            Task {
                                do {
                                    try await self.session.accept(
                                        contents: local.contents,
                                        bundle: local.bundle
                                    )
                                    self.engine.performOnQueue {
                                        self.initialDescriptionWasSignaled = true
                                        self.sendLocalCandidates()
                                    }
                                } catch {
                                    self.engine.callDidFail(self, error: error)
                                }
                            }
                        case .failure(let error):
                            self.engine.callDidFail(self, error: error)
                        }
                    }
                }
            }
        }
    }

    private func generateDescription(
        type: RTCSdpType,
        peerConnection: RTCPeerConnection,
        completion: @escaping (Result<SDP, Error>) -> Void
    ) {
        let mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let handler: (RTCSessionDescription?, Error?) -> Void = { [weak self] description, error in
            guard let self else { return }
            guard let description else {
                self.engine.performOnQueue {
                    completion(.failure(error ?? LumaCallError.sdpGenerationFailed))
                }
                return
            }
            peerConnection.setLocalDescription(description) { error in
                self.engine.performOnQueue {
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    // Martin 3.2.4 assumes that libwebrtc terminates SDP with
                    // CRLF. Normalize its input first, then repair the FID
                    // source metadata independently below. The latter is
                    // intentionally kept even with normalized line endings:
                    // WebRTC M150 can still expose a shortened final RTX msid.
                    let martinSDP = CallSDPNormalization.martinParseInput(
                        description.sdp
                    )
                    guard
                        let (sdp, _) = SDP.parse(
                            sdpString: martinSDP,
                            creatorProvider: self.session.contentCreator(of:),
                            localRole: self.session.role
                        )
                    else {
                        completion(.failure(LumaCallError.sdpGenerationFailed))
                        return
                    }
                    let repaired = CallSDPCompatibility.repairLocalFIDMSIDs(in: sdp)
                    let fidStatus = CallSDPCompatibility.fidGroupStatus(in: repaired.sdp)
                    guard fidStatus.inconsistent == 0 else {
                        completion(.failure(LumaCallError.incompatibleLocalDescription))
                        return
                    }
                    #if DEBUG
                        if fidStatus.total > 0 {
                            print(
                                "Luma SDP: verified \(fidStatus.total) FID group(s); "
                                    + "repaired \(repaired.repairedCount) source msid(s)."
                            )
                        }
                    #endif
                    self.localSDP = repaired.sdp
                    completion(.success(repaired.sdp))
                }
            }
        }
        if type == .offer {
            peerConnection.offer(for: mediaConstraints, completionHandler: handler)
        } else {
            peerConnection.answer(for: mediaConstraints, completionHandler: handler)
        }
    }

    private func sendLocalCandidates() {
        // setLocalDescription starts ICE before the corresponding Jingle stanza
        // is acknowledged. With JMI, session-initiate can be addressed to a
        // bare JID while only one resource accepts it. Keep candidates queued
        // until the remote SDP arrives from that concrete full JID; otherwise
        // Prosody can route transport-info to another resource, which correctly
        // responds with item-not-found for the SID.
        guard
            CallCandidateDispatchGate.canSend(
                initialDescriptionWasSignaled: initialDescriptionWasSignaled,
                hasLocalDescription: localSDP != nil,
                hasRemoteDescription: remoteSDP != nil,
                hasFullPeerJID: session.jid.resource != nil
            ), let localSDP
        else { return }
        let candidates = localCandidates
        localCandidates.removeAll()
        #if DEBUG
            if !candidates.isEmpty {
                print(
                    "Luma Jingle: sending \(candidates.count) ICE candidate(s) "
                        + "to \(session.jid.stringValue) sid=\(session.sid)."
                )
            }
        #endif
        for candidate in candidates {
            let line = candidate.sdp.hasPrefix("a=") ? candidate.sdp : "a=\(candidate.sdp)"
            guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: line),
                let contentName = candidate.sdpMid,
                let content = localSDP.contents.first(where: { $0.name == contentName }),
                let transport = content.transports.first(where: {
                    $0 is Jingle.Transport.ICEUDPTransport
                }) as? Jingle.Transport.ICEUDPTransport
            else { continue }
            _ = session.transportInfo(
                contentName: contentName,
                transport: Jingle.Transport.ICEUDPTransport(
                    pwd: transport.pwd,
                    ufrag: transport.ufrag,
                    candidates: [jingleCandidate]
                )
            )
        }
    }

    private func addRemoteCandidate(
        _ candidate: Jingle.Transport.ICEUDPTransport.Candidate,
        contentName: String,
        to peerConnection: RTCPeerConnection
    ) {
        let index = remoteSDP?.contents.firstIndex(where: { $0.name == contentName }) ?? 0
        let candidateSDP = CallSDPOrdering.webRTCCandidateLine(candidate.toSDP())
        peerConnection.add(
            RTCIceCandidate(
                sdp: candidateSDP,
                sdpMLineIndex: Int32(index),
                sdpMid: contentName
            ),
            completionHandler: { error in
                #if DEBUG
                    if let error {
                        print(
                            "Luma WebRTC: remote ICE candidate rejected: \(error.localizedDescription)"
                        )
                    }
                #endif
            }
        )
    }

    private func normalizeInitialRemoteAnswer(_ sdp: SDP) throws -> SDP {
        guard direction == .outgoing, remoteSDP == nil, let localSDP else {
            return sdp
        }

        let expectedNames = localSDP.contents.map(\.name)
        let receivedNames = sdp.contents.map(\.name)
        guard
            let indices = CallSDPOrdering.answerIndices(
                localOrder: expectedNames,
                remoteOrder: receivedNames
            )
        else {
            throw LumaCallError.incompatibleRemoteDescription
        }
        let normalizedBundle: [String]?
        if let bundle = sdp.bundle {
            let bundleNames = Set(bundle)
            guard bundleNames.count == bundle.count,
                bundleNames.isSubset(of: Set(receivedNames))
            else {
                throw LumaCallError.incompatibleRemoteDescription
            }
            normalizedBundle = expectedNames.filter { bundleNames.contains($0) }
        } else {
            normalizedBundle = nil
        }
        guard indices != Array(sdp.contents.indices) || normalizedBundle != sdp.bundle else {
            return sdp
        }

        let orderedContents = indices.map { sdp.contents[$0] }
        #if DEBUG
            print("Luma WebRTC: reordered session-accept contents to match the local offer.")
        #endif
        return SDP(contents: orderedContents, bundle: normalizedBundle)
    }

    private func cancelScheduledConnectionFailure() {
        connectionFailureWorkItem?.cancel()
        connectionFailureWorkItem = nil
    }

    private func scheduleConnectionFailure(after delay: TimeInterval) {
        connectionFailureWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.connectionFailureWorkItem = nil
            self.engine.callDidLoseConnection(self)
        }
        connectionFailureWorkItem = item
        engine.performOnQueue(after: delay, execute: item)
    }

    private static func preferredCamera() -> AVCaptureDevice? {
        RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front })
            ?? RTCCameraVideoCapturer.captureDevices().first
    }

    private static func preferredFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        RTCCameraVideoCapturer.supportedFormats(for: device).min { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let leftDistance = abs(Int(left.width) - 1_280) + abs(Int(left.height) - 720)
            let rightDistance = abs(Int(right.width) - 1_280) + abs(Int(right.height) - 720)
            return leftDistance < rightDistance
        }
    }

    private static func preferredFPS(for format: AVCaptureDevice.Format) -> Int {
        let maximum = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        return max(15, min(30, Int(maximum.rounded())))
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
    ) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let track = stream.videoTracks.first else { return }
        engine.performOnQueue {
            self.remoteVideoTrack = track
            self.engine.callVideoTracksDidChange(self)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
    ) {
        engine.performOnQueue {
            #if DEBUG
                print("Luma WebRTC: ICE state changed to \(String(describing: newState)).")
            #endif
            switch newState {
            case .connected, .completed:
                self.cancelScheduledConnectionFailure()
                self.engine.callDidConnect(self)
            case .checking:
                self.cancelScheduledConnectionFailure()
            case .disconnected:
                self.scheduleConnectionFailure(after: 12)
            case .failed:
                // A late TURN or video-component candidate can still move ICE
                // back to checking. Keep the call alive during trickle ICE.
                self.scheduleConnectionFailure(after: 8)
            case .closed:
                self.cancelScheduledConnectionFailure()
                self.engine.callDidLoseConnection(self)
            default:
                break
            }
        }
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
    ) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate)
    {
        engine.performOnQueue {
            self.localCandidates.append(candidate)
            self.sendLocalCandidates()
        }
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
    ) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        engine.performOnQueue {
            self.remoteVideoTrack = track
            self.engine.callVideoTracksDidChange(self)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver)
    {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        engine.performOnQueue {
            guard self.remoteVideoTrack === track else { return }
            self.remoteVideoTrack = nil
            self.engine.callVideoTracksDidChange(self)
        }
    }
}

// MARK: - Queue helpers kept fileprivate for the live call object

extension LumaCallEngine {
    fileprivate func performOnQueue(_ action: @escaping () -> Void) {
        queue.async(execute: action)
    }

    fileprivate func performOnQueue(after delay: TimeInterval, execute item: DispatchWorkItem) {
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    fileprivate func performAttachedClient() -> XMPPClient? {
        performSync { client }
    }
}

extension ExternalServiceDiscoveryModule.Service {
    fileprivate var rtcIceServer: RTCIceServer? {
        let normalizedType = type.lowercased()
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["stun", "stuns", "turn", "turns"].contains(normalizedType) else { return nil }
        guard !normalizedHost.isEmpty,
            normalizedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            !normalizedHost.contains("/"),
            !normalizedHost.contains("?"),
            !normalizedHost.contains("#")
        else { return nil }
        guard !normalizedType.hasSuffix("s") || transport == nil || transport == .tcp else {
            return nil
        }
        if normalizedType.hasPrefix("turn") {
            guard let username, !username.isEmpty,
                let password, !password.isEmpty
            else { return nil }
        }
        if let expires, expires <= Date() { return nil }

        let escapedHost =
            normalizedHost.contains(":") && !normalizedHost.hasPrefix("[")
            ? "[\(normalizedHost)]"
            : normalizedHost
        var url = "\(normalizedType):\(escapedHost)"
        if let port { url += ":\(port)" }
        // RFC 7064 STUN URLs do not have a transport query. The query belongs
        // to TURN URLs; appending it to STUN makes newer libwebrtc reject the
        // entire RTCConfiguration.
        if normalizedType.hasPrefix("turn"), let transport {
            url += "?transport=\(transport.rawValue)"
        }
        return RTCIceServer(
            urlStrings: [url],
            username: normalizedType.hasPrefix("turn") ? username : nil,
            credential: normalizedType.hasPrefix("turn") ? password : nil,
            tlsCertPolicy: .secure
        )
    }
}

enum CallSDPOrdering {
    static func answerIndices(localOrder: [String], remoteOrder: [String]) -> [Int]? {
        guard localOrder.count == remoteOrder.count,
            Set(localOrder).count == localOrder.count,
            Set(remoteOrder).count == remoteOrder.count,
            Set(localOrder) == Set(remoteOrder)
        else { return nil }

        let remoteIndices = Dictionary(
            uniqueKeysWithValues: remoteOrder.enumerated().map { ($0.element, $0.offset) }
        )
        return localOrder.compactMap { remoteIndices[$0] }
    }

    static func webRTCCandidateLine(_ jingleSDP: String) -> String {
        jingleSDP.hasPrefix("a=") ? String(jingleSDP.dropFirst(2)) : jingleSDP
    }
}

enum CallSDPNormalization {
    static func martinParseInput(_ webRTCSDP: String) -> String {
        let lfNormalized =
            webRTCSDP
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines = lfNormalized.components(separatedBy: "\n")

        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

enum CallSDPCompatibility {
    struct SourceGroup: Equatable {
        let semantics: String
        let sources: [String]
    }

    /// Every SSRC in an FID group represents the same media track (the later
    /// sources carry retransmissions), so their msid values must be identical.
    /// Prefer the longest value when a converter shortened one at the end; for
    /// equal lengths this naturally keeps the primary source's value.
    static func canonicalFIDMSIDs(
        groups: [SourceGroup],
        msids: [String: String]
    ) -> [String: String] {
        var result = msids
        for group in groups where group.semantics.uppercased() == "FID" {
            guard group.sources.count >= 2 else { continue }
            let candidates = group.sources.compactMap { result[$0] }
            guard let canonical = candidates.max(by: { $0.count < $1.count }) else {
                continue
            }
            group.sources.forEach { result[$0] = canonical }
        }
        return result
    }

    static func repairLocalFIDMSIDs(in sdp: SDP) -> (sdp: SDP, repairedCount: Int) {
        var repairedCount = 0
        let contents = sdp.contents.map { content -> Jingle.Content in
            guard let description = content.description as? Jingle.RTP.Description else {
                return content
            }

            var currentMSIDs: [String: String] = [:]
            for source in description.ssrcs {
                guard
                    let value = source.parameters.first(where: {
                        $0.key.lowercased() == "msid"
                    })?.value, !value.isEmpty
                else { continue }
                currentMSIDs[source.ssrc] = value
            }
            let desiredMSIDs = canonicalFIDMSIDs(
                groups: description.ssrcGroups.map {
                    SourceGroup(semantics: $0.semantics, sources: $0.sources)
                },
                msids: currentMSIDs
            )

            var changed = false
            let sources = description.ssrcs.map { source -> Jingle.RTP.Description.SSRC in
                guard let desired = desiredMSIDs[source.ssrc],
                    currentMSIDs[source.ssrc] != desired
                else {
                    return source
                }
                changed = true
                repairedCount += 1
                let parameters =
                    source.parameters.filter {
                        $0.key.lowercased() != "msid"
                    } + [
                        Jingle.RTP.Description.SSRC.Parameter(
                            key: "msid",
                            value: desired
                        )
                    ]
                return Jingle.RTP.Description.SSRC(
                    ssrc: source.ssrc,
                    parameters: parameters
                )
            }
            guard changed else { return content }

            let repairedDescription = Jingle.RTP.Description(
                media: description.media,
                ssrc: description.ssrc,
                payloads: description.payloads,
                bandwidth: description.bandwidth,
                encryption: description.encryption,
                rtcpMux: description.rtcpMux,
                ssrcs: sources,
                ssrcGroups: description.ssrcGroups,
                hdrExts: description.hdrExts
            )
            return Jingle.Content(
                name: content.name,
                creator: content.creator,
                senders: content.senders,
                description: repairedDescription,
                transports: content.transports
            )
        }
        guard repairedCount > 0 else { return (sdp, 0) }
        return (SDP(contents: contents, bundle: sdp.bundle), repairedCount)
    }

    static func fidGroupStatus(in sdp: SDP) -> (total: Int, inconsistent: Int) {
        var total = 0
        var inconsistent = 0
        for content in sdp.contents {
            guard let description = content.description as? Jingle.RTP.Description else {
                continue
            }
            let msids = Dictionary(
                uniqueKeysWithValues: description.ssrcs.compactMap { source in
                    source.parameters.first(where: {
                        $0.key.lowercased() == "msid"
                    })?.value.map { (source.ssrc, $0) }
                }
            )
            for group in description.ssrcGroups where group.semantics.uppercased() == "FID" {
                total += 1
                let values = group.sources.compactMap { msids[$0] }
                if values.count != group.sources.count || Set(values).count != 1 {
                    inconsistent += 1
                }
            }
        }
        return (total, inconsistent)
    }
}

enum CallCandidateDispatchGate {
    static func canSend(
        initialDescriptionWasSignaled: Bool,
        hasLocalDescription: Bool,
        hasRemoteDescription: Bool,
        hasFullPeerJID: Bool
    ) -> Bool {
        initialDescriptionWasSignaled
            && hasLocalDescription
            && hasRemoteDescription
            && hasFullPeerJID
    }
}

private enum LumaCallError: LocalizedError {
    case callAlreadyActive
    case noIncomingCall
    case notConnected
    case contactOffline
    case unsupportedByContact
    case mediaEngineUnavailable
    case incompatibleLocalDescription
    case incompatibleRemoteDescription
    case sdpGenerationFailed
    case connectionLost
    case timedOut

    var errorDescription: String? {
        switch self {
        case .callAlreadyActive:
            return "Сначала завершите текущий звонок."
        case .noIncomingCall:
            return "Входящий звонок уже завершён."
        case .notConnected:
            return "Для звонка нужно активное XMPP-соединение."
        case .contactOffline:
            return "Контакт сейчас не в сети."
        case .unsupportedByContact:
            return "Устройства контакта не объявили поддержку совместимых Jingle-звонков."
        case .mediaEngineUnavailable:
            return
                "WebRTC не смог создать соединение даже без STUN/TURN. Очистите сборку и переустановите приложение."
        case .incompatibleLocalDescription:
            return
                "WebRTC сформировал несовместимое описание видеопотока. Повторите звонок после перезапуска приложения."
        case .incompatibleRemoteDescription:
            return
                "Ответ на видеозвонок содержит другой набор аудио/видео потоков. Обновите клиент собеседника или повторите аудиозвонок."
        case .sdpGenerationFailed:
            return "Не удалось согласовать параметры аудио/видео."
        case .connectionLost:
            return "Соединение звонка потеряно. Проверьте TURN/STUN на сервере."
        case .timedOut:
            return "Контакт не ответил на звонок."
        }
    }
}
