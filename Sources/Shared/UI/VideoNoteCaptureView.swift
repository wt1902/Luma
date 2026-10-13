import AVFoundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
struct VideoNoteCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VideoNoteRecorder()
    @State private var errorMessage: String?
    @State private var isFinalizing = false
    @State private var isSwitchingCamera = false

    let onComplete: (VideoNoteRecorder.Recording) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Color.black)
                    CameraPreview(session: recorder.session)
                        .clipShape(Circle())
                    if !recorder.isPrepared {
                        ProgressView("Подготовка камеры…")
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: 420)
                .aspectRatio(1, contentMode: .fit)
                .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                #if os(iOS)
                    .overlay(alignment: .bottomTrailing) {
                        if recorder.hasAlternateCamera, recorder.isPrepared {
                            Button(action: flipCamera) {
                                Image(
                                    systemName:
                                        "arrow.triangle.2.circlepath.camera.fill"
                                )
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(14)
                            .disabled(isSwitchingCamera || isFinalizing)
                            .accessibilityLabel("Переключить камеру")
                        }
                    }
                #endif

                Text(recordingStatus)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(recorder.isRecording ? .red : .secondary)

                Button {
                    guard recorder.isRecording, !isFinalizing else { return }
                    isFinalizing = true
                    Task { @MainActor in
                        await recorder.stop(
                            afterMinimumDuration: VideoNoteStopPolicy.minimumCaptureDuration
                        )
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.red, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        if isFinalizing {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.red)
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.red)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!recorder.isRecording || isFinalizing)
                .accessibilityLabel(isFinalizing ? "Видео завершается" : "Завершить запись")

                Text("Запись началась. Нажмите красную кнопку, чтобы завершить и отправить.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Видеосообщение")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            recorder.onFinished = { result in
                switch result {
                case .success(let recording):
                    onComplete(recording)
                    dismiss()
                case .failure(let error):
                    isFinalizing = false
                    errorMessage = error.localizedDescription
                }
            }
            do {
                try await recorder.prepare()
                guard !Task.isCancelled else { return }
                try recorder.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.cancel()
            } else {
                recorder.shutdown()
            }
        }
        .alert("Luma", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
#if os(macOS)
        .frame(minWidth: 540, minHeight: 650)
#endif
    }

    private func flipCamera() {
        guard !isSwitchingCamera, !isFinalizing else { return }
        isSwitchingCamera = true
        Task { @MainActor in
            do {
                try await recorder.switchCamera()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSwitchingCamera = false
        }
    }

    private func formatted(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var recordingStatus: String {
        if isFinalizing { return "Завершение…" }
        if recorder.isRecording { return formatted(recorder.elapsed) }
        return "Подготовка камеры…"
    }
}

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#elseif os(macOS)
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
#endif

#Preview {
    VideoNoteCaptureView { _ in }
}
