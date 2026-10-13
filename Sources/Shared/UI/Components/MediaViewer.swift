import AVFoundation
import AVKit
import SwiftUI

#if os(iOS)
import UIKit
private typealias MediaViewerPlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias MediaViewerPlatformImage = NSImage
#endif

enum MediaViewerDismissGesturePolicy {
    private static let verticalDominance: CGFloat = 1.15

    static func isVertical(_ translation: CGSize) -> Bool {
        let verticalDistance = abs(translation.height)
        let horizontalDistance = abs(translation.width)
        return verticalDistance >= 8 && verticalDistance > horizontalDistance * verticalDominance
    }

    static func shouldDismiss(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        containerHeight: CGFloat
    ) -> Bool {
        guard isVertical(translation) else { return false }

        let distanceThreshold = min(140, max(88, containerHeight * 0.14))
        if abs(translation.height) >= distanceThreshold {
            return true
        }

        return isVertical(predictedEndTranslation)
            && abs(predictedEndTranslation.height) >= distanceThreshold * 1.35
    }
}

@MainActor
struct MediaViewer: View {
    let item: MediaViewerItem
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isTrackingDismissGesture = false
    @State private var isCompletingDismissal = false
    @State private var isPhotoZoomed = false
    @State private var saveErrorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(backgroundOpacity(in: geometry.size.height))
                    .ignoresSafeArea()

                ZStack {
                    viewerContent
                        .ignoresSafeArea(edges: .bottom)

                    VStack(spacing: 0) {
                        Spacer()
                        HStack {
//                            Text(item.title)
//                                .font(.headline)
//                                .foregroundStyle(.white)
//                                .lineLimit(1)

                            Spacer()

                            Button(action: save) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.white.opacity(0.16), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Сохранить")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(
                            LinearGradient(
                                colors: [.black.opacity(0.72), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        )
                    }
                }
                .offset(y: dragOffset)
                .scaleEffect(contentScale(in: geometry.size.height))
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                verticalDismissGesture(in: geometry.size),
                including: .all
            )
            .onChange(of: isPhotoZoomed) { _, isZoomed in
                guard isZoomed else { return }
                resetDismissGesture(animated: true)
            }
            .accessibilityAction(.escape) {
                closeImmediately()
            }
            .alert("Ошибка сохранения", isPresented: saveErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "Не удалось сохранить медиа.")
            }
        }
#if os(macOS)
        .onExitCommand {
            closeImmediately()
        }
#endif
    }

    private var canTrackDismissGesture: Bool {
        !isPhotoZoomed && !isCompletingDismissal
    }

    private func verticalDismissGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                guard canTrackDismissGesture else { return }

                if !isTrackingDismissGesture {
                    guard MediaViewerDismissGesturePolicy.isVertical(value.translation) else { return }
                    isTrackingDismissGesture = true
                }

                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard isTrackingDismissGesture else { return }
                isTrackingDismissGesture = false

                guard canTrackDismissGesture else {
                    resetDismissGesture(animated: true)
                    return
                }

                if MediaViewerDismissGesturePolicy.shouldDismiss(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    containerHeight: size.height
                ) {
                    completeDismissal(
                        direction: dismissalDirection(for: value),
                        containerHeight: size.height
                    )
                } else {
                    resetDismissGesture(animated: true)
                }
            }
    }

    private func dismissalDirection(for value: DragGesture.Value) -> CGFloat {
        let projected = value.predictedEndTranslation.height
        let distance = abs(projected) > abs(value.translation.height)
            ? projected
            : value.translation.height
        return distance < 0 ? -1 : 1
    }

    private func completeDismissal(direction: CGFloat, containerHeight: CGFloat) {
        guard !isCompletingDismissal else { return }
        isCompletingDismissal = true

        withAnimation(.easeOut(duration: 0.18)) {
            dragOffset = direction * max(700, containerHeight * 1.15)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            onClose()
        }
    }

    private func resetDismissGesture(animated: Bool) {
        isTrackingDismissGesture = false
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                dragOffset = 0
            }
        } else {
            dragOffset = 0
        }
    }

    private func closeImmediately() {
        guard !isCompletingDismissal else { return }
        isCompletingDismissal = true
        onClose()
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { visible in if !visible { saveErrorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await MediaDownloadService.save(
                    url: item.url,
                    kind: item.kind,
                    filename: item.title
                )
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
    }

    private func dismissalProgress(in containerHeight: CGFloat) -> CGFloat {
        min(1, abs(dragOffset) / max(1, containerHeight * 0.62))
    }

    private func backgroundOpacity(in containerHeight: CGFloat) -> Double {
        Double(1 - dismissalProgress(in: containerHeight) * 0.72)
    }

    private func contentScale(in containerHeight: CGFloat) -> CGFloat {
        1 - dismissalProgress(in: containerHeight) * 0.045
    }

    @ViewBuilder
    private var viewerContent: some View {
        switch item.kind {
        case .photo:
            ZoomablePhotoView(url: item.url, isZoomed: $isPhotoZoomed)
        case .video:
            FullWindowVideoPlayer(url: item.url)
        default:
            ContentUnavailableView(
                "Не удалось открыть медиа",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.white)
        }
    }
}

@MainActor
private struct FullWindowVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                player?.pause()
                let nextPlayer = AVPlayer(url: url)
                player = nextPlayer
                nextPlayer.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

@MainActor
private struct ZoomablePhotoView: View {
    let url: URL
    @Binding var isZoomed: Bool

    @State private var imageValue: MediaViewerPlatformImage?
    @State private var hasFinishedLoading = false
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let imageValue {
                    image(imageValue)
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(effectiveScale)
                        .offset(effectiveOffset)
                        .gesture(dragGesture)
                        .simultaneousGesture(magnifyGesture)
                        .onTapGesture(count: 2, perform: toggleZoom)
                } else if hasFinishedLoading {
                    invalidImage
                } else {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .clipped()
        }
        .onChange(of: effectiveScale) { _, value in
            isZoomed = value > 1.01
        }
        .onDisappear {
            isZoomed = false
        }
        .task(id: url) {
            imageValue = nil
            hasFinishedLoading = false
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard !Task.isCancelled else { return }
            imageValue = data.flatMap { MediaViewerPlatformImage(data: $0) }
            hasFinishedLoading = true
        }
    }

    private var effectiveScale: CGFloat {
        min(5, max(1, scale * gestureScale))
    }

    private var effectiveOffset: CGSize {
        guard effectiveScale > 1 else { return .zero }
        return CGSize(
            width: offset.width + gestureOffset.width,
            height: offset.height + gestureOffset.height
        )
    }

    @ViewBuilder
    private func image(_ value: MediaViewerPlatformImage) -> some View {
#if os(iOS)
        Image(uiImage: value)
            .resizable()
#elseif os(macOS)
        Image(nsImage: value)
            .resizable()
#endif
    }

    private var invalidImage: some View {
        ContentUnavailableView(
            "Фото повреждено",
            systemImage: "photo.badge.exclamationmark"
        )
        .foregroundStyle(.white)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                guard effectiveScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard effectiveScale > 1 else {
                    offset = .zero
                    return
                }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = min(5, max(1, scale * value.magnification))
                if scale == 1 {
                    offset = .zero
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2
            }
        }
    }
}

#Preview {
    MediaViewer(
        item: MediaViewerItem(
            id: "preview",
            url: URL(fileURLWithPath: "/tmp/preview-photo.jpg"),
            kind: .photo,
            title: "IMG_1234.jpg"
        ),
        onClose: {}
    )
}
