import Foundation
import os

struct CapturedCameraMedia: Sendable {
    let url: URL
    let kind: ChatMessage.Kind
}

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct SystemPhotoCameraView: UIViewControllerRepresentable {
    /// Called synchronously on the main thread inside
    /// `didFinishPickingMediaWithInfo`, before any background preparation.
    /// The host must flip its `isPresented` binding here so SwiftUI drives
    /// the dismissal; letting UIImagePickerController dismiss itself leaves
    /// the fullScreenCover state desynchronized and breaks the follow-up
    /// preview presentation.
    let onDismissRequest: () -> Void
    let onMedia: (Result<CapturedCameraMedia, Error>) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onDismissRequest: onDismissRequest,
            onMedia: onMedia,
            onCancel: onCancel
        )
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.cameraCaptureMode = .photo
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 180
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onDismissRequest: () -> Void
        private let onMedia: (Result<CapturedCameraMedia, Error>) -> Void
        private let onCancel: () -> Void
        private var completed = false

        init(
            onDismissRequest: @escaping () -> Void,
            onMedia: @escaping (Result<CapturedCameraMedia, Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onDismissRequest = onDismissRequest
            self.onMedia = onMedia
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard !completed else { return }
            completed = true
            onDismissRequest()

            let mediaType = (info[.mediaType] as? String).flatMap { UTType($0) }
            if mediaType?.conforms(to: .movie) == true,
               let sourceURL = info[.mediaURL] as? URL {
                prepareMovie(from: sourceURL)
                return
            }

            guard let image = info[.originalImage] as? UIImage else {
                onMedia(.failure(SystemCameraError.missingMedia))
                return
            }
            preparePhoto(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !completed else { return }
            completed = true
            onCancel()
        }

        private func preparePhoto(_ image: UIImage) {
            let completion = onMedia
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<CapturedCameraMedia, Error>
                do {
                    let url = try Self.destinationURL(extension: "jpg")
                    guard let data = image.jpegData(compressionQuality: 0.9),
                          !data.isEmpty else {
                        throw SystemCameraError.encodingFailed
                    }
                    try data.write(to: url, options: [.atomic])
                    result = .success(CapturedCameraMedia(url: url, kind: .photo))
                } catch {
                    result = .failure(error)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }

        /// Claims the picker-owned temporary movie synchronously, while the
        /// picker is still alive: UIImagePickerController can delete its
        /// temporary file as soon as it is dismissed, so a background copy
        /// races that cleanup and fails with an unreadable source. The move
        /// is a same-volume rename and does not block the main thread.
        private func prepareMovie(from sourceURL: URL) {
            let logger = Logger(subsystem: "Luma", category: "video-preview")
            do {
                let sourceSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                logger.info("picker movie ready: source=\(sourceURL.lastPathComponent) size=\(sourceSize)")
                let fileExtension = sourceURL.pathExtension.isEmpty
                    ? "mov"
                    : sourceURL.pathExtension
                let destination = try Self.destinationURL(extension: fileExtension)
                try FileManager.default.moveItem(at: sourceURL, to: destination)
                let values = try destination.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey]
                )
                let movedSize = values.fileSize ?? 0
                logger.info("picker movie moved: size=\(movedSize) regular=\(values.isRegularFile == true)")
                guard values.isRegularFile == true, movedSize > 0 else {
                    try? FileManager.default.removeItem(at: destination)
                    throw SystemCameraError.emptyMovie
                }
                onMedia(.success(CapturedCameraMedia(url: destination, kind: .video)))
            } catch {
                logger.error("picker movie preparation failed: \(error.localizedDescription)")
                onMedia(.failure(error))
            }
        }

        private static func destinationURL(extension fileExtension: String) throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LumaCameraMedia", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(
                "camera-\(UUID().uuidString).\(fileExtension)"
            )
        }
    }
}

private enum SystemCameraError: LocalizedError {
    case missingMedia
    case encodingFailed
    case emptyMovie

    var errorDescription: String? {
        switch self {
        case .missingMedia:
            return "Камера не вернула фото или видео."
        case .encodingFailed:
            return "Не удалось подготовить фотографию к отправке."
        case .emptyMovie:
            return "Камера вернула пустой видеофайл. Повторите запись."
        }
    }
}

#Preview {
    SystemPhotoCameraView(
        onDismissRequest: {},
        onMedia: { _ in },
        onCancel: {}
    )
}
#endif
