import Foundation
import UniformTypeIdentifiers

#if os(iOS)
import Photos
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Saves a message's cached media to the right destination: photos, videos and
/// video notes go to the Photos library on iOS (or Downloads on macOS, which
/// would otherwise need a Photo Library entitlement), while files, audio and
/// voice messages go to the user's Downloads location. Kept dependency-free so
/// every bubble, the full-screen viewer and the audio player share one path.
@MainActor
enum MediaDownloadService {
    enum SaveError: LocalizedError {
        case missingLocalFile
        case unsupportedKind

        var errorDescription: String? {
            switch self {
            case .missingLocalFile:
                return "Не удалось загрузить файл для сохранения."
            case .unsupportedKind:
                return "Этот тип сообщения нельзя сохранить."
            }
        }
    }

    // MARK: - Entry points

    /// Resolve the cached copy for `message` (downloading through AppModel when
    /// needed) and save it. Failures are surfaced through AppModel's error alert.
    static func save(_ message: ChatMessage, model: AppModel) async {
        do {
            guard let sourceURL = await resolvedLocalURL(for: message, model: model) else {
                throw SaveError.missingLocalFile
            }
            let filename = message.localFilename ?? Self.defaultFilename(for: message)
            let didSave = try await save(
                url: sourceURL,
                kind: message.kind,
                filename: filename
            )
            if didSave {
                model.informationalMessage = "Сохранено."
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    /// Save an already-downloaded file, routing by kind and platform. Returns
    /// `false` when the user cancelled an interactive save sheet.
    @discardableResult
    static func save(
        url: URL,
        kind: ChatMessage.Kind,
        filename: String
    ) async throws -> Bool {
        switch kind {
        case .photo, .video, .videoNote:
            #if os(iOS)
            try await saveToPhotos(url: url, kind: kind)
            return true
            #else
            return try await saveToDownloads(url: url, filename: filename)
            #endif
        case .attachment, .audio, .voice:
            return try await saveToDownloads(url: url, filename: filename)
        case .text, .location, .system:
            throw SaveError.unsupportedKind
        }
    }

    // MARK: - Local file resolution

    private static func resolvedLocalURL(
        for message: ChatMessage,
        model: AppModel
    ) async -> URL? {
        if let cached = model.mediaPreviewURL(for: message) {
            return cached
        }
        // Inline media (photo/video/audio/voice/video note) is fetched by
        // AppModel into its preview cache; files are not auto-previewed and fall
        // through to the QuickLook handoff below.
        await model.prepareMediaPreview(message)
        if let cached = model.mediaPreviewURL(for: message) {
            return cached
        }
        // Attachments are only fetched on demand via previewAttachment(_:),
        // which parks the result in the single-shot previewURL property. Clear it
        // before and after so the QuickLook sheet does not flash open.
        model.previewURL = nil
        await model.previewAttachment(message)
        let url = model.previewURL
        model.previewURL = nil
        return url
    }

    // MARK: - Photos

    #if os(iOS)
    private static func saveToPhotos(url: URL, kind: ChatMessage.Kind) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            if kind == .photo {
                _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            } else {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }
    #endif

    // MARK: - Downloads

    private static func saveToDownloads(url: URL, filename: String) async throws -> Bool {
        #if os(macOS)
        return try await saveWithPanel(url: url, filename: filename)
        #else
        return await FileExportPresenter.shared.present(url: url)
        #endif
    }

    #if os(macOS)
    /// Present a save panel defaulting to ~/Downloads. The app sandbox grants
    /// write access to the location the user picks, so no Downloads entitlement
    /// is required.
    private static func saveWithPanel(url: URL, filename: String) async throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        if let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let destination = panel.url else {
            return false
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return true
    }
    #endif

    // MARK: - Helpers

    private static func defaultFilename(for message: ChatMessage) -> String {
        let ext = Self.fileExtension(for: message)
        let base: String
        switch message.kind {
        case .photo: base = "Фото"
        case .video: base = "Видео"
        case .videoNote: base = "Видеосообщение"
        case .voice: base = "Голосовое сообщение"
        case .audio: base = "Аудио"
        case .attachment: base = "Вложение"
        default: base = "Файл"
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    private static func fileExtension(for message: ChatMessage) -> String {
        if let filename = message.localFilename {
            let ext = (filename as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }
        if let mime = message.mimeType,
            let type = UTType(mimeType: mime),
            let ext = type.preferredFilenameExtension
        {
            return ext
        }
        switch message.kind {
        case .video, .videoNote: return "mp4"
        case .voice, .audio: return "m4a"
        case .photo: return "jpg"
        default: return ""
        }
    }
}

#if os(iOS)
/// Presents the system "save to Files" sheet for a cached file and reports
/// whether the user completed the save or cancelled. Held alive by the
/// continuation until the delegate fires.
@MainActor
private final class FileExportPresenter: NSObject, UIDocumentPickerDelegate {
    static let shared = FileExportPresenter()

    private var continuation: CheckedContinuation<Bool, Never>?

    func present(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = self
            Task { @MainActor in
                // Let a just-dismissed context menu finish its transition before
                // presenting, otherwise the sheet can be rejected.
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let presenter = Self.topPresenter(),
                    presenter.presentedViewController == nil
                else {
                    self.finish(false)
                    return
                }
                presenter.present(picker, animated: true)
            }
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finish(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(false)
    }

    private func finish(_ result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    private static func topPresenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let window = scene.windows.first(where: { $0.isKeyWindow }),
            let root = window.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
