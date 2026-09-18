import CoreTransferable
import Foundation
import ImageIO
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import os

#if os(iOS)
    import UIKit
#endif

private enum EmojiPickerPresentation: Identifiable {
    case reaction(ChatMessage)
    case composer

    var id: String {
        switch self {
        case .reaction(let message): return "reaction-\(message.clientID)"
        case .composer: return "composer"
        }
    }
}

@MainActor
struct ChatView: View {
    private static let bottomAnchorID = "luma-chat-timeline-bottom"
    private static let timelineCoordinateSpace = "luma-chat-timeline-space"

    @ObservedObject var model: AppModel
    let conversation: Conversation

    @StateObject private var audioRecorder = AudioMessageRecorder()
    @FocusState private var isComposerFocused: Bool
    @State private var draft = ""
    @State private var showingFileImporter = false
    @State private var fileImportMode: FileImportMode = .files
    @State private var showingEncryption = false
    @State private var showingVideoNoteRecorder = false
    @State private var videoNoteIsSending = false
    @State private var showingMediaPicker = false
    @State private var showingPhotoCamera = false
    @State private var photoCameraIsPreparingResult = false
    @State private var showingLocationPicker = false
    @State private var showingGroupInfo = false
    @State private var showingAttachmentPreview = false
    @State private var attachmentPreviewPresentationPending = false
    @State private var attachmentPreviewPresentationTask: Task<Void, Never>?
    @State private var pickedMediaItems: [PhotosPickerItem] = []
    @State private var attachmentDrafts: [AttachmentDraft] = []
    @State private var isPreparingAttachments = false
    @State private var editingMessageID: String?
    @State private var replyingToMessageID: String?
    @State private var forwardingSelection: MessageForwardSelection?
    @State private var selectedMessageIDs: Set<String> = []
    @State private var destructiveAction: MessageDestructiveAction?
    @State private var replyThreadSelection: ReplyThreadSelection?
    @State private var emojiPickerPresentation: EmojiPickerPresentation?
    @State private var hasCompletedInitialScroll = false
    @State private var isNearTimelineBottom = true
    @State private var historyLoadAnchorID: String?
    @State private var historyTopTriggerArmed = true
    @State private var historyTopTriggerVisible = false
    @State private var historyLoadEntryCount = 0
    @State private var historyAutoContinueCount = 0
    @State private var emptyHistoryRetryCount = 0
    @State private var activeCaptureMode: ComposerCaptureMode?
    @State private var preparingCaptureMode: ComposerCaptureMode?
    @State private var captureGestureIsActive = false
    @State private var captureIsLocked = false
    @State private var captureDragTranslation: CGSize = .zero
    @State private var captureAttemptID = UUID()
    @State private var captureStartTask: Task<Void, Never>?
    @State private var captureSuspendsArchiveSync = false
    @State private var pickerResetToken = UUID()
    @State private var timelineEntries: [ChatTimelineEntry] = []
    /// Messages-style entrance state: which rows currently animate, which IDs
    /// the timeline already showed, and whether the opening cascade of this
    /// conversation has played.
    @State private var entranceModes: [String: MessageBubbleEntrance.Mode] = [:]
    @State private var knownEntranceIDs: Set<String> = []
    @State private var hasPlayedOpeningEntrance = false
    @State private var entranceReleaseToken = UUID()

    /// Messages of this conversation straight from the SwiftData store,
    /// ordered like `AppModel.selectedMessages`: timestamp, then clientID.
    @Query private var messages: [ChatMessage]

    init(model: AppModel, conversation: Conversation) {
        self.model = model
        self.conversation = conversation
        let conversationJID = conversation.jid
        _messages = Query(
            filter: #Predicate<ChatMessage> { message in
                message.conversationID == conversationJID
            },
            sort: [
                SortDescriptor(\ChatMessage.timestamp, order: .forward),
                SortDescriptor(\ChatMessage.clientID, order: .forward),
            ]
        )
        _audioRecorder = StateObject(wrappedValue: AudioMessageRecorder())
        _isComposerFocused = FocusState()
        _draft = State(initialValue: "")
        _showingFileImporter = State(initialValue: false)
        _fileImportMode = State(initialValue: FileImportMode.files)
        _showingEncryption = State(initialValue: false)
        _showingVideoNoteRecorder = State(initialValue: false)
        _videoNoteIsSending = State(initialValue: false)
        _showingMediaPicker = State(initialValue: false)
        _showingPhotoCamera = State(initialValue: false)
        _photoCameraIsPreparingResult = State(initialValue: false)
        _showingLocationPicker = State(initialValue: false)
        _showingGroupInfo = State(initialValue: false)
        _showingAttachmentPreview = State(initialValue: false)
        _attachmentPreviewPresentationPending = State(initialValue: false)
        _attachmentPreviewPresentationTask = State<Task<Void, Never>?>(
            initialValue: nil
        )
        _pickedMediaItems = State<[PhotosPickerItem]>(initialValue: [])
        _attachmentDrafts = State<[AttachmentDraft]>(initialValue: [])
        _isPreparingAttachments = State(initialValue: false)
        _editingMessageID = State<String?>(initialValue: nil)
        _replyingToMessageID = State<String?>(initialValue: nil)
        _forwardingSelection = State<MessageForwardSelection?>(
            initialValue: nil
        )
        _selectedMessageIDs = State<Set<String>>(initialValue: [])
        _destructiveAction = State<MessageDestructiveAction?>(initialValue: nil)
        _replyThreadSelection = State<ReplyThreadSelection?>(initialValue: nil)
        _emojiPickerPresentation = State<EmojiPickerPresentation?>(
            initialValue: nil
        )
        _hasCompletedInitialScroll = State(initialValue: false)
        _historyTopTriggerVisible = State(initialValue: false)
        _historyLoadEntryCount = State(initialValue: 0)
        _historyAutoContinueCount = State(initialValue: 0)
        _emptyHistoryRetryCount = State(initialValue: 0)
        _isNearTimelineBottom = State(initialValue: true)
        _historyLoadAnchorID = State<String?>(initialValue: nil)
        _historyTopTriggerArmed = State(initialValue: true)
        _activeCaptureMode = State<ComposerCaptureMode?>(initialValue: nil)
        _preparingCaptureMode = State<ComposerCaptureMode?>(initialValue: nil)
        _captureGestureIsActive = State(initialValue: false)
        _captureIsLocked = State(initialValue: false)
        _captureDragTranslation = State(initialValue: CGSize.zero)
        _captureAttemptID = State(initialValue: UUID())
        _captureStartTask = State<Task<Void, Never>?>(initialValue: nil)
        _captureSuspendsArchiveSync = State(initialValue: false)
        _pickerResetToken = State(initialValue: UUID())
        _timelineEntries = State<[ChatTimelineEntry]>(initialValue: [])
        _entranceModes = State<[String: MessageBubbleEntrance.Mode]>(
            initialValue: [:]
        )
        _knownEntranceIDs = State<Set<String>>(initialValue: [])
        _hasPlayedOpeningEntrance = State(initialValue: false)
        _entranceConversationID = State<String?>(initialValue: nil)
        _entranceReleaseToken = State(initialValue: UUID())
    }

    var body: some View {
        VStack(spacing: 0) {
            if conversation.isGroup, !liveConversation.isGroupJoined {
                groupJoinBanner
            }
            messageTimeline
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isSelectingMessages {
                        selectionActionBar
                    } else {
                        composer
                    }
                }
        }
        .background(Color.secondary.opacity(0.035))
        .navigationTitle("")
        // #if os(iOS)
        //         .navigationBarTitleDisplayMode(.inline)
        // #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                chatNavigationTitle
            }
            if isSelectingMessages {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена", action: clearMessageSelection)
                }
                ToolbarItem(placement: .primaryAction) {
                    Text("Выбрано: \(selectedTimelineMessages.count)")
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    if !conversation.isGroup {
                        Menu {
                            Button {
                                Task {
                                    await model.startCall(
                                        to: conversation.jid,
                                        withVideo: false
                                    )
                                }
                            } label: {
                                Label("Аудиозвонок", systemImage: "phone")
                            }
                            .disabled(!canStartCall)
                            .help("Аудиозвонок")

                            Button {
                                Task {
                                    await model.startCall(
                                        to: conversation.jid,
                                        withVideo: true
                                    )
                                }
                            } label: {
                                Label("Видеозвонок", systemImage: "video")
                            }
                            .disabled(!canStartCall)
                            .help("Видеозвонок")
                            encryptionMenu
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuIndicator(.hidden)
                        .disabled(!canStartCall)
                    }
                    if conversation.isGroup {
                        Button {
                            showingGroupInfo = true
                        } label: {
                            Image(systemName: "person.3")
                        }
                        .help("Информация о группе")
                    }
                }
            }
        }
        #if os(iOS)
            .toolbar(
                replyThreadSelection == nil ? .visible : .hidden,
                for: .navigationBar
            )
            // A pushed conversation takes the whole screen; the tab bar
            // comes back when the user pops back to the list.
            .toolbar(.hidden, for: .tabBar)
        #endif
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: fileImportMode.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            let preferredKind = fileImportMode.preferredKind
            Task {
                await stageImportedFiles(urls, preferredKind: preferredKind)
            }
        }
        .photosPicker(
            isPresented: $showingMediaPicker,
            selection: $pickedMediaItems,
            maxSelectionCount: 20,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current
        )
        // A fresh picker identity per attempt: clearing the selection while
        // the picker is presented desynchronizes its internal state, and the
        // stale selection then leaks into the next presentation.
        .id(pickerResetToken)
        .onChange(of: showingMediaPicker) { _, isPresented in
            guard !isPresented else { return }
            // On Done the binding holds the chosen items; on Cancel SwiftUI
            // restores the pre-presentation value (kept empty below), so
            // staging runs only for a confirmed selection.
            let items = pickedMediaItems
            pickedMediaItems = []
            pickerResetToken = UUID()
            guard !items.isEmpty else { return }
            Task { await stagePickedMedia(items) }
        }
        #if os(iOS)
            .fullScreenCover(
                isPresented: $showingPhotoCamera,
                onDismiss: {
                    schedulePendingAttachmentPreview()
                    if !photoCameraIsPreparingResult {
                        releaseArchiveSyncAfterCapture()
                    }
                }
            ) {
                SystemPhotoCameraView(
                    onDismissRequest: {
                        // Runs synchronously in the picker delegate while the
                        // camera is still presented: dismiss through the
                        // binding so SwiftUI owns the transition, and reserve
                        // the archive-sync suspension across the dismissal
                        // while the file is prepared in the background.
                        showingPhotoCamera = false
                        photoCameraIsPreparingResult = true
                    },
                    onMedia: { result in
                        switch result {
                        case .success(let media):
                            photoCameraIsPreparingResult = true
                            Task { await stageCapturedMedia(media) }
                        case .failure(let error):
                            photoCameraIsPreparingResult = false
                            releaseArchiveSyncAfterCapture()
                            model.errorMessage = error.localizedDescription
                        }
                    },
                    onCancel: {
                        showingPhotoCamera = false
                    }
                )
                .ignoresSafeArea()
            }
        #endif
        .onChange(of: draft) { _, text in
            model.updateComposerActivity(text, in: liveConversation)
        }
        .sheet(isPresented: $showingEncryption) {
            EncryptionDevicesView(model: model, conversation: conversation)
        }
        .sheet(
            isPresented: $showingVideoNoteRecorder,
            onDismiss: {
                if !videoNoteIsSending {
                    releaseArchiveSyncAfterCapture()
                }
            }
        ) {
            VideoNoteCaptureView { recording in
                sendRecordedVideoNote(recording)
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView { location in
                Task {
                    await model.sendLocation(location, to: conversation.jid)
                }
            }
        }
        .sheet(
            isPresented: $showingAttachmentPreview,
            onDismiss: {
                attachmentPreviewPresentationPending = false
                attachmentPreviewPresentationTask?.cancel()
                attachmentPreviewPresentationTask = nil
            }
        ) {
            AttachmentPreviewView(
                model: model,
                conversation: liveConversation,
                drafts: $attachmentDrafts
            )
        }
        .sheet(isPresented: $showingGroupInfo) {
            GroupInfoView(model: model, conversation: liveConversation)
        }
        .sheet(item: $forwardingSelection) { selection in
            ForwardMessageView(model: model, messages: selection.messages) {
                clearMessageSelection()
            }
        }
        .sheet(item: $emojiPickerPresentation) { presentation in
            EmojiPickerView { emoji in
                handleEmojiSelection(emoji, for: presentation)
            }
        }
        .alert(item: $destructiveAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.explanation),
                primaryButton: .destructive(Text(action.confirmationTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
        .overlay {
            replyThreadOverlay
        }
        .onChange(of: conversation.jid) { _, _ in
            hasCompletedInitialScroll = false
            isNearTimelineBottom = true
            historyLoadAnchorID = nil
            historyTopTriggerArmed = true
            historyTopTriggerVisible = false
            historyAutoContinueCount = 0
            emptyHistoryRetryCount = 0
            entranceModes = [:]
            knownEntranceIDs = []
            hasPlayedOpeningEntrance = false
            entranceReleaseToken = UUID()
        }
        .onDisappear {
            model.endConversationViewing(jid: conversation.jid)
            model.endComposerActivity(in: liveConversation)
            attachmentPreviewPresentationTask?.cancel()
            attachmentPreviewPresentationTask = nil
            attachmentPreviewPresentationPending = false
            replyThreadSelection = nil
            clearMessageSelection()
            cancelComposerRecording(feedback: false)
            if !showingVideoNoteRecorder,
                !showingPhotoCamera,
                !videoNoteIsSending,
                !photoCameraIsPreparingResult
            {
                releaseArchiveSyncAfterCapture()
            }
            if !showingAttachmentPreview {
                model.discardAttachmentDrafts(attachmentDrafts)
                attachmentDrafts = []
            }
        }
    }

    @ViewBuilder
    private var replyThreadOverlay: some View {
        if let selection = replyThreadSelection,
            let root = model.message(
                withID: selection.rootID,
                in: conversation.jid
            )
        {
            ReplyThreadOverlay(
                model: model,
                rootMessage: root,
                replies: replyThreadReplies(
                    for: root,
                    selectedReplyID: selection.selectedReplyID
                ),
                selectedReplyID: selection.selectedReplyID,
                onDismiss: dismissReplyThread
            )
            .zIndex(100)
        }
    }

    private var encryptionMenu: some View {
        Menu {
            Section(
                conversation.isGroup
                    ? "Шифрование этой группы" : "Шифрование этого чата"
            ) {
                ForEach(EncryptionPreference.allCases, id: \.rawValue) {
                    preference in
                    Button {
                        model.setEncryptionPreference(
                            preference,
                            for: conversation.jid
                        )
                    } label: {
                        if model.encryptionPreference(for: conversation.jid)
                            == preference
                        {
                            Label(preference.title, systemImage: "checkmark")
                        } else {
                            Text(preference.title)
                        }
                    }
                }
            }
            if !conversation.isGroup {
                Divider()
                Button {
                    showingEncryption = true
                } label: {
                    Label(
                        "Устройства и отпечатки",
                        systemImage: "checkmark.shield"
                    )
                }
            }
        } label: {
            Label("Шифрование", systemImage: encryptionIcon)
        }
        .help(
            encryptionEnabled
                ? "OMEMO включено" : "Сообщения отправляются без OMEMO"
        )
    }

    private var canStartCall: Bool {
        model.connectionStatus == .connected && model.activeCall == nil
    }

    private var selectedTimelineMessages: [ChatMessage] {
        model.selectedMessages.filter {
            selectedMessageIDs.contains($0.clientID)
        }
    }

    private func rebuildTimelineEntries(from newMessages: [ChatMessage]? = nil)
    {
        let source = newMessages ?? messages
        timelineEntries = ChatTimelineEntry.make(from: source)
        updateEntranceModes(for: source)
    }

    /// Decides which rows play a Messages-style entrance after a rebuild.
    /// The first page of an opened conversation cascades bottom-up; rows that
    /// appear later (a send, an incoming message) launch from the composer's
    /// edge. Modes are released once the animation window closes so a row
    /// recycled by the lazy stack during scrolling reappears statically.
    private func updateEntranceModes(for newMessages: [ChatMessage]) {
        let ids = newMessages.map(\.clientID)
        let known = knownEntranceIDs
        knownEntranceIDs = Set(ids)

        guard hasPlayedOpeningEntrance else {
            guard !ids.isEmpty else { return }
            hasPlayedOpeningEntrance = true
            // The first message ever in an empty chat should launch out of
            // the composer like any other send, not cascade in.
            if ids.count == 1, known.isEmpty,
                newMessages.first?.direction == .outgoing
            {
                applyLaunch(for: newMessages, ids: ids)
                return
            }
            let delays = ChatMessageEntrancePolicy.entranceDelays(
                forIDs: ids
            )
            for (id, delay) in delays {
                entranceModes[id] = .cascade(delay: delay)
            }
            scheduleEntranceRelease(
                ids: Set(delays.keys),
                after: ChatMessageEntrancePolicy.entranceCascadeDuration
            )
            return
        }

        applyLaunch(
            for: newMessages,
            ids: ChatMessageEntrancePolicy.appendedLaunchIDs(
                in: ids,
                after: known
            )
        )
    }

    private func applyLaunch(for messages: [ChatMessage], ids: [String]) {
        guard !ids.isEmpty else { return }
        let launched = Set(ids)
        var applied: Set<String> = []
        for message in messages where launched.contains(message.clientID) {
            entranceModes[message.clientID] = .launch(
                outgoing: message.direction == .outgoing
            )
            applied.insert(message.clientID)
        }
        scheduleEntranceRelease(
            ids: applied,
            after: ChatMessageEntrancePolicy.entranceAnimationDuration
        )
    }

    private func scheduleEntranceRelease(
        ids: Set<String>,
        after delay: TimeInterval
    ) {
        guard !ids.isEmpty else { return }
        let token = entranceReleaseToken
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            guard !Task.isCancelled, token == entranceReleaseToken else {
                return
            }
            for id in ids {
                entranceModes[id] = nil
            }
        }
    }

    private var isSelectingMessages: Bool {
        !selectedMessageIDs.isEmpty
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            if hasCompletedInitialScroll,
                                model.hasMoreOlderHistory,
                                !timelineEntries.isEmpty
                            {
                                Color.clear
                                    .frame(height: 1)
                                    .accessibilityHidden(true)
                                    .onAppear {
                                        historyTopTriggerVisible = true
                                        guard historyTopTriggerArmed,
                                            !model.isLoadingOlderHistory
                                        else { return }
                                        triggerOlderHistoryLoad()
                                    }
                                    .onDisappear {
                                        historyTopTriggerVisible = false
                                        historyTopTriggerArmed = true
                                        historyAutoContinueCount = 0
                                    }
                                if model.isLoadingOlderHistory {
                                    ProgressView()
                                        .controlSize(.small)
                                        .padding(.vertical, 6)
                                }
                            }
                            if timelineEntries.isEmpty {
                                ContentUnavailableView(
                                    emptyChatTitle,
                                    systemImage: conversation.isGroup
                                        ? "person.3.fill"
                                        : (encryptionEnabled
                                            ? "lock.shield" : "lock.open"),
                                    description: Text(emptyChatDescription)
                                )
                                .padding(.top, 80)
                                .onAppear {
                                    // Empty timeline has no scroll gesture, so load
                                    // the first page directly when it appears.
                                    guard model.hasMoreOlderHistory,
                                        !model.isLoadingOlderHistory
                                    else { return }
                                    model
                                        .loadOlderHistoryForSelectedConversation()
                                }
                            } else {
                                ForEach(timelineEntries) { entry in
                                    let message = entry.message
                                    if entry.startsNewDay {
                                        datePill(message.timestamp)
                                    }
                                    MessageBubble(
                                        model: model,
                                        message: message,
                                        isSelectionMode: isSelectingMessages,
                                        isSelected: selectedMessageIDs.contains(
                                            message.clientID
                                        ),
                                        onAttachmentTap: {
                                            Task {
                                                await model.previewAttachment(
                                                    message
                                                )
                                            }
                                        },
                                        onEdit: { startEditing(message) },
                                        onReply: { startReplying(to: message) },
                                        onForward: {
                                            presentForwarding([message])
                                        },
                                        onRetry: {
                                            Task {
                                                await model.retryMediaMessage(
                                                    message
                                                )
                                            }
                                        },
                                        onToggleSelection: {
                                            toggleMessageSelection(message)
                                        },
                                        onBeginSelection: {
                                            beginMessageSelection(with: message)
                                        },
                                        onRetract: {
                                            destructiveAction = .init(
                                                kind: .retract,
                                                messages: [message]
                                            )
                                        },
                                        onDelete: {
                                            destructiveAction = .init(
                                                kind: .localDelete,
                                                messages: [message]
                                            )
                                        },
                                        onReplyTap: { targetID in
                                            presentReplyThread(
                                                rootID: targetID,
                                                selectedReplyID: message
                                                    .clientID
                                            )
                                        },
                                        onReact: { emoji in
                                            Task {
                                                await model.toggleReaction(
                                                    emoji,
                                                    on: message
                                                )
                                            }
                                        },
                                        onReactPicker: {
                                            emojiPickerPresentation = .reaction(
                                                message
                                            )
                                        }
                                    )
                                    .modifier(
                                        MessageBubbleEntrance(
                                            mode: entranceModes[
                                                message.clientID
                                            ] ?? .settled
                                        )
                                    )
                                    .id(message.clientID)
                                }
                            }
                        }
                        .padding(.vertical, 10)

                        timelineBottomSentinel
                        #if os(iOS)
                            ChatScrollMetricsObserver(
                                identity: conversation.jid
                            ) { isNearBottom in
                                guard isNearTimelineBottom != isNearBottom
                                else { return }
                                isNearTimelineBottom = isNearBottom
                            }
                            .frame(height: 0)
                            .accessibilityHidden(true)
                        #endif
                    }
                    .defaultScrollAnchor(.bottom)
                    #if os(iOS)
                        .scrollDismissesKeyboard(.interactively)
                    #endif
                    .coordinateSpace(name: Self.timelineCoordinateSpace)
                    .onAppear {
                        rebuildTimelineEntries()
                    }
                    .onChange(of: messages) { _, newMessages in
                        rebuildTimelineEntries(from: newMessages)
                    }
                    .accessibilityIdentifier("chat-timeline")
                    #if os(macOS)
                        .onPreferenceChange(TimelineBottomYPreferenceKey.self) {
                            bottomY in
                            updateTimelineBottomProximity(
                                bottomY: bottomY,
                                viewportHeight: viewport.size.height
                            )
                        }
                    #endif
                    .task(id: timelineEntries.last?.id) {
                        await performInitialScrollAfterLayout(using: proxy)
                    }
                    .onChange(of: timelineEntries.last?.id) { oldID, newID in
                        guard hasCompletedInitialScroll,
                            let newID,
                            newID != oldID,
                            isNearTimelineBottom
                                || timelineEntries.last?.message.direction
                                    == .outgoing
                        else {
                            return
                        }
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: model.isLoadingOlderHistory) {
                        wasLoading,
                        isLoading in
                        guard wasLoading, !isLoading else { return }
                        // Restore the scroll position so the newly loaded
                        // page appears above the previously visible one. Only
                        // while the user is still at the top: a slow page must
                        // never yank the timeline away from where the user
                        // scrolled while it was loading.
                        if let anchor = historyLoadAnchorID,
                            historyTopTriggerVisible
                        {
                            Task { @MainActor in
                                await Task.yield()
                                proxy.scrollTo(anchor, anchor: .top)
                                historyLoadAnchorID = nil
                            }
                        } else {
                            historyLoadAnchorID = nil
                        }
                        // The trigger is one-shot per visibility cycle.
                        // Re-arm it whenever a load settles so the next
                        // scroll gesture can fire again even if this page
                        // inserted nothing.
                        historyTopTriggerArmed = true
                        if timelineEntries.isEmpty {
                            handleEmptyHistoryLoadCompleted()
                        } else if historyTopTriggerVisible {
                            // The page left the sentinel on screen: it either
                            // inserted no rows (reactions, duplicates) or the
                            // anchor scroll did not push it away. While the
                            // user stays at the top, continue through such
                            // pages so scroll-up never appears dead. Every
                            // page advances the server cursor, so this loop
                            // is bounded by the archive itself.
                            if timelineEntries.count
                                == historyLoadEntryCount,
                                model.hasMoreOlderHistory,
                                historyAutoContinueCount < 6
                            {
                                historyAutoContinueCount += 1
                                triggerOlderHistoryLoad()
                            } else {
                                historyAutoContinueCount = 0
                            }
                        }
                    }
                    .onChange(of: timelineEntries.count) { _, _ in
                        selectedMessageIDs.formIntersection(
                            Set(timelineEntries.map(\.id))
                        )
                    }

                    if hasCompletedInitialScroll,
                        !timelineEntries.isEmpty,
                        !isNearTimelineBottom
                    {
                        jumpToLatestButton(using: proxy)
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                            .transition(
                                .scale(scale: 0.82).combined(with: .opacity)
                            )
                            .zIndex(10)
                    }
                }
                .animation(
                    .easeInOut(duration: 0.16),
                    value: isNearTimelineBottom
                )
            }
        }
    }

    @ViewBuilder
    private var timelineBottomSentinel: some View {
        #if os(iOS)
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
                .id(Self.bottomAnchorID)
        #else
            Color.clear
                .frame(height: 1)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TimelineBottomYPreferenceKey.self,
                            value: geometry.frame(
                                in: .named(Self.timelineCoordinateSpace)
                            ).maxY
                        )
                    }
                }
                .accessibilityHidden(true)
                .id(Self.bottomAnchorID)
        #endif
    }

    private var selectionActionBar: some View {
        HStack(spacing: 18) {
            Text("Выбрано: \(selectedTimelineMessages.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                presentForwarding(selectedTimelineMessages)
            } label: {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(
                selectedTimelineMessages.isEmpty
                    || !selectedTimelineMessages.allSatisfy(\.canBeForwarded)
            )
            .accessibilityLabel("Переслать выбранные сообщения")

            Menu {
                Button(role: .destructive) {
                    destructiveAction = .init(
                        kind: .localDelete,
                        messages: selectedTimelineMessages
                    )
                } label: {
                    Label("Удалить у меня", systemImage: "trash")
                }

                if !selectedTimelineMessages.isEmpty,
                    selectedTimelineMessages.allSatisfy(\.canBeRetracted)
                {
                    Button(role: .destructive) {
                        destructiveAction = .init(
                            kind: .retract,
                            messages: selectedTimelineMessages
                        )
                    } label: {
                        Label("Удалить у всех", systemImage: "trash.slash")
                    }
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
            }
            .disabled(selectedTimelineMessages.isEmpty)
            .accessibilityLabel("Удалить выбранные сообщения")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Group {
                    if isCapturePresentationVisible {
                        recordingStatusStrip
                    } else {
                        HStack(alignment: .bottom, spacing: 8) {
                            attachmentButton
                                .disabled(!canOpenAttachments)
                            messageInput
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                composerActionControl
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(.top, 6)
        .background(Color.clear)
        .animation(
            .easeInOut(duration: 0.18),
            value: isCapturePresentationVisible
        )
    }

    private var messageInput: some View {
        VStack {
            if let editingMessage {
                editingBanner(editingMessage)
            } else if let replyingToMessage {
                replyBanner(replyingToMessage)
            }
            HStack(alignment: .center, spacing: 8) {
                TextField(
                    editingMessageID == nil
                        ? "Сообщение" : "Изменить сообщение",
                    text: $draft,
                    axis: .vertical
                )
                .focused($isComposerFocused)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { sendDraft() }

                Button {
                    emojiPickerPresentation = .composer
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Эмодзи")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
        .glassEffect(in: .rect(cornerRadius: 21))
    }

    @ViewBuilder
    private var composerActionControl: some View {
        if editingMessageID != nil || !draftIsEmpty {
            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        canUseComposer ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 42, height: 42)
                //                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canUseComposer)
            .accessibilityLabel(
                editingMessageID == nil ? "Отправить" : "Сохранить исправление"
            )
            .glassEffect()
        } else {
            TelegramRecordButton(
                mode: .voice,
                isRecording: isCapturePresentationVisible,
                isLocked: captureIsLocked,
                isFinalizing: false,
                isEnabled: canUseComposer,
                onTap: captureButtonTapped,
                onLongPressBegan: beginCaptureGesture,
                onLongPressChanged: updateCaptureGesture,
                onLongPressEnded: endCaptureGesture,
                onLongPressCancelled: {
                    cancelComposerRecording(feedback: false)
                }
            )
            .overlay(alignment: .top) {
                if isCapturePresentationVisible, !captureIsLocked {
                    recordingLockIndicator
                        .offset(
                            y: -74
                                + min(
                                    12,
                                    max(
                                        -14,
                                        captureDragTranslation.height * 0.12
                                    )
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var attachmentButton: some View {
        Menu {
            #if os(iOS)
                Button {
                    presentCamera()
                } label: {
                    Label("Камера", systemImage: "camera.fill")
                }
                .disabled(!SystemPhotoCameraView.isAvailable)
            #endif
            Button {
                dismissKeyboard()
                showingMediaPicker = true
            } label: {
                Label(
                    "Фото или видео (несколько)",
                    systemImage: "photo.on.rectangle"
                )
            }
            Button {
                presentFileImporter(.audio)
            } label: {
                Label("Музыка", systemImage: "music.note")
            }
            Button {
                presentVideoNoteRecorder()
            } label: {
                Label("Видеосообщение", systemImage: "video.circle")
            }
            Button {
                dismissKeyboard()
                model.audioPlayback.stop()
                showingLocationPicker = true
            } label: {
                Label("Отправить геопозицию", systemImage: "location.fill")
            }
            Divider()
            Button {
                presentFileImporter(.files)
            } label: {
                Label("Файлы (несколько)", systemImage: "doc.on.doc")
            }
        } label: {
            ZStack {
                if model.isSendingAttachment || isPreparingAttachments {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "paperclip")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .glassEffect()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить вложение")
        .help(
            "Открыть камеру или добавить фото, видео, файлы, музыку и геопозицию"
        )
    }

    private var editingMessage: ChatMessage? {
        guard let editingMessageID else { return nil }
        return model.selectedMessages.first { $0.clientID == editingMessageID }
    }

    private var replyingToMessage: ChatMessage? {
        guard let replyingToMessageID else { return nil }
        return model.selectedMessages.first {
            $0.clientID == replyingToMessageID && $0.canBeRepliedTo
        }
    }

    private var requiresOMEMO: Bool {
        editingMessage?.security == .omemo
            || (editingMessageID == nil && encryptionEnabled)
    }

    private var encryptionEnabled: Bool {
        model.encryptionEnabled(for: conversation.jid)
    }

    private var encryptionIcon: String {
        if !encryptionEnabled { return "lock.open" }
        return model.isOMEMOReady
            ? "lock.fill" : "lock.trianglebadge.exclamationmark"
    }

    private var liveConversation: Conversation {
        model.conversations.first(where: { $0.jid == conversation.jid })
            ?? conversation
    }

    private var chatNavigationTitle: some View {
        ChatNavigationTitle(model: model, conversation: conversation)
    }

    private var canSendToConversation: Bool {
        !conversation.isGroup || liveConversation.isGroupJoined
    }

    private var emptyChatTitle: String {
        if conversation.isGroup { return "Групповая комната" }
        return encryptionEnabled
            ? "Новый защищённый чат" : "Новый чат без шифрования"
    }

    private var emptyChatDescription: String {
        if conversation.isGroup {
            return liveConversation.isGroupJoined
                ? "Напишите первое сообщение участникам комнаты."
                : "Войдите в комнату, чтобы отправлять сообщения."
        }
        return encryptionEnabled
            ? "Сообщения этому контакту будут отправляться с OMEMO."
            : "Сообщения этому контакту будут передаваться открытым текстом внутри TLS-соединения."
    }

    private var groupJoinBanner: some View {
        HStack(spacing: 10) {
            Image(
                systemName: liveConversation.invitedBy == nil
                    ? "person.3" : "envelope.badge"
            )
            .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    liveConversation.invitedBy == nil
                        ? "Комната не подключена" : "Вас пригласили в комнату"
                )
                .font(.subheadline.weight(.semibold))
                Text(liveConversation.invitedBy ?? conversation.jid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(liveConversation.invitedBy == nil ? "Войти" : "Принять") {
                Task { await model.joinGroup(jid: conversation.jid) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(0.09))
    }

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canUseComposer: Bool {
        canSendToConversation
            && (!requiresOMEMO || model.isOMEMOReady)
            && !model.isSendingAttachment
            && !isPreparingAttachments
            && (editingMessageID == nil || !draftIsEmpty)
    }

    private var canOpenAttachments: Bool {
        canUseComposer
            && !isCapturePresentationVisible
            && editingMessageID == nil
    }

    private var isCapturePresentationVisible: Bool {
        activeCaptureMode != nil
            || preparingCaptureMode != nil
            || audioRecorder.isRecording
    }

    private var captureElapsed: TimeInterval {
        audioRecorder.elapsed
    }

    private var recordingCancelHintOpacity: Double {
        ComposerRecordingGesturePolicy.cancelHintOpacity(
            for: captureDragTranslation
        )
    }

    private var recordingStatusStrip: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)

            Text(formatDuration(captureElapsed))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .contentTransition(.numericText())

            Spacer(minLength: 6)

            if captureIsLocked {
                Button("Отмена") {
                    cancelComposerRecording()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
            } else {
                Label("Влево — отмена", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .offset(x: min(0, captureDragTranslation.width * 0.18))
                    .opacity(recordingCancelHintOpacity)
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 42)
        .glassEffect()
    }

    private var recordingLockIndicator: some View {
        VStack(spacing: 1) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 18, weight: .medium))
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.primary)
        .frame(width: 38, height: 55)
        .glassEffect(in: Capsule())
        .accessibilityLabel("Проведите вверх, чтобы зафиксировать запись")
    }

    private func captureButtonTapped() {
        if captureIsLocked {
            finishComposerRecording()
        }
    }

    private func beginCaptureGesture() {
        guard canUseComposer,
            draftIsEmpty,
            editingMessageID == nil,
            !isCapturePresentationVisible
        else { return }

        dismissKeyboard()
        model.audioPlayback.stop()
        captureStartTask?.cancel()
        let attemptID = UUID()
        captureAttemptID = attemptID
        captureGestureIsActive = true
        captureIsLocked = false
        captureDragTranslation = .zero
        preparingCaptureMode = .voice
        activeCaptureMode = nil
        impactFeedback()

        captureStartTask = Task { @MainActor in
            do {
                try await audioRecorder.start()
                guard !Task.isCancelled,
                    captureAttemptID == attemptID,
                    captureGestureIsActive || captureIsLocked
                else {
                    audioRecorder.cancel()
                    return
                }

                guard captureAttemptID == attemptID else { return }
                preparingCaptureMode = nil
                activeCaptureMode = .voice
            } catch {
                audioRecorder.cancel()
                guard captureAttemptID == attemptID else { return }
                resetCaptureInterface()
                if !(error is CancellationError) {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateCaptureGesture(_ translation: CGSize) {
        guard isCapturePresentationVisible, !captureIsLocked else { return }
        captureDragTranslation = translation
        switch ComposerRecordingGesturePolicy.resolution(for: translation) {
        case .continueRecording:
            break
        case .cancel:
            cancelComposerRecording()
        case .lock:
            captureIsLocked = true
            captureGestureIsActive = false
            captureDragTranslation = .zero
            impactFeedback()
        }
    }

    private func endCaptureGesture(_ translation: CGSize) {
        guard isCapturePresentationVisible else { return }
        updateCaptureGesture(translation)
        guard isCapturePresentationVisible, !captureIsLocked else { return }
        captureGestureIsActive = false

        guard activeCaptureMode != nil else {
            // A first-run permission prompt can outlive the physical press.
            // Do not send a surprise recording after the user releases it.
            cancelComposerRecording(feedback: false)
            return
        }
        finishComposerRecording()
    }

    private func finishComposerRecording() {
        captureGestureIsActive = false
        captureDragTranslation = .zero

        switch activeCaptureMode {
        case .voice:
            do {
                let recording = try audioRecorder.finish()
                resetCaptureInterface()
                Task {
                    let sentID = await model.sendAttachment(
                        from: recording.url,
                        preferredKind: .voice,
                        duration: recording.duration,
                        to: conversation.jid
                    )
                    if sentID != nil {
                        try? FileManager.default.removeItem(at: recording.url)
                    }
                }
            } catch {
                resetCaptureInterface()
                model.errorMessage = error.localizedDescription
            }
        case nil:
            cancelComposerRecording(feedback: false)
        }
    }

    private func cancelComposerRecording(feedback: Bool = true) {
        let hadCapture = isCapturePresentationVisible
        captureStartTask?.cancel()
        captureStartTask = nil
        captureAttemptID = UUID()
        if audioRecorder.isRecording {
            audioRecorder.cancel()
        }
        resetCaptureInterface()
        if feedback, hadCapture {
            impactFeedback()
        }
    }

    private func resetCaptureInterface() {
        captureStartTask?.cancel()
        captureStartTask = nil
        captureGestureIsActive = false
        captureIsLocked = false
        captureDragTranslation = .zero
        preparingCaptureMode = nil
        activeCaptureMode = nil
    }

    private func releaseArchiveSyncAfterCapture() {
        guard captureSuspendsArchiveSync else { return }
        captureSuspendsArchiveSync = false
        model.setVideoNoteCaptureActive(false)
    }

    private func dismissKeyboard() {
        isComposerFocused = false
        #if os(iOS)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        #endif
    }

    private func impactFeedback() {
        #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func sendDraft() {
        let outgoing = draft
        guard canSendToConversation,
            !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        draft = ""
        if let editingMessageID {
            self.editingMessageID = nil
            Task {
                await model.editMessage(id: editingMessageID, newBody: outgoing)
            }
        } else {
            let replyTarget = replyingToMessage
            replyingToMessageID = nil
            Task {
                await model.sendText(
                    outgoing,
                    to: conversation.jid,
                    replyingTo: replyTarget
                )
            }
        }
    }

    @discardableResult
    private func stageImportedFiles(
        _ urls: [URL],
        preferredKind: ChatMessage.Kind? = nil
    ) async -> Bool {
        guard !urls.isEmpty else { return false }
        isPreparingAttachments = true
        defer { isPreparingAttachments = false }
        let prepared = await model.prepareAttachmentDrafts(
            from: urls,
            preferredKind: preferredKind,
            for: conversation.jid
        )
        guard !prepared.isEmpty else { return false }
        model.discardAttachmentDrafts(attachmentDrafts)
        attachmentDrafts = prepared
        presentAttachmentPreviewAfterPickerDismissal()
        return true
    }

    private func stageCapturedMedia(_ media: CapturedCameraMedia) async {
        defer {
            try? FileManager.default.removeItem(at: media.url)
            photoCameraIsPreparingResult = false
            releaseArchiveSyncAfterCapture()
        }
        let logger = Logger(subsystem: "Luma", category: "video-preview")
        await waitForCameraFileSettling(at: media.url, logger: logger)
        let staged = await stageImportedFiles(
            [media.url],
            preferredKind: media.kind
        )
        if staged {
            if let draft = attachmentDrafts.last {
                logger.info(
                    "camera draft staged: kind=\(draft.kind.rawValue) mime=\(draft.mimeType) size=\(draft.byteCount) duration=\(String(describing: draft.duration)) thumbnailBytes=\(draft.thumbnailData?.count ?? 0)"
                )
            }
        } else {
            logger.error("camera staging produced no drafts")
            if model.errorMessage == nil {
                model.errorMessage =
                    "Камера вернула файл, который не удалось подготовить к отправке."
            }
        }
    }

    /// The picker can hand over a movie whose final bytes are still being
    /// flushed. Wait until the file size stops changing so staging never
    /// copies a truncated file.
    private func waitForCameraFileSettling(at url: URL, logger: Logger) async {
        guard
            let initial = try? url.resourceValues(forKeys: [.fileSizeKey])
                .fileSize
        else {
            return
        }
        var previous = initial
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard
                let current = try? url.resourceValues(forKeys: [.fileSizeKey])
                    .fileSize
            else {
                return
            }
            if current == previous {
                return
            }
            previous = current
        }
        logger.warning("camera file size kept changing; staging anyway")
    }

    private func presentCamera() {
        #if os(iOS)
            guard SystemPhotoCameraView.isAvailable else {
                model.errorMessage = "Камера недоступна на этом устройстве."
                return
            }
            dismissKeyboard()
            model.audioPlayback.stop()
            photoCameraIsPreparingResult = false
            if !captureSuspendsArchiveSync {
                captureSuspendsArchiveSync = true
                model.setVideoNoteCaptureActive(true)
            }
            Task { @MainActor in
                await Task.yield()
                showingPhotoCamera = true
            }
        #endif
    }

    private func presentVideoNoteRecorder() {
        guard !showingVideoNoteRecorder, !videoNoteIsSending else { return }
        dismissKeyboard()
        model.audioPlayback.stop()
        if !captureSuspendsArchiveSync {
            captureSuspendsArchiveSync = true
            model.setVideoNoteCaptureActive(true)
        }
        Task { @MainActor in
            // Let the attachment menu finish dismissing before presenting the
            // dedicated camera. This keeps the menu tap separate from the
            // voice-message touch surface.
            await Task.yield()
            showingVideoNoteRecorder = true
        }
    }

    private func sendRecordedVideoNote(_ recording: VideoNoteRecorder.Recording)
    {
        videoNoteIsSending = true
        Task { @MainActor in
            defer {
                videoNoteIsSending = false
                releaseArchiveSyncAfterCapture()
            }
            let sentID = await model.sendAttachment(
                from: recording.url,
                preferredKind: .videoNote,
                duration: recording.duration,
                to: conversation.jid
            )
            if sentID != nil {
                try? FileManager.default.removeItem(at: recording.url)
            }
        }
    }

    private func presentFileImporter(_ mode: FileImportMode) {
        dismissKeyboard()
        fileImportMode = mode
        // Let Menu finish dismissing before SwiftUI presents the native file
        // panel. A single importer owns both modes, so presentations no longer
        // compete with each other.
        Task { @MainActor in
            await Task.yield()
            showingFileImporter = true
        }
    }

    private func presentReplyThread(rootID: String, selectedReplyID: String) {
        guard model.message(withID: rootID, in: conversation.jid) != nil else {
            model.errorMessage =
                "Исходное сообщение ещё не загружено в локальную историю."
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            replyThreadSelection = ReplyThreadSelection(
                rootID: rootID,
                selectedReplyID: selectedReplyID
            )
        }
    }

    private func dismissReplyThread() {
        withAnimation(.easeIn(duration: 0.18)) {
            replyThreadSelection = nil
        }
    }

    private func replyThreadReplies(
        for root: ChatMessage,
        selectedReplyID: String
    ) -> [ChatMessage] {
        var sourceIdentifiers: Set<String> = [root.clientID]
        if let stanzaID = root.stanzaID { sourceIdentifiers.insert(stanzaID) }
        if let replyIdentifier = root.replyIdentifier {
            sourceIdentifiers.insert(replyIdentifier)
        }

        var replies = model.selectedMessages.filter { candidate in
            guard let replyToID = candidate.replyToID else { return false }
            return sourceIdentifiers.contains(replyToID)
        }
        if !replies.contains(where: { $0.clientID == selectedReplyID }),
            let selected = model.message(
                withID: selectedReplyID,
                in: conversation.jid
            )
        {
            replies.append(selected)
        }
        return replies.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.clientID < rhs.clientID
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    private func stagePickedMedia(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !isPreparingAttachments else { return }
        isPreparingAttachments = true
        var sourceURLs: [URL] = []
        var failedItemCount = 0
        defer {
            isPreparingAttachments = false
            sourceURLs.forEach(discardPickedMediaFile)
        }
        model.clearError()

        let prepared = await model.withMediaPreparationActivity {
            for item in items.prefix(20) {
                do {
                    sourceURLs.append(try await loadPickedMediaFile(item))
                } catch {
                    failedItemCount += 1
                }
            }
            guard !sourceURLs.isEmpty else { return [AttachmentDraft]() }
            return await model.prepareAttachmentDrafts(
                from: sourceURLs,
                for: conversation.jid
            )
        }

        guard !sourceURLs.isEmpty else {
            model.errorMessage =
                MediaPickerError.cannotReadSelection.errorDescription
            return
        }
        failedItemCount += max(0, sourceURLs.count - prepared.count)
        guard !prepared.isEmpty else { return }
        model.discardAttachmentDrafts(attachmentDrafts)
        attachmentDrafts = prepared
        presentAttachmentPreviewAfterPickerDismissal()
        if failedItemCount > 0 {
            model.errorMessage =
                "Не удалось подготовить \(failedItemCount) из \(items.prefix(20).count) выбранных фото или видео. Остальные готовы к отправке."
        }
    }

    private func presentAttachmentPreviewAfterPickerDismissal() {
        guard !attachmentDrafts.isEmpty else { return }
        attachmentPreviewPresentationPending = true
        schedulePendingAttachmentPreview()
    }

    private func schedulePendingAttachmentPreview() {
        guard attachmentPreviewPresentationPending else { return }
        attachmentPreviewPresentationTask?.cancel()
        attachmentPreviewPresentationTask = Task { @MainActor in
            // `isPresented` becomes false at the beginning of UIKit's
            // dismissal animation. Starting another sheet in that same frame
            // is ignored on iOS. Leave a short hand-off window, then keep the
            // request pending until every system picker has really gone away.
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }

            for _ in 0..<120 {
                guard !Task.isCancelled,
                    attachmentPreviewPresentationPending,
                    !attachmentDrafts.isEmpty
                else { return }
                if !showingMediaPicker,
                    !showingPhotoCamera,
                    !showingFileImporter,
                    !isPreparingAttachments,
                    !showingAttachmentPreview
                {
                    attachmentPreviewPresentationPending = false
                    showingAttachmentPreview = true
                    attachmentPreviewPresentationTask = nil
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
            }
            attachmentPreviewPresentationTask = nil
        }
    }

    private func loadPickedMediaFile(_ item: PhotosPickerItem) async throws
        -> URL
    {
        let supportsImage = item.supportedContentTypes.contains {
            $0.conforms(to: .image)
        }
        let supportsVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie)
        }
        // A Live Photo can advertise both representations. Prefer its still
        // image, while a video-only asset starts with the movie representation.
        let order = MediaPickerSelectionPolicy.preferredOrder(
            supportsImage: supportsImage,
            supportsVideo: supportsVideo
        )
        var lastError: Error?

        for representation in order {
            do {
                switch representation {
                case .photo:
                    return try await loadPickedPhoto(item)
                case .video:
                    return try await loadPickedVideo(item)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MediaPickerError.cannotReadSelection
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async throws -> URL {
        let fileRepresentation = try? await item.loadTransferable(
            type: PickedPhoto.self
        )
        if let photo = fileRepresentation {
            return photo.url
        }

        let dataRepresentation = try await item.loadTransferable(
            type: Data.self
        )
        guard let data = dataRepresentation, !data.isEmpty else {
            throw MediaPickerError.cannotReadSelection
        }
        return try await Task.detached(priority: .userInitiated) {
            try writePickedImageData(data)
        }.value
    }

    private func loadPickedVideo(_ item: PhotosPickerItem) async throws -> URL {
        guard
            let video = try await item.loadTransferable(type: PickedVideo.self)
        else {
            throw MediaPickerError.cannotReadSelection
        }
        return video.url
    }

    private func discardPickedMediaFile(_ url: URL) {
        let pickerRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LumaPhotoPicker", isDirectory: true)
            .standardizedFileURL
        let parent = url.deletingLastPathComponent().standardizedFileURL
        if parent.deletingLastPathComponent() == pickerRoot {
            try? FileManager.default.removeItem(at: parent)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func startEditing(_ message: ChatMessage) {
        guard message.canBeEdited else { return }
        cancelComposerRecording(feedback: false)
        replyingToMessageID = nil
        editingMessageID = message.clientID
        draft = message.body
        isComposerFocused = true
    }

    private func handleEmojiSelection(
        _ emoji: String,
        for presentation: EmojiPickerPresentation
    ) {
        switch presentation {
        case .reaction(let message):
            Task { await model.toggleReaction(emoji, on: message) }
        case .composer:
            draft.append(emoji)
        }
    }

    private func beginMessageSelection(with message: ChatMessage) {
        cancelComposerRecording(feedback: false)
        dismissKeyboard()
        if editingMessageID != nil { cancelEditing() }
        cancelReplying()
        selectedMessageIDs.insert(message.clientID)
    }

    private func toggleMessageSelection(_ message: ChatMessage) {
        if selectedMessageIDs.contains(message.clientID) {
            selectedMessageIDs.remove(message.clientID)
        } else {
            selectedMessageIDs.insert(message.clientID)
        }
    }

    private func clearMessageSelection() {
        selectedMessageIDs.removeAll()
    }

    private func presentForwarding(_ messages: [ChatMessage]) {
        let forwardable = messages.filter(\.canBeForwarded)
        guard !forwardable.isEmpty else { return }
        forwardingSelection = MessageForwardSelection(messages: forwardable)
    }

    private func startReplying(to message: ChatMessage) {
        guard message.canBeRepliedTo else { return }
        cancelComposerRecording(feedback: false)
        if editingMessageID != nil {
            editingMessageID = nil
            draft = ""
        }
        replyingToMessageID = message.clientID
        isComposerFocused = true
    }

    private func cancelEditing() {
        editingMessageID = nil
        draft = ""
    }

    private func cancelReplying() {
        replyingToMessageID = nil
    }

    private func editingBanner(_ message: ChatMessage) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Редактирование")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: cancelEditing) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить редактирование")
        }
    }

    /// Telegram-style reply plate: a rounded card above the composer with
    /// the reply header, a close button and the quoted message preview.
    private func replyBanner(_ message: ChatMessage) -> some View {
        HStack(alignment: .center) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(
                        "Ответ: \(message.senderDisplayName ?? model.displayName(for: message.senderJID))"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                }
                Text(message.quotePreview)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Button(action: cancelReplying) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить ответ")
        }
        .accessibilityIdentifier("reply-banner")
    }

    private func perform(_ action: MessageDestructiveAction) {
        let ids = Set(action.messages.map(\.clientID))
        if let editingMessageID, ids.contains(editingMessageID) {
            cancelEditing()
        }
        if let replyingToMessageID, ids.contains(replyingToMessageID) {
            cancelReplying()
        }
        selectedMessageIDs.subtract(ids)
        switch action.kind {
        case .localDelete:
            model.deleteMessagesLocally(ids: ids, in: conversation.jid)
        case .retract:
            Task {
                for message in action.messages where message.canBeRetracted {
                    await model.retractMessage(id: message.clientID)
                }
            }
        }
    }

    private func datePill(_ date: Date) -> some View {
        Text(date, format: .dateTime.day().month(.wide).year())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .padding(.vertical, 10)
    }

    private func jumpToLatestButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            scrollToBottom(proxy, animated: true)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .glassEffect()
        .accessibilityLabel("Перейти к последнему сообщению")
        .help("Перейти в конец истории")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !model.selectedMessages.isEmpty else { return }
        let action = { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } else {
            action()
        }
    }

    /// Starts one interactive older-history page load from the top sentinel.
    /// Remembers the first visible entry so the viewport can be restored when
    /// the page arrives.
    private func triggerOlderHistoryLoad() {
        historyTopTriggerArmed = false
        historyLoadAnchorID = timelineEntries.first?.id
        historyLoadEntryCount = timelineEntries.count
        model.loadOlderHistoryForSelectedConversation()
    }

    /// A finished load left the timeline empty. Retry a bounded number of
    /// times with a short delay: the first page of an empty chat can fail
    /// transiently (timeout, reconnect), and an empty timeline has no scroll
    /// gesture that could retry it manually.
    private func handleEmptyHistoryLoadCompleted() {
        guard model.hasMoreOlderHistory,
            !model.isLoadingOlderHistory,
            emptyHistoryRetryCount < 3
        else { return }
        emptyHistoryRetryCount += 1
        Task { @MainActor [weak model] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                timelineEntries.isEmpty,
                model?.hasMoreOlderHistory == true,
                model?.isLoadingOlderHistory == false
            else { return }
            model?.loadOlderHistoryForSelectedConversation()
        }
    }

    private func performInitialScrollAfterLayout(using proxy: ScrollViewProxy)
        async
    {
        guard !hasCompletedInitialScroll else { return }
        guard !model.selectedMessages.isEmpty else {
            // Empty conversation: there is nothing to scroll to, so the
            // scroll-to-top gesture can never fire. Load the first page of
            // history directly so a newly-created or emptied chat still fills.
            if model.hasMoreOlderHistory, !model.isLoadingOlderHistory {
                model.loadOlderHistoryForSelectedConversation()
            }
            return
        }

        // ScrollViewReader can receive its first command before a long
        // LazyVStack has published the bottom anchor. Yield once for layout,
        // then repeat on the next frame to make opening at the latest message
        // deterministic on iOS, iPadOS and macOS.
        await Task.yield()
        guard !Task.isCancelled else { return }
        scrollToBottom(proxy, animated: false)

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else { return }
        scrollToBottom(proxy, animated: false)
        hasCompletedInitialScroll = true
    }

    private func updateTimelineBottomProximity(
        bottomY: CGFloat,
        viewportHeight: CGFloat
    ) {
        let isNearBottom = ChatScrollPositionPolicy.isNearBottom(
            bottomY: bottomY,
            viewportHeight: viewportHeight
        )
        guard isNearBottom != isNearTimelineBottom else { return }
        isNearTimelineBottom = isNearBottom
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TimelineBottomYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(iOS)
    /// Reads the real UIScrollView offset without replacing its delegate or
    /// installing another pan recognizer. SwiftUI geometry preferences can stop
    /// updating after a programmatic ScrollViewReader jump on some iOS releases.
    private struct ChatScrollMetricsObserver: UIViewRepresentable {
        let identity: String
        let onNearBottomChange: (Bool) -> Void

        init(identity: String, onNearBottomChange: @escaping (Bool) -> Void) {
            self.identity = identity
            self.onNearBottomChange = onNearBottomChange
        }

        func makeUIView(context: Context) -> ObserverView {
            let view = ObserverView(frame: .zero)
            view.identity = identity
            view.onNearBottomChange = onNearBottomChange
            return view
        }

        func updateUIView(_ uiView: ObserverView, context: Context) {
            uiView.onNearBottomChange = onNearBottomChange
            if uiView.identity != identity {
                uiView.identity = identity
                uiView.resetReportedState()
            }
            uiView.attachToAncestorScrollViewIfNeeded()
        }

        static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) {
            uiView.detach()
        }

        final class ObserverView: UIView {
            var identity = ""
            var onNearBottomChange: ((Bool) -> Void)?

            private weak var observedScrollView: UIScrollView?
            private var observations: [NSKeyValueObservation] = []
            private var lastNearBottom: Bool?
            private var attachmentScheduled = false
            private var metricsReportScheduled = false

            override init(frame: CGRect) {
                super.init(frame: frame)
                isUserInteractionEnabled = false
                backgroundColor = .clear
            }

            required init?(coder: NSCoder) {
                nil
            }

            override func didMoveToWindow() {
                super.didMoveToWindow()
                attachToAncestorScrollViewIfNeeded()
            }

            override func didMoveToSuperview() {
                super.didMoveToSuperview()
                attachToAncestorScrollViewIfNeeded()
            }

            func attachToAncestorScrollViewIfNeeded() {
                guard window != nil,
                    !attachmentScheduled
                else { return }
                attachmentScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.attachmentScheduled = false
                    var ancestor = self.superview
                    while let view = ancestor, !(view is UIScrollView) {
                        ancestor = view.superview
                    }
                    guard let scrollView = ancestor as? UIScrollView else {
                        self.detach()
                        return
                    }
                    self.observe(scrollView)
                }
            }

            func resetReportedState() {
                lastNearBottom = nil
                scheduleMetricsReport()
            }

            func detach() {
                observations.forEach { $0.invalidate() }
                observations.removeAll(keepingCapacity: false)
                observedScrollView = nil
                metricsReportScheduled = false
            }

            private func observe(_ scrollView: UIScrollView) {
                guard observedScrollView !== scrollView else { return }
                detach()
                observedScrollView = scrollView
                observations = [
                    scrollView.observe(
                        \.contentOffset,
                        options: [.initial, .new]
                    ) {
                        [weak self] _, _ in
                        self?.scheduleMetricsReport()
                    },
                    scrollView.observe(\.contentSize, options: [.new]) {
                        [weak self] _, _ in
                        self?.scheduleMetricsReport()
                    },
                    scrollView.observe(\.bounds, options: [.new]) {
                        [weak self] _, _ in
                        self?.scheduleMetricsReport()
                    },
                ]
            }

            private func scheduleMetricsReport() {
                guard !metricsReportScheduled else { return }
                metricsReportScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.metricsReportScheduled = false
                    self.reportMetricsNow()
                }
            }

            private func reportMetricsNow() {
                guard let scrollView = observedScrollView else { return }
                let maximumOffsetY = max(
                    -scrollView.adjustedContentInset.top,
                    scrollView.contentSize.height
                        - scrollView.bounds.height
                        + scrollView.adjustedContentInset.bottom
                )
                let distance = maximumOffsetY - scrollView.contentOffset.y
                let isNearBottom = ChatScrollPositionPolicy.isNearBottom(
                    distanceFromBottom: distance
                )
                guard lastNearBottom != isNearBottom else { return }
                lastNearBottom = isNearBottom
                onNearBottomChange?(isNearBottom)
            }
        }
    }
#endif

enum ComposerRecordingGestureResolution: Equatable {
    case continueRecording
    case cancel
    case lock
}

struct ComposerRecordingGesturePolicy {
    static let cancelDistance: CGFloat = 92
    static let lockDistance: CGFloat = 78
    static let cancelHintFadeDistance: CGFloat = 150
    static let maximumCancelHintFade: CGFloat = 0.72
    static let longPressDelayNanoseconds: UInt64 = 240_000_000
    static let minimumLongPressDuration: TimeInterval = 0.22

    static func resolution(for translation: CGSize)
        -> ComposerRecordingGestureResolution
    {
        let cancelProgress = max(0, -translation.width) / cancelDistance
        let lockProgress = max(0, -translation.height) / lockDistance
        if cancelProgress >= 1, cancelProgress >= lockProgress {
            return .cancel
        }
        if lockProgress >= 1 {
            return .lock
        }
        return .continueRecording
    }

    static func cancelHintOpacity(for translation: CGSize) -> Double {
        let leftwardDistance = max(CGFloat.zero, -translation.width)
        let fadeAmount = min(
            maximumCancelHintFade,
            leftwardDistance / cancelHintFadeDistance
        )
        return Double(CGFloat(1) - fadeAmount)
    }

    static func isLongPress(elapsed: TimeInterval) -> Bool {
        elapsed >= minimumLongPressDuration
    }
}

private enum ComposerCaptureMode: Equatable {
    case voice

    var systemImage: String {
        "mic.fill"
    }

    var recordingAccessibilityLabel: String {
        "Запись голосового сообщения"
    }

    var idleAccessibilityLabel: String {
        "Удерживайте для голосового сообщения"
    }
}

@MainActor
private struct TelegramRecordButton: View {
    let mode: ComposerCaptureMode
    let isRecording: Bool
    let isLocked: Bool
    let isFinalizing: Bool
    let isEnabled: Bool
    let onTap: () -> Void
    let onLongPressBegan: () -> Void
    let onLongPressChanged: (CGSize) -> Void
    let onLongPressEnded: (CGSize) -> Void
    let onLongPressCancelled: () -> Void

    @State private var isPressing = false
    @State private var didBeginLongPress = false
    @State private var pressStartedAt: Date?
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if isFinalizing {
                ProgressView()
                    .controlSize(.small)
                    .tint(iconColor)
            } else {
                Image(systemName: isLocked ? "arrow.up" : mode.systemImage)
                    .font(.system(size: isLocked ? 18 : 20, weight: .bold))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 42, height: 42)
        .scaleEffect(isRecording && !isLocked ? 1.34 : (isPressing ? 1.08 : 1))
        .contentShape(Circle())
        .glassEffect()
        #if os(iOS)
            .overlay {
                ComposerRecordTouchSurface(
                    onBegan: { beginPhysicalPress(at: $0) },
                    onMoved: movePhysicalPress,
                    onEnded: { translation, eventTime in
                        endPhysicalPress(translation, at: eventTime)
                    },
                    onCancelled: cancelPhysicalPress
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }
        #else
            .gesture(recordGesture)
        #endif
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled && !isFinalizing)
        .animation(
            .spring(response: 0.24, dampingFraction: 0.78),
            value: isRecording
        )
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            "Во время записи проведите влево для отмены или вверх для фиксации"
        )
        .onDisappear {
            longPressTask?.cancel()
            longPressTask = nil
            pressStartedAt = nil
        }
    }

    private var iconColor: Color {
        isRecording ? .red : .primary
    }

    private var accessibilityLabel: String {
        if isLocked { return "Отправить записанное сообщение" }
        return isRecording
            ? mode.recordingAccessibilityLabel : mode.idleAccessibilityLabel
    }

    private var recordGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard isEnabled, !isFinalizing else { return }
                if !isPressing {
                    // DragGesture timestamps belong to the physical input
                    // events. Date() here would measure when the main actor
                    // finally handled the event and could turn a real hold
                    // into a tap after a busy MAM batch.
                    beginPhysicalPress(at: value.time)
                }
                if didBeginLongPress {
                    movePhysicalPress(value.translation)
                }
            }
            .onEnded { value in
                endPhysicalPress(value.translation, at: value.time)
            }
    }

    private func beginPhysicalPress(at eventTime: Date) {
        guard isEnabled, !isFinalizing, !isPressing else { return }
        isPressing = true
        didBeginLongPress = false
        pressStartedAt = eventTime
        scheduleLongPress()
    }

    private func movePhysicalPress(_ translation: CGSize) {
        guard didBeginLongPress else { return }
        onLongPressChanged(translation)
    }

    private func endPhysicalPress(_ translation: CGSize, at eventTime: Date) {
        guard isPressing || didBeginLongPress else { return }
        longPressTask?.cancel()
        longPressTask = nil
        let wasLongPress = didBeginLongPress
        let elapsed =
            pressStartedAt.map {
                eventTime.timeIntervalSince($0)
            } ?? 0
        isPressing = false
        didBeginLongPress = false
        pressStartedAt = nil
        if wasLongPress {
            onLongPressEnded(translation)
        } else if ComposerRecordingGesturePolicy.isLongPress(elapsed: elapsed) {
            // If MAM decryption delayed the main actor, the scheduled
            // recognizer callback may arrive after the finger lifts. Recover
            // the physical press duration instead of turning it into a tap.
            onLongPressBegan()
            onLongPressEnded(translation)
        } else {
            onTap()
        }
    }

    private func cancelPhysicalPress() {
        let wasLongPress = didBeginLongPress
        longPressTask?.cancel()
        longPressTask = nil
        isPressing = false
        didBeginLongPress = false
        pressStartedAt = nil
        if wasLongPress {
            // UIKit distinguishes a real touch-up from an interruption (for
            // example an app transition or system gesture). Never translate a
            // cancelled touch into the Telegram-style "release to send" path.
            onLongPressCancelled()
        }
    }

    private func scheduleLongPress() {
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: ComposerRecordingGesturePolicy
                        .longPressDelayNanoseconds
                )
            } catch {
                return
            }
            guard isPressing else { return }
            didBeginLongPress = true
            onLongPressBegan()
        }
    }
}

#if os(iOS)
    /// A raw UIKit touch surface keeps ownership of the physical finger while the
    /// SwiftUI composer swaps its idle controls for the recording preview. A
    /// SwiftUI DragGesture can be cancelled by that hierarchy update and used to
    /// report the cancellation as an early end on some iOS releases.
    @MainActor
    private struct ComposerRecordTouchSurface: UIViewRepresentable {
        let onBegan: (Date) -> Void
        let onMoved: (CGSize) -> Void
        let onEnded: (CGSize, Date) -> Void
        let onCancelled: () -> Void

        func makeUIView(context: Context) -> TouchView {
            let view = TouchView(frame: .zero)
            update(view)
            return view
        }

        func updateUIView(_ uiView: TouchView, context: Context) {
            update(uiView)
        }

        private func update(_ view: TouchView) {
            view.onBegan = onBegan
            view.onMoved = onMoved
            view.onEnded = onEnded
            view.onCancelled = onCancelled
        }

        final class TouchView: UIView {
            var onBegan: ((Date) -> Void)?
            var onMoved: ((CGSize) -> Void)?
            var onEnded: ((CGSize, Date) -> Void)?
            var onCancelled: (() -> Void)?

            private var activeTouch: UITouch?
            private var origin = CGPoint.zero

            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = .clear
                isOpaque = false
                isExclusiveTouch = true
                isMultipleTouchEnabled = false
                isAccessibilityElement = false
            }

            required init?(coder: NSCoder) {
                nil
            }

            override func touchesBegan(
                _ touches: Set<UITouch>,
                with event: UIEvent?
            ) {
                guard activeTouch == nil, let touch = touches.first else {
                    return
                }
                activeTouch = touch
                origin = touch.location(in: window)
                onBegan?(eventDate(for: touch))
            }

            override func touchesMoved(
                _ touches: Set<UITouch>,
                with event: UIEvent?
            ) {
                guard let touch = trackedTouch(in: touches) else { return }
                onMoved?(translation(for: touch))
            }

            override func touchesEnded(
                _ touches: Set<UITouch>,
                with event: UIEvent?
            ) {
                guard let touch = trackedTouch(in: touches) else { return }
                let translation = translation(for: touch)
                let date = eventDate(for: touch)
                activeTouch = nil
                onEnded?(translation, date)
            }

            override func touchesCancelled(
                _ touches: Set<UITouch>,
                with event: UIEvent?
            ) {
                guard trackedTouch(in: touches) != nil else { return }
                activeTouch = nil
                onCancelled?()
            }

            private func trackedTouch(in touches: Set<UITouch>) -> UITouch? {
                guard let activeTouch else { return nil }
                return touches.first(where: { $0 === activeTouch })
            }

            private func translation(for touch: UITouch) -> CGSize {
                let location = touch.location(in: window)
                return CGSize(
                    width: location.x - origin.x,
                    height: location.y - origin.y
                )
            }

            private func eventDate(for touch: UITouch) -> Date {
                Date().addingTimeInterval(
                    touch.timestamp - ProcessInfo.processInfo.systemUptime
                )
            }
        }
    }
#endif

private struct ReplyThreadSelection: Equatable {
    let rootID: String
    let selectedReplyID: String
}

private struct MessageForwardSelection: Identifiable {
    let id = UUID()
    let messages: [ChatMessage]
}

private enum FileImportMode {
    case files
    case audio

    var allowedContentTypes: [UTType] {
        switch self {
        case .files: return [.item]
        case .audio: return [.audio]
        }
    }

    var preferredKind: ChatMessage.Kind? {
        switch self {
        case .files: return nil
        case .audio: return .audio
        }
    }
}

private enum MediaPickerError: LocalizedError {
    case cannotReadSelection

    var errorDescription: String? {
        "Не удалось прочитать выбранное фото или видео. Попробуйте сохранить его в «Файлы» и отправить оттуда."
    }
}

private struct MessageDestructiveAction: Identifiable {
    enum Kind: Equatable {
        case localDelete
        case retract
    }

    let kind: Kind
    let messages: [ChatMessage]

    var id: String {
        let messageIDs = messages.map(\.clientID).sorted().joined(
            separator: "-"
        )
        return "\(kind == .localDelete ? "local" : "retract")-\(messageIDs)"
    }

    var title: String {
        let plural = messages.count > 1
        switch kind {
        case .localDelete:
            return plural
                ? "Удалить выбранные сообщения у себя?"
                : "Удалить сообщение у себя?"
        case .retract:
            return plural
                ? "Удалить выбранные сообщения у всех?"
                : "Удалить сообщение у всех?"
        }
    }

    var explanation: String {
        switch kind {
        case .localDelete:
            return messages.count > 1
                ? "\(messageCountText) исчезнут только из истории Luma на этом устройстве."
                : "Сообщение исчезнет только из истории Luma на этом устройстве."
        case .retract:
            return
                "Luma отправит XMPP-запрос retract для \(messageCountText). Сервер и другие клиенты могут не удалить уже полученные копии."
        }
    }

    var confirmationTitle: String {
        kind == .localDelete ? "Удалить у меня" : "Удалить у всех"
    }

    private var messageCountText: String {
        let count = messages.count
        let remainder100 = count % 100
        let remainder10 = count % 10
        let word: String
        if (11...14).contains(remainder100) {
            word = "сообщений"
        } else if remainder10 == 1 {
            word = "сообщение"
        } else if (2...4).contains(remainder10) {
            word = "сообщения"
        } else {
            word = "сообщений"
        }
        return "\(count) \(word)"
    }
}

private struct PickedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { photo in
            SentTransferredFile(photo.url)
        } importing: { received in
            PickedPhoto(
                url: try copyPickedMediaFile(
                    received.file,
                    fallbackExtension: "jpg"
                )
            )
        }
    }
}

private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            PickedVideo(
                url: try copyPickedMediaFile(
                    received.file,
                    fallbackExtension: "mov"
                )
            )
        }
    }
}

private func copyPickedMediaFile(_ source: URL, fallbackExtension: String)
    throws -> URL
{
    let fileManager = FileManager.default
    let rootDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("LumaPhotoPicker", isDirectory: true)
    let selectionDirectory =
        rootDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
        at: selectionDirectory,
        withIntermediateDirectories: true
    )

    let values = try? source.resourceValues(forKeys: [
        .nameKey, .contentTypeKey,
    ])
    let fileExtension =
        source.pathExtension.isEmpty
        ? (values?.contentType?.preferredFilenameExtension ?? fallbackExtension)
        : source.pathExtension
    var filename = values?.name ?? source.lastPathComponent
    if filename.isEmpty {
        filename = "media.\(fileExtension)"
    } else if URL(fileURLWithPath: filename).pathExtension.isEmpty {
        filename += ".\(fileExtension)"
    }
    let forbidden = CharacterSet(charactersIn: "/\\:")
        .union(.controlCharacters)
    filename = filename.components(separatedBy: forbidden).joined(
        separator: "_"
    )
    let destination = selectionDirectory.appendingPathComponent(filename)
    let accessed = source.startAccessingSecurityScopedResource()
    defer {
        if accessed { source.stopAccessingSecurityScopedResource() }
    }

    var coordinatedError: NSError?
    var copyResult: Result<URL, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(
        readingItemAt: source,
        options: [],
        error: &coordinatedError
    ) { coordinatedURL in
        copyResult = Result {
            do {
                try fileManager.copyItem(at: coordinatedURL, to: destination)
                let stagedValues = try destination.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                )
                guard stagedValues.isRegularFile == true,
                    fileManager.isReadableFile(atPath: destination.path)
                else {
                    throw MediaFileIOError.unreadableFile(filename)
                }
                guard (stagedValues.fileSize ?? 0) > 0 else {
                    throw MediaFileIOError.emptyFile(filename)
                }
                return destination
            } catch {
                try? fileManager.removeItem(at: selectionDirectory)
                throw error
            }
        }
    }
    if let copyResult {
        return try copyResult.get()
    }
    try? fileManager.removeItem(at: selectionDirectory)
    throw MediaFileIOError.coordinatedReadFailed(
        coordinatedError?.localizedDescription ?? "неизвестная ошибка"
    )
}

private func writePickedImageData(_ data: Data) throws -> URL {
    guard !data.isEmpty else {
        throw MediaFileIOError.emptyFile("Фото")
    }
    let contentType: UTType?
    if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
        let typeIdentifier = CGImageSourceGetType(imageSource)
    {
        contentType = UTType(typeIdentifier as String)
    } else {
        contentType = nil
    }
    let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LumaPhotoPicker", isDirectory: true)
    let selectionDirectory =
        rootDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: selectionDirectory,
        withIntermediateDirectories: true
    )
    let destination = selectionDirectory.appendingPathComponent(
        "photo.\(fileExtension)"
    )
    do {
        try data.write(to: destination, options: [.atomic])
        return destination
    } catch {
        try? FileManager.default.removeItem(at: selectionDirectory)
        throw error
    }
}

#Preview {
    PreviewSupport.chatPreview()
}

/// Extracted chat navigation title: avatar, display name and the transient
/// «печатает…» line. Kept as its own view so its layout can be previewed on
/// its own without opening a full chat.
private struct ChatNavigationTitle: View {
    @ObservedObject var model: AppModel
    let conversation: Conversation

    private var liveConversation: Conversation {
        model.conversations.first(where: { $0.jid == conversation.jid })
            ?? conversation
    }

    var body: some View {
        Button {
        } label: {
            titleContent
        }
        .buttonStyle(.plain)
    }

    private var titleContent: some View {
        HStack {
            AvatarView(
                conversation: liveConversation,
                imageData: model.avatarData(for: conversation.jid),
                size: 25
            )
            .padding(4)
            VStack(spacing: 0) {
                Text(liveConversation.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let typingText = model.typingText(for: liveConversation) {
                    Text(typingText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.top, 5)
            .padding(.bottom, 5)
            .padding(.trailing, 15)
            .animation(
                .easeInOut(duration: 0.16),
                value: model.typingText(for: liveConversation)
            )
            .accessibilityElement(children: .combine)
        }
        #if os(iOS)
            .glassEffect()
        #endif
    }
}

#Preview("Заголовок чата") {
    ChatNavigationTitle(
        model: PreviewSupport.model,
        conversation: PreviewSupport.conversation(
            displayName: "Алиса",
            isOnline: true
        )
    )
    .padding()
}
