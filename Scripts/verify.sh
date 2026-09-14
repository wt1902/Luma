#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required=(
  project.yml
  Sources/App/LumaApp.swift
  Sources/Shared/XMPP/XMPPService.swift
  Sources/Shared/XMPP/LumaCallEngine.swift
  Sources/Shared/XMPP/LumaRoomStore.swift
  Sources/Shared/XMPP/LumaOMEMOStore.swift
  Sources/Shared/Models/MediaMetadata.swift
  Sources/Shared/Models/AttachmentDraft.swift
  Sources/Shared/Models/MediaSendActivityTracker.swift
  Sources/Shared/Models/ArchiveSyncCheckpoint.swift
  Sources/Shared/Models/ArchiveSyncPagination.swift
  Sources/Shared/Models/ArchiveSyncRecoveryPolicy.swift
  Sources/Shared/Models/ArchiveSyncWorkBudget.swift
  Sources/Shared/Models/ArchiveMessageBatchPolicy.swift
  Sources/Shared/Models/OlderHistoryScrollPolicy.swift
  Sources/Shared/Models/ChatScrollPositionPolicy.swift
  Sources/Shared/Models/ChatTimelineEntry.swift
  Sources/Shared/Models/ChatTypingPolicy.swift
  Sources/Shared/Models/MessageReaction.swift
  Sources/Shared/Models/MediaPickerSelectionPolicy.swift
  Sources/Shared/Models/VideoNoteRecordingCompletionPolicy.swift
  Sources/Shared/Models/VideoNoteRotationPolicy.swift
  Sources/Shared/Models/VideoNoteRecordingLifecycle.swift
  Sources/Shared/Models/MessageReplySwipePolicy.swift
  Sources/Shared/Models/MessageReplyFallback.swift
  Sources/Shared/Models/CallSnapshot.swift
  Sources/Shared/Models/NotificationPolicy.swift
  Sources/Shared/Services/AudioMessageRecorder.swift
  Sources/Shared/Services/MediaPlaybackCoordinator.swift
  Sources/Shared/Services/MediaPreviewProcessor.swift
  Sources/Shared/Services/MediaFileIO.swift
  Sources/Shared/Services/ChatMediaImageCache.swift
  Sources/Shared/Services/LocationProvider.swift
  Sources/Shared/Services/VideoNoteRecorder.swift
  Sources/Shared/UI/SystemPhotoCameraView.swift
  Sources/Shared/UI/VideoNoteCaptureView.swift
  Sources/Shared/UI/CallView.swift
  Sources/Shared/UI/Components/AudioMessagePlayer.swift
  Sources/Shared/UI/Components/BubbleShapes.swift
  Sources/Shared/UI/Components/InlineVideoPlayer.swift
  Sources/Shared/UI/Components/VideoAttachmentPreview.swift
  Sources/Shared/UI/Components/VideoNotePreview.swift
  Sources/Shared/UI/Components/PhotoAttachmentPreview.swift
  Sources/Shared/UI/Components/ReplyThreadOverlay.swift
  Sources/Shared/UI/Components/MediaViewer.swift
  Sources/Shared/UI/Components/LocationMessagePreview.swift
  Sources/Shared/UI/Components/RTCVideoRendererView.swift
  Sources/Shared/UI/LocationPickerView.swift
  Sources/Shared/UI/ForwardMessageView.swift
  Sources/Shared/UI/NewGroupView.swift
  Sources/Shared/UI/GroupInfoView.swift
  Sources/Shared/UI/AttachmentPreviewView.swift
  Sources/Watch/LumaWatchApp.swift
  Sources/Watch/WatchSessionModel.swift
  Sources/Watch/WatchViews.swift
  Sources/Watch/WatchVoiceRecorder.swift
  Tests/CallSDPOrderingTests.swift
  Tests/CallSnapshotTests.swift
  Tests/NotificationPolicyTests.swift
  Tests/MediaSendActivityTrackerTests.swift
  Tests/ComposerRecordingGestureTests.swift
  Tests/MediaViewerDismissGestureTests.swift
  Tests/ArchiveSyncCheckpointTests.swift
  Tests/ArchiveSyncPaginationTests.swift
  Tests/OlderHistoryScrollPolicyTests.swift
  Tests/ArchiveSyncRecoveryPolicyTests.swift
  Tests/ArchiveSyncWorkBudgetTests.swift
  Tests/ArchiveMessageBatchPolicyTests.swift
  Tests/ChatScrollPositionPolicyTests.swift
  Tests/ChatTimelineEntryTests.swift
  Tests/ChatTypingPolicyTests.swift
  Tests/MessageReactionTests.swift
  Tests/MediaFileIOTests.swift
  Tests/MediaPickerSelectionPolicyTests.swift
  Tests/VideoNoteRecordingCompletionPolicyTests.swift
  Tests/VideoNoteRecordingLifecycleTests.swift
  Tests/VideoNoteRotationPolicyTests.swift
  Tests/VideoNoteStopPolicyTests.swift
  Tests/MessageReplySwipeTests.swift
  Tests/WatchVoiceMessageTests.swift
  Tests/ArchiveStoreTests.swift
  Tests/SASLprepTests.swift
  Tests/SaslFailureMessageTests.swift
  Tests/MediaPreviewProcessorVideoTests.swift
  Tests/SCRAMSHA512Tests.swift
  Tests/AppLockPolicyTests.swift
  Tests/CallHistorySyncTests.swift
  Tests/ReadStateSyncTests.swift
  Tests/ChatMessageDeliveryTests.swift
  UITests/TimelineUITests.swift
  Sources/Shared/XMPP/LumaScramSha512Mechanism.swift
  Sources/Shared/XMPP/CallHistorySync.swift
  Sources/Shared/XMPP/ReadStateSync.swift
  Sources/Shared/Security/AppLockVault.swift
  Sources/Shared/Models/AppLockPolicy.swift
  Sources/Shared/UI/AppLockView.swift
  Sources/Shared/XMPP/SASLprep.swift
  Sources/Shared/XMPP/LumaSaslFailureModule.swift
  Sources/Shared/XMPP/SaslFailureMessage.swift
  Sources/Shared/Models/ChatMessage.swift
  Sources/Shared/Models/Conversation.swift
  Sources/Shared/Persistence/ArchiveStore.swift
  Sources/Shared/Persistence/ArchiveMetadataRecord.swift
  Sources/Shared/Persistence/LegacyArchiveImporter.swift
  Brand/LumaIcon-1024.png
  Resources/AppAssets.xcassets/AppIcon.appiconset/Contents.json
  Regenerate-Luma-Project.command
  Scripts/regenerate-project.command
)

for file in "${required[@]}"; do
  test -f "$file" || { echo "Missing $file"; exit 1; }
done

test "$(grep -c 'path: Resources/AppAssets.xcassets' project.yml)" -eq 3 || {
  echo "Every app target must reference Resources/AppAssets.xcassets"
  exit 1
}
test "$(grep -c 'ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon' project.yml)" -eq 3 || {
  echo "Every app target must compile the AppIcon set"
  exit 1
}

if grep -q 'type: application.watchapp2' project.yml; then
  echo "The legacy WatchKit container cannot compile single-target SwiftUI watch sources"
  exit 1
fi
grep -A8 '^  LumaWatch:' project.yml | grep -q 'type: application$' || {
  echo "LumaWatch must be a modern single-target watchOS application"
  exit 1
}
test "$(grep -c 'PRODUCT_NAME: LumaWatch' project.yml)" -eq 1 || {
  echo "The watch product must use its own bundle filename"
  exit 1
}
grep -q 'TARGETED_DEVICE_FAMILY: "4"' project.yml || {
  echo "The watch target must select the watch device family"
  exit 1
}
grep -q '<key>NSMicrophoneUsageDescription</key>' Config/LumaWatch-Info.plist || {
  echo "The watch app microphone usage description is missing"
  exit 1
}
grep -q 'session.transferFile(fileURL, metadata: metadata)' Sources/Watch/WatchSessionModel.swift || {
  echo "Background Apple Watch voice transfer is missing"
  exit 1
}
grep -q 'voiceTransferCacheKey' Sources/Watch/WatchSessionModel.swift || {
  echo "Apple Watch transfer acknowledgements must survive app restarts"
  exit 1
}
grep -q 'persistVoiceMessage(message)' Sources/Shared/Services/PhoneWatchBridge.swift || {
  echo "Received Apple Watch voice files must survive iPhone app restarts"
  exit 1
}
grep -q 'kind: \.voice' Sources/Shared/Models/AppModel.swift || {
  echo "Apple Watch recordings are not connected to the voice media pipeline"
  exit 1
}

test "$(grep -c -- '- package: WebRTC' project.yml)" -eq 2 || {
  echo "WebRTC must be linked to the iOS/iPadOS and macOS targets"
  exit 1
}

if grep -R -q 'ChatBubbleTailShape\|maximumMediaSize\|25 МБ' Sources/Shared; then
  echo "Legacy bubble tails or the old client attachment limit are still present"
  exit 1
fi

if grep -q 'DtlsSrtpKeyAgreement\|continualGatheringPolicy\|iceCandidatePoolSize = 5\|OfferToReceive' \
  Sources/Shared/XMPP/LumaCallEngine.swift; then
  echo "Legacy WebRTC peer-connection configuration is still present"
  exit 1
fi

grep -q 'attempts.append(("public STUN"' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "WebRTC public STUN fallback is missing"
  exit 1
}
grep -q 'attempts.append(("host candidates", \[\]))' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "WebRTC host-candidate fallback is missing"
  exit 1
}
grep -q 'CallCandidateDispatchGate.canSend' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "Jingle ICE candidate signaling gate is missing"
  exit 1
}
grep -q 'session.pinPeerResource(jid)' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "Jingle full-resource pinning is missing"
  exit 1
}
grep -q 'return (jid: jmiJID, usesMessageInitiation: true)' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "JMI must target an advertised full JID"
  exit 1
}
grep -q 'CallSDPOrdering.answerIndices' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "Outgoing video answer ordering guard is missing"
  exit 1
}
grep -q 'CallSDPNormalization.martinParseInput' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "WebRTC-to-Martin SDP terminator normalization is missing"
  exit 1
}
grep -q 'CallSDPCompatibility.repairLocalFIDMSIDs' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "Outgoing video FID/MSID compatibility repair is missing"
  exit 1
}
grep -q 'historyHandler' Sources/Shared/XMPP/LumaCallEngine.swift || {
  echo "Call completion history bridge is missing"
  exit 1
}
grep -q 'callHistoryContent' Sources/Shared/UI/Components/MessageBubble.swift || {
  echo "Call history message card is missing"
  exit 1
}
grep -q 'defaultScrollAnchor(.bottom)' Sources/Shared/UI/ChatView.swift || {
  echo "Chat timeline must open at the latest message"
  exit 1
}
grep -q 'ArchiveSyncPagination' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM synchronization must validate every RSM cursor"
  exit 1
}
grep -q 'guard activeQueryID == queryID else' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM results must be restricted to the active query ID"
  exit 1
}
grep -q 'allowedSources.contains(source.stringValue.lowercased())' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM results must be restricted to the account archive source"
  exit 1
}
grep -q 'archiveStanzaInbox.append' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Raw MAM stanzas must enter the bounded parser-queue inbox"
  exit 1
}
if sed -n '/archivedMessagesPublisher/,/store(in: &cancellables)/p' \
  Sources/Shared/XMPP/XMPPService.swift | grep -q 'receive(on: DispatchQueue.main)'; then
  echo "Every raw MAM stanza must not be dispatched onto the main queue"
  exit 1
fi
grep -q 'RSM.Query(lastItems: archiveBootstrapMessageLimit)' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Fresh MAM bootstrap must request the latest bounded page"
  exit 1
}
grep -q 'archiveWorkBudget.recordCompletedPage' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Incremental MAM passes must have a finite foreground work budget"
  exit 1
}
grep -q 'OlderHistoryScrollPolicy.page(' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Interactive history paging must advance via the server's RSM first cursor"
  exit 1
}
if grep -q 'scheduleArchiveRestart\|restartDelayNanoseconds' Sources/Shared/XMPP/XMPPService.swift; then
  echo "Failed MAM queries must not restart themselves indefinitely"
  exit 1
fi
grep -q 'archiveRetrySuppressedUntilActivation = true' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM failures must remain paused until a later app activation"
  exit 1
}
grep -q 'pauseArchiveSync(client: client)' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM must stop cleanly while the app or camera is inactive"
  exit 1
}
grep -q 'isArchiveSyncing = false' Sources/Shared/Models/AppModel.swift || {
  echo "A transport disconnect must clear a stale MAM indicator"
  exit 1
}
grep -q 'case archiveBatch(\[ArchiveMutation\])' Sources/Shared/XMPP/XMPPService.swift || {
  echo "A decoded MAM pass must be exposed as one atomic mutation batch"
  exit 1
}
grep -q 'applyArchiveBatch(mutations)' Sources/Shared/Models/AppModel.swift || {
  echo "MAM mutations must be applied atomically before publishing SwiftUI state"
  exit 1
}
grep -q 'decodeSliceSize = 8' Sources/Shared/Models/ArchiveMessageBatchPolicy.swift || {
  echo "MAM decoding must stay batched in small per-slice groups"
  exit 1
}
grep -q 'lastSuccessfulMAMCursor' Sources/Shared/Persistence/ArchiveStore.swift || {
  echo "The durable archive store must persist the XEP-0313 UID cursor"
  exit 1
}
if test -f Sources/Shared/Persistence/ChatArchive.swift; then
  echo "The legacy JSON ChatArchive actor must stay removed"
  exit 1
fi
grep -q '@Query' Sources/Shared/UI/MainTabView.swift || {
  echo "Chat list must be SwiftData @Query-driven"
  exit 1
}
grep -q 'NavigationSplitView' Sources/Shared/UI/MainTabView.swift || {
  echo "macOS must keep the Telegram Desktop-style split view"
  exit 1
}
grep -q 'SearchField' Sources/Shared/UI/MainTabView.swift || {
  echo "Search fields must stay inline above the lists"
  exit 1
}
grep -q 'TabView(selection:' Sources/Shared/UI/MainTabView.swift || {
  echo "The iOS main screen must use the native TabView tab bar"
  exit 1
}
grep -q 'toolbar(.hidden, for: .tabBar)' Sources/Shared/UI/ChatView.swift || {
  echo "The tab bar must be hidden inside a pushed chat"
  exit 1
}
grep -q 'PhoneWatchMessageData' Sources/Shared/Services/PhoneWatchBridge.swift || {
  echo "The watch bridge must snapshot SwiftData models on the main actor"
  exit 1
}
grep -q 'urn:xmpp:omemo:2' Sources/Shared/XMPP/LumaOMEMO2Module.swift || {
  echo "OMEMO 2 must be implemented by the app-level module"
  exit 1
}
grep -q 'decodeOmemo2OffMain' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Incoming messages must route OMEMO 2 payloads to the OMEMO 2 module"
  exit 1
}
grep -q 'XCLocalSwiftPackageReference "ThirdParty/MartinOMEMO"' Luma.xcodeproj/project.pbxproj || {
  echo "The vendored MartinOMEMO package must stay linked in the generated project (run make project)"
  exit 1
}
grep -q '@Query' Sources/Shared/UI/ChatView.swift || {
  echo "Chat timeline must be SwiftData @Query-driven"
  exit 1
}
grep -q '@Query' Sources/Shared/UI/ForwardMessageView.swift || {
  echo "Forward destination list must be SwiftData @Query-driven"
  exit 1
}
grep -q '\.modelContext' Sources/Shared/UI/RootView.swift || {
  echo "RootView must inject the SwiftData ModelContext"
  exit 1
}
grep -q 'modelContext.delete(message)' Sources/Shared/Models/AppModel.swift || {
  echo "Local message deletion must remove the SwiftData row"
  exit 1
}
grep -q 'purgeLocallyDeletedMessages' Sources/Shared/Persistence/ArchiveStore.swift || {
  echo "ArchiveStore must purge locally deleted rows for @Query views"
  exit 1
}
grep -q 'completeUntilFirstUserAuthentication' Sources/Shared/Persistence/ArchiveStore.swift || {
  echo "The SwiftData store must keep the data protection attribute"
  exit 1
}
grep -q 'SASLprep' Sources/Shared/XMPP/XMPPService.swift || {
  echo "SCRAM passwords must be RFC 4013 (SASLprep) normalized"
  exit 1
}
grep -q 'LumaSaslFailureModule' Sources/Shared/XMPP/XMPPService.swift || {
  echo "The raw SASL failure condition must be captured for the UI"
  exit 1
}
grep -q 'Сервер отклонил имя пользователя или пароль' Sources/Shared/XMPP/SaslFailureMessage.swift || {
  echo "SASL failures must produce an actionable Russian message"
  exit 1
}
grep -q "doesn't match the one we calculated" Sources/Shared/XMPP/SaslFailureMessage.swift || {
  echo "Prosody SCRAM proof mismatches must be explained in Russian"
  exit 1
}
grep -q 'passwordVisible' Sources/Shared/UI/LoginView.swift || {
  echo "The login screen must let the user verify the typed password"
  exit 1
}
grep -q 'SCRAM-SHA-512' Sources/Shared/XMPP/LumaScramSha512Mechanism.swift || {
  echo "The SCRAM-SHA-512 mechanism must be available"
  exit 1
}
grep -q 'LumaScramSha512Mechanism(channelBindingStore: channelBindingStore)' Sources/Shared/XMPP/XMPPService.swift || {
  echo "SCRAM-SHA-512 must be registered ahead of Martin's mechanisms"
  exit 1
}
grep -q 'NSFaceIDUsageDescription' project.yml || {
  echo "Biometric unlock must declare its usage description"
  exit 1
}
grep -q 'unlockWithBiometrics' Sources/Shared/Models/AppModel.swift || {
  echo "The app lock must support biometric unlock"
  exit 1
}
grep -q 'AppLockView' Sources/Shared/UI/RootView.swift || {
  echo "The lock screen must cover every app layer"
  exit 1
}
grep -q 'Блокировка приложения' Sources/Shared/UI/SettingsView.swift || {
  echo "Settings must offer the app lock toggle"
  exit 1
}
grep -q 'https://luma.chat/call-history' Sources/Shared/XMPP/CallHistorySync.swift || {
  echo "Call history must sync through its service namespace"
  exit 1
}
grep -q 'syncCallHistory' Sources/Shared/Models/AppModel.swift || {
  echo "Call cards must be synced to the user's other devices"
  exit 1
}
grep -q 'CallHistorySync.envelope' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Incoming call-history payloads must be intercepted"
  exit 1
}
grep -q 'https://luma.chat/read-marker' Sources/Shared/XMPP/ReadStateSync.swift || {
  echo "Read state must sync through its service namespace"
  exit 1
}
grep -q 'ReadStateSync.envelope' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Incoming read-marker payloads must be intercepted"
  exit 1
}
grep -q 'syncReadState' Sources/Shared/Models/AppModel.swift || {
  echo "Read receipts must be synced to the user's other devices"
  exit 1
}
grep -q 'markersPublisher' Sources/Shared/XMPP/XMPPService.swift || {
  echo "XEP-0333 displayed markers must mark messages as read"
  exit 1
}
grep -q 'case read(conversationJID' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Read receipts must reference the conversation"
  exit 1
}
grep -q 'merged(with: message.delivery)' Sources/Shared/Models/AppModel.swift || {
  echo "MAM replays must not downgrade delivered or read state"
  exit 1
}
grep -q 'func deleteGroupChat' Sources/Shared/Models/AppModel.swift || {
  echo "Group chats must support local deletion"
  exit 1
}
grep -q 'deletedGroupChatJIDs' Sources/Shared/Models/AppModel.swift || {
  echo "Deleted group chats must stay suppressed for the session"
  exit 1
}
grep -q 'Удалить чат' Sources/Shared/UI/GroupInfoView.swift || {
  echo "Group info must offer deleting the chat"
  exit 1
}
grep -q 'pendingGroupDeletion' Sources/Shared/UI/MainTabView.swift || {
  echo "Chat list must offer deleting group chats"
  exit 1
}
grep -q 'pickerResetToken' Sources/Shared/UI/ChatView.swift || {
  echo "The photo picker must be recreated after each selection"
  exit 1
}
grep -q 'let items = pickedMediaItems' Sources/Shared/UI/ChatView.swift || {
  echo "Gallery staging must run on picker dismissal only"
  exit 1
}
grep -q 'connectionStatus == .connected' Sources/Shared/Models/AppModel.swift || {
  echo "Older-history loads must skip silently while disconnected"
  exit 1
}
grep -q 'removeSessionWithOwnDeviceOnce' Sources/Shared/XMPP/LumaOMEMOStore.swift || {
  echo "The self-session purge must be a one-time migration"
  exit 1
}
grep -q 'ensureSelfSession' Sources/Shared/XMPP/XMPPService.swift || {
  echo "A missing self-session must be rebuilt from the own bundle"
  exit 1
}
grep -q 'urn:xmpp:omemo:2' Sources/Shared/XMPP/XMPPService.swift || {
  echo "OMEMO 2 payloads must be shown as undecryptable, not empty"
  exit 1
}
grep -q 'biometricUnlockAvailable' Sources/Shared/Models/AppModel.swift || {
  echo "Biometric availability must be cached off the view body"
  exit 1
}
grep -q 'Звонки' Sources/Shared/UI/MainTabView.swift || {
  echo "The main screen must offer the Calls tab"
  exit 1
}
grep -q 'Настройки' Sources/Shared/UI/MainTabView.swift || {
  echo "The main screen must offer the Settings tab"
  exit 1
}
grep -q 'case .background:' Sources/App/LumaApp.swift || {
  echo "The app lock must trigger on background only, not on inactive"
  exit 1
}
grep -q 'onDismissRequest' Sources/Shared/UI/SystemPhotoCameraView.swift || {
  echo "The camera picker must request dismissal before background preparation"
  exit 1
}
grep -q 'onDismissRequest' Sources/Shared/UI/ChatView.swift || {
  echo "The camera cover must dismiss through the SwiftUI binding"
  exit 1
}
grep -q 'moveItem(at: sourceURL' Sources/Shared/UI/SystemPhotoCameraView.swift || {
  echo "The picker movie must be claimed synchronously before dismissal cleanup"
  exit 1
}
grep -q 'video-preview' Sources/Shared/UI/ChatView.swift || {
  echo "The camera video path must log diagnostics"
  exit 1
}
grep -q 'ArchiveSyncCursorPolicy.requestPosition' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM reconnects must prefer the durable archive UID over timestamps"
  exit 1
}
grep -q 'shouldFallbackFromStoredCursor' Sources/Shared/XMPP/XMPPService.swift || {
  echo "An expired archive UID must have one bounded timestamp fallback"
  exit 1
}
grep -q 'await Task.yield()' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM decoding must yield to scrolling and camera callbacks"
  exit 1
}
grep -q 'pageApplyTimeoutNanoseconds' Sources/Shared/XMPP/XMPPService.swift || {
  echo "MAM page application must have a finite watchdog"
  exit 1
}
grep -q 'setArchiveSyncIndicator(false)' Sources/Shared/XMPP/XMPPService.swift || {
  echo "Every MAM terminal path must be able to clear the indicator"
  exit 1
}
grep -q 'selectedMessagesCacheConversationID' Sources/Shared/Models/AppModel.swift || {
  echo "Chat timeline sorting must not repeat on every recording timer tick"
  exit 1
}
if sed -n '/private func upsertMessage(/,/private func updateMessage/p' \
  Sources/Shared/Models/AppModel.swift | grep -q 'messages.firstIndex'; then
  echo "MAM insertion must use the indexed message lookup"
  exit 1
fi
grep -q 'incrementUnread: envelope.isArchived ? false : nil' Sources/Shared/Models/AppModel.swift || {
  echo "Historical MAM replay must not inflate unread counters"
  exit 1
}
grep -q 'persistenceQueue.async' Sources/Shared/XMPP/LumaOMEMOStore.swift || {
  echo "OMEMO state persistence must not block MAM decryption on the main actor"
  exit 1
}
grep -q 'persistWhenQuiet' Sources/Shared/XMPP/LumaOMEMOStore.swift || {
  echo "OMEMO persistence must wait for a quiet coalescing window"
  exit 1
}
grep -q 'mediaFileIO.load' Sources/Shared/Models/AppModel.swift || {
  echo "Large media files must be loaded outside the main actor"
  exit 1
}
grep -q 'stageAttachmentDraft' Sources/Shared/Models/AppModel.swift || {
  echo "Picker media must be copied outside the main actor before preview"
  exit 1
}
grep -q 'NSFileCoordinator' Sources/Shared/Services/MediaFileIO.swift || {
  echo "Security-scoped and iCloud media reads must be coordinated"
  exit 1
}
grep -q 'preferredItemEncoding: .current' Sources/Shared/UI/ChatView.swift || {
  echo "The photo picker must avoid unnecessary representation transcoding"
  exit 1
}
grep -q 'MediaPickerSelectionPolicy.preferredOrder' Sources/Shared/UI/ChatView.swift || {
  echo "Ambiguous photo/video providers must retain a fallback representation"
  exit 1
}
grep -q 'type: Data.self' Sources/Shared/UI/ChatView.swift || {
  echo "PhotosPicker images need a data fallback when no file representation is available"
  exit 1
}
grep -q 'CGImageSourceGetType' Sources/Shared/UI/ChatView.swift || {
  echo "Fallback image data must retain its real media type and extension"
  exit 1
}
grep -q 'setArchiveSyncSuspendedForMediaWork' Sources/Shared/Models/AppModel.swift || {
  echo "MAM must pause while gallery media is staged or sent"
  exit 1
}
grep -q 'withMediaPreparationActivity' Sources/Shared/UI/ChatView.swift || {
  echo "MAM must pause before Photos/iCloud item-provider loading starts"
  exit 1
}
grep -q 'thumbnailData: draft.thumbnailData' Sources/Shared/Models/AppModel.swift || {
  echo "Prepared gallery thumbnails must not be regenerated during send"
  exit 1
}
grep -q 'thumbnailImages: \[UUID: DraftThumbnailImage\]' Sources/Shared/UI/AttachmentPreviewView.swift || {
  echo "Attachment thumbnails must be decoded once and cached by draft ID"
  exit 1
}
grep -q '@State private var player: AVPlayer?' Sources/Shared/UI/Components/MediaViewer.swift || {
  echo "The full-screen video player must survive SwiftUI body updates"
  exit 1
}
if grep -q 'archiveLookback\|page < 10' Sources/Shared/XMPP/XMPPService.swift; then
  echo "MAM synchronization must not silently truncate history"
  exit 1
fi
grep -q 'performInitialScrollAfterLayout' Sources/Shared/UI/ChatView.swift || {
  echo "Deferred initial chat scroll is missing"
  exit 1
}
grep -q 'scrollDismissesKeyboard(.interactively)' Sources/Shared/UI/ChatView.swift || {
  echo "Interactive keyboard dismissal is missing"
  exit 1
}
grep -q 'rebuildTimelineEntries' Sources/Shared/UI/ChatView.swift || {
  echo "Chat rows and day boundaries must use the cached stable timeline"
  exit 1
}
grep -q 'jumpToLatestButton' Sources/Shared/UI/ChatView.swift || {
  echo "The chat must expose a jump-to-latest button away from the bottom"
  exit 1
}
grep -q 'ChatScrollMetricsObserver' Sources/Shared/UI/ChatView.swift || {
  echo "iOS bottom-button state must follow native UIScrollView metrics"
  exit 1
}
grep -q 'scheduleMetricsReport' Sources/Shared/UI/ChatView.swift || {
  echo "iOS scroll metrics must be coalesced before publishing SwiftUI state"
  exit 1
}
if sed -n '/func attachToAncestorScrollViewIfNeeded/,/func resetReportedState/p' \
  Sources/Shared/UI/ChatView.swift | grep -q 'observedScrollView == nil'; then
  echo "The iOS scroll observer must be able to attach to a replacement UIScrollView"
  exit 1
fi
grep -q 'ChatScrollPositionPolicy.isNearBottom' Sources/Shared/UI/ChatView.swift || {
  echo "The jump-to-latest button must follow a bounded bottom threshold"
  exit 1
}
grep -q 'safeAreaInset(edge: .bottom' Sources/Shared/UI/ChatView.swift || {
  echo "The glass composer must float without an opaque full-width background"
  exit 1
}
if sed -n '/private var messageInput:/,/private var composerActionControl:/p' \
  Sources/Shared/UI/ChatView.swift | grep -q 'DragGesture'; then
  echo "The composer must not compete with vertical timeline scrolling"
  exit 1
fi
grep -q 'ComposerRecordingGesturePolicy.resolution' Sources/Shared/UI/ChatView.swift || {
  echo "Telegram-style recording gestures are missing"
  exit 1
}
grep -q 'MessageReplySwipePolicy.shouldReply' Sources/Shared/UI/Components/MessageBubble.swift || {
  echo "Horizontal reply swipe is missing"
  exit 1
}
grep -q 'ChatMediaImageCache.image' Sources/Shared/UI/Components/PhotoAttachmentPreview.swift || {
  echo "Visible chat thumbnails must not be decoded on every SwiftUI pass"
  exit 1
}
if sed -n '/private var composer:/,/private var messageInput:/p' Sources/Shared/UI/ChatView.swift \
  | grep -q 'background(.ultraThinMaterial)'; then
  echo "The message composer must not have a full-width grey material background"
  exit 1
fi
grep -q 'Image(systemName: "paperclip")' Sources/Shared/UI/ChatView.swift || {
  echo "Telegram-style attachment control is missing"
  exit 1
}
grep -q 'presentVideoNoteRecorder()' Sources/Shared/UI/ChatView.swift || {
  echo "The attachment menu must open the dedicated video-note recorder"
  exit 1
}
grep -q 'Label("Видеосообщение"' Sources/Shared/UI/ChatView.swift || {
  echo "The attachment menu video-note action is missing"
  exit 1
}
grep -q 'try recorder.start()' Sources/Shared/UI/VideoNoteCaptureView.swift || {
  echo "The dedicated video-note screen must start recording after camera preparation"
  exit 1
}
if grep -q 'Режим видеосообщения\|composerCaptureMode.*video' Sources/Shared/UI/ChatView.swift; then
  echo "Video-note recording must not reuse the inline voice-message gesture"
  exit 1
fi
grep -q 'VideoNoteRotationPolicy.currentInterfaceOrientation' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Video note capture must rotate by the interface orientation, not the device sensor"
  exit 1
}
grep -q 'resetCaptureGraph()' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Reusable video-note capture cleanup is missing"
  exit 1
}
grep -q 'sessionQueue.async' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "AVCaptureSession start/stop must run outside the main actor"
  exit 1
}
grep -q 'afterMinimumDuration: VideoNoteStopPolicy.minimumCaptureDuration' \
  Sources/Shared/UI/VideoNoteCaptureView.swift || {
  echo "The dedicated video-note stop button must preserve the minimum valid recording duration"
  exit 1
}
if grep -q '450_000_000\|afterMinimumDuration: 0.45' Sources/Shared/UI/ChatView.swift; then
  echo "Video-note stop must follow AVCapture didStart rather than a guessed UI delay"
  exit 1
fi
grep -q 'VideoNoteRecordingCompletionPolicy.shouldKeepOutput' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Successful AVFoundation video files must survive non-nil completion errors"
  exit 1
}
grep -q 'VideoNoteRecordingLifecycle.acceptsCompletion' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Stale AVFoundation callbacks must not reset a newer video note"
  exit 1
}
grep -q 'model.setVideoNoteCaptureActive(true)' Sources/Shared/UI/ChatView.swift || {
  echo "Video-note capture must pause competing MAM work"
  exit 1
}
grep -q 'releaseArchiveSyncAfterCapture' Sources/Shared/UI/ChatView.swift || {
  echo "MAM must stay paused until video-note upload has yielded the main actor"
  exit 1
}
grep -q 'ComposerRecordingGesturePolicy.isLongPress' Sources/Shared/UI/ChatView.swift || {
  echo "Recording long-press must survive a delayed main actor"
  exit 1
}
grep -q 'beginPhysicalPress(at: value.time)' Sources/Shared/UI/ChatView.swift || {
  echo "Recording duration must use physical gesture timestamps"
  exit 1
}
grep -q 'ComposerRecordTouchSurface' Sources/Shared/UI/ChatView.swift || {
  echo "iOS voice recording must retain the physical touch across SwiftUI updates"
  exit 1
}
grep -q 'override func touchesCancelled' Sources/Shared/UI/ChatView.swift || {
  echo "A cancelled iOS recording touch must not be treated as release-to-send"
  exit 1
}
grep -q 'remainingRecordedDuration' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Video-note minimum duration must use recorded media time"
  exit 1
}
grep -q 'wasRequestedOrReachedLimit' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Unexpected camera completion must not send a partial video note"
  exit 1
}
grep -q 'normalizedRecordingPath' Sources/Shared/Models/VideoNoteRecordingLifecycle.swift || {
  echo "macOS temporary-path aliases must identify the active recording"
  exit 1
}
grep -q 'AVVideoCodecType.h264' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Video notes must use the interoperable H.264 codec when available"
  exit 1
}
grep -q 'VideoNoteFileInspector' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "Finalized video notes must be inspected before upload"
  exit 1
}
grep -q 'UIImagePickerController' Sources/Shared/UI/SystemPhotoCameraView.swift || {
  echo "Native iPhone camera capture is missing"
  exit 1
}
grep -q 'picker.mediaTypes = \[UTType.image.identifier, UTType.movie.identifier\]' \
  Sources/Shared/UI/SystemPhotoCameraView.swift || {
  echo "The native camera must support both photos and videos"
  exit 1
}
grep -q 'Label("Камера"' Sources/Shared/UI/ChatView.swift || {
  echo "The attachment menu must expose the photo/video camera"
  exit 1
}
grep -q 'presentAttachmentPreviewAfterPickerDismissal' Sources/Shared/UI/ChatView.swift || {
  echo "PhotosPicker dismissal must complete before attachment preview presentation"
  exit 1
}
grep -q 'attachmentPreviewPresentationPending' Sources/Shared/UI/ChatView.swift || {
  echo "A prepared attachment preview must remain queued across picker dismissal"
  exit 1
}
if sed -n '/private func presentAttachmentPreviewAfterPickerDismissal/,/private func loadPickedMediaFile/p' \
  Sources/Shared/UI/ChatView.swift | grep -q 'showingMediaPicker = false'; then
  echo "Attachment preview must not force-close PhotosPicker while UIKit is dismissing it"
  exit 1
fi
if sed -n '/private func copyPickedMediaFile/,/^}/p' Sources/Shared/UI/ChatView.swift \
  | grep -q 'options: \.forUploading'; then
  echo "PhotosPicker files must be coordinated as files, not upload packages"
  exit 1
fi
grep -q 'case reaction(ReactionEnvelope)' Sources/Shared/XMPP/XMPPService.swift || {
  echo "XEP-0444 reaction events are missing"
  exit 1
}
grep -q 'urn:xmpp:reactions:0' Sources/Shared/XMPP/XMPPService.swift || {
  echo "XEP-0444 capability advertisement is missing"
  exit 1
}
grep -q 'onReactPicker' Sources/Shared/UI/Components/MessageBubble.swift || {
  echo "Message reaction picker is missing"
  exit 1
}
grep -q 'EmojiPickerView' Sources/Shared/UI/ChatView.swift || {
  echo "The emoji picker is not wired into the chat"
  exit 1
}
grep -q 'ChatStateNotificationsModule' Sources/Shared/XMPP/XMPPService.swift || {
  echo "XEP-0085 chat-state support is missing"
  exit 1
}
grep -q 'model.updateComposerActivity' Sources/Shared/UI/ChatView.swift || {
  echo "The composer is not connected to typing notifications"
  exit 1
}
grep -q 'snapshotQueue.async' Sources/Shared/Services/PhoneWatchBridge.swift || {
  echo "Apple Watch snapshot encoding must not block SwiftUI"
  exit 1
}
awk '
  /^[[:space:]]*#if os\(iOS\)$/ { ios_only = 1; next }
  /^[[:space:]]*#endif$/ && ios_only { ios_only = 0; next }
  /availableVideoCodecTypes/ {
    found = 1
    if (!ios_only) escaped = 1
  }
  END { exit !(found && !escaped) }
' Sources/Shared/Services/VideoNoteRecorder.swift || {
  echo "iOS-only movie codec discovery escaped its platform guard"
  exit 1
}
grep -q 'canRetryMediaMessage' Sources/Shared/UI/Components/MessageBubble.swift || {
  echo "Failed media messages must expose a retry action"
  exit 1
}
grep -q 'MediaViewerDismissGesturePolicy.shouldDismiss' Sources/Shared/UI/Components/MediaViewer.swift || {
  echo "Full-screen media vertical swipe dismissal is missing"
  exit 1
}
if grep -q 'Image(systemName: "xmark")' Sources/Shared/UI/Components/MediaViewer.swift; then
  echo "Full-screen media viewer must not show a close button"
  exit 1
fi
grep -q 'selectedMessageIDs' Sources/Shared/UI/ChatView.swift || {
  echo "Multiple message selection is missing"
  exit 1
}
grep -q 'forwardMessages' Sources/Shared/UI/ForwardMessageView.swift || {
  echo "Multiple message forwarding is missing"
  exit 1
}
grep -q 'MediaSendActivityTracker' Sources/Shared/Models/AppModel.swift || {
  echo "Overlapping media send recovery is missing"
  exit 1
}
grep -q 'failedDrafts' Sources/Shared/UI/AttachmentPreviewView.swift || {
  echo "Failed media drafts must remain available for retry"
  exit 1
}
grep -q 'rosterContactJIDs' Sources/Shared/UI/MainTabView.swift || {
  echo "Prosody roster contacts screen is missing"
  exit 1
}
grep -q '\[.banner, .list, .sound\]' Sources/Shared/Services/NotificationCoordinator.swift || {
  echo "Foreground notification presentation is missing"
  exit 1
}

for catalog in Resources/*.xcassets/AppIcon.appiconset/Contents.json; do
  python3 -m json.tool "$catalog" >/dev/null
  python3 - "$catalog" <<'PY'
import json
import pathlib
import sys

catalog = pathlib.Path(sys.argv[1])
contents = json.loads(catalog.read_text())
filenames = [item.get("filename") for item in contents.get("images", [])]
if not filenames or any(not name for name in filenames):
    raise SystemExit(f"Incomplete AppIcon catalog: {catalog}")
missing = [name for name in filenames if not (catalog.parent / name).is_file()]
if missing:
    raise SystemExit(f"Missing AppIcon files in {catalog}: {', '.join(missing)}")
PY
done

for plist in Config/Luma-Info.plist Config/LumaMac-Info.plist Config/LumaWatch-Info.plist; do
  grep -q '<key>CFBundleIconName</key>' "$plist" || { echo "AppIcon is not configured in $plist"; exit 1; }
done

if command -v plutil >/dev/null; then
  plutil -lint Config/*.plist Config/*.entitlements >/dev/null
fi

if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet
fi

if command -v xcodebuild >/dev/null && test -d Luma.xcodeproj; then
  xcodebuild -project Luma.xcodeproj -scheme Luma \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
else
  echo "Static project checks passed. Run on macOS with Xcode for a full build."
fi
