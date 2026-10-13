import Foundation
import os
import SwiftUI

#if os(iOS)
import UIKit
private typealias DraftThumbnailImage = UIImage
#elseif os(macOS)
import AppKit
private typealias DraftThumbnailImage = NSImage
#endif

@MainActor
struct AttachmentPreviewView: View {
    @ObservedObject var model: AppModel
    let conversation: Conversation
    @Binding var drafts: [AttachmentDraft]

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var isSending = false
    @State private var sendStatusMessage: String?
    @State private var previewItem: MediaViewerItem?
    @State private var thumbnailImages: [UUID: DraftThumbnailImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 190), spacing: 18)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(drafts) { draft in
                            draftCard(draft)
                        }
                    }
                    .padding(16)
                }

                Divider()
                VStack(spacing: 10) {
                    TextField("Добавить подпись…", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .disabled(isSending)

                    if let sendStatusMessage {
                        Label(sendStatusMessage, systemImage: "arrow.clockwise.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            send()
                        } label: {
                            Label(isSending ? "Отправка…" : "Отправить", systemImage: "arrow.up.circle.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(drafts.isEmpty || isSending)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Перед отправкой")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { cancel() }
                        .disabled(isSending)
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
#endif
        .interactiveDismissDisabled(isSending || previewItem != nil)
        .task(id: drafts.map(\.id)) {
            await cacheDraftThumbnails()
        }
        .overlay {
            if let previewItem {
                MediaViewer(item: previewItem) {
                    self.previewItem = nil
                }
                .zIndex(100)
            }
        }
        .onDisappear {
            guard !isSending, !drafts.isEmpty else { return }
            model.discardAttachmentDrafts(drafts)
            drafts = []
        }
    }

    private func draftCard(_ draft: AttachmentDraft) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Button {
                    presentPreview(for: draft)
                } label: {
                    ZStack {
                        Color.secondary.opacity(0.1)
                        thumbnail(for: draft)
                            .padding(6)

                        if draft.kind == .video {
                            Image(systemName: "play.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(11)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.secondary.opacity(0.13), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canPreview(draft) || isSending)
                .accessibilityLabel("Предпросмотр \(draft.filename)")

                Button {
                    remove(draft)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .accessibilityLabel("Убрать \(draft.filename)")
            }

            Text(draft.filename)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(detail(for: draft))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .background(.background, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
    }

    @ViewBuilder
    private func thumbnail(for draft: AttachmentDraft) -> some View {
#if os(iOS)
        if let image = thumbnailImages[draft.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            filePlaceholder(for: draft)
        }
#elseif os(macOS)
        if let image = thumbnailImages[draft.id] {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            filePlaceholder(for: draft)
        }
#endif
    }

    private func filePlaceholder(for draft: AttachmentDraft) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.secondary.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: icon(for: draft.kind))
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.tint)
        }
    }

    private var summary: String {
        let bytes = drafts.reduce(0) { $0 + $1.byteCount }
        return "\(drafts.count) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    private func detail(for draft: AttachmentDraft) -> String {
        var values = [ByteCountFormatter.string(fromByteCount: Int64(draft.byteCount), countStyle: .file)]
        if let duration = draft.duration {
            let seconds = max(0, Int(duration.rounded()))
            values.insert(String(format: "%d:%02d", seconds / 60, seconds % 60), at: 0)
        }
        return values.joined(separator: " · ")
    }

    private func icon(for kind: ChatMessage.Kind) -> String {
        switch kind {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .voice: return "waveform"
        case .videoNote: return "video.circle.fill"
        case .attachment: return "doc.fill"
        case .location: return "location.fill"
        case .text, .system: return "doc"
        }
    }

    private func remove(_ draft: AttachmentDraft) {
        model.discardAttachmentDrafts([draft])
        drafts.removeAll { $0.id == draft.id }
        thumbnailImages.removeValue(forKey: draft.id)
        if drafts.isEmpty { dismiss() }
    }

    private func cacheDraftThumbnails() async {
        let retainedIDs = Set(drafts.map(\.id))
        thumbnailImages = thumbnailImages.filter { retainedIDs.contains($0.key) }
        for draft in drafts where thumbnailImages[draft.id] == nil {
            guard let data = draft.thumbnailData,
                  let image = DraftThumbnailImage(data: data) else {
                if draft.kind == .video {
                    Logger(subsystem: "Luma", category: "video-preview")
                        .warning("video draft has no decodable thumbnail: \(draft.filename) thumbnailBytes=\(draft.thumbnailData?.count ?? 0)")
                }
                continue
            }
            thumbnailImages[draft.id] = image
            await Task.yield()
        }
    }

    private func canPreview(_ draft: AttachmentDraft) -> Bool {
        draft.kind == .photo || draft.kind == .video
    }

    private func presentPreview(for draft: AttachmentDraft) {
        guard canPreview(draft), FileManager.default.fileExists(atPath: draft.url.path) else { return }
        previewItem = MediaViewerItem(
            id: draft.id.uuidString,
            url: draft.url,
            kind: draft.kind,
            title: draft.filename
        )
    }

    private func cancel() {
        model.discardAttachmentDrafts(drafts)
        drafts = []
        dismiss()
    }

    private func send() {
        guard !isSending, !drafts.isEmpty else { return }
        let outgoingDrafts = drafts
        sendStatusMessage = nil
        isSending = true
        Task {
            let result = await model.sendAttachmentBatch(
                outgoingDrafts,
                caption: caption,
                to: conversation.jid
            )
            isSending = false
            if result.failedDrafts.isEmpty {
                drafts = []
                dismiss()
            } else {
                drafts = result.failedDrafts
                if result.sentCount > 0 {
                    sendStatusMessage = "Отправлено: \(result.sentCount). Не удалось: \(result.failedDrafts.count). Нажмите «Отправить», чтобы повторить оставшиеся."
                } else {
                    sendStatusMessage = "Не удалось отправить. Файлы сохранены здесь — проверьте соединение и повторите попытку."
                }
            }
        }
    }
}

private struct AttachmentPreviewHost: View {
    @State private var drafts = PreviewSupport.drafts()

    var body: some View {
        AttachmentPreviewView(
            model: PreviewSupport.model,
            conversation: PreviewSupport.conversation(displayName: "Алиса"),
            drafts: $drafts
        )
    }
}

#Preview {
    AttachmentPreviewHost()
}
