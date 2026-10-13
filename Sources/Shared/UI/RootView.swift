import QuickLook
import SwiftData
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if model.isAppLocked {
                // The lock covers every layer: chat list, media viewer and
                // calls stay hidden until the passcode or biometrics succeed.
                AppLockView(model: model)
            } else {
                Group {
                    if model.account == nil {
                        LoginView(model: model)
                    } else {
                        MainTabView(model: model)
                            .environment(\.modelContext, model.modelContext)
                    }
                }

                if let item = model.mediaViewerItem {
                    MediaViewer(item: item, onClose: model.closeMediaViewer)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(100)
                }

                if let call = model.activeCall {
                    CallView(model: model, call: call)
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                        .zIndex(200)
                }

                if let info = model.informationalMessage {
                    VStack {
                        toast(info)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(300)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.account?.id)
        .animation(.easeInOut(duration: 0.2), value: model.mediaViewerItem?.id)
        .animation(.easeInOut(duration: 0.2), value: model.activeCall?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.informationalMessage)
        .alert("Luma", isPresented: errorBinding) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Неизвестная ошибка")
        }
        .quickLookPreview($model.previewURL)
        .onChange(of: model.informationalMessage) { _, newValue in
            guard newValue != nil else { return }
            toastDismissTask?.cancel()
            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                model.clearInformationalMessage()
            }
        }
    }

    /// Compact Telegram-style confirmation toast shown for a couple of
    /// seconds above every layer (lists, media viewer, calls).
    private func toast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.top, 8)
        .accessibilityIdentifier("info-toast")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { visible in if !visible { model.clearError() } }
        )
    }
}

#Preview {
    RootView(model: PreviewSupport.model)
}
