import Foundation
import SwiftUI
import WebRTC

@MainActor
struct CallView: View {
    @ObservedObject var model: AppModel
    let call: CallSnapshot

    private var conversation: Conversation {
        model.conversations.first(where: { $0.jid == call.peerJID.lowercased() })
            ?? Conversation(jid: call.peerJID, displayName: model.displayName(for: call.peerJID))
    }

    private var remoteTrack: RTCVideoTrack? {
        model.remoteCallVideoTrack(for: call.id)
    }

    private var localTrack: RTCVideoTrack? {
        model.localCallVideoTrack(for: call.id)
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 24) {
                callHeader
                    .padding(.top, 22)

                Spacer(minLength: 12)

                if remoteTrack == nil {
                    contactIdentity
                }

                Spacer(minLength: 20)

                controls
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)

            if call.isVideoCall, let localTrack, call.isCameraEnabled {
                RTCVideoRendererView(track: localTrack, mirrored: true)
                    .frame(width: 118, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 92)
                    .padding(.trailing, 18)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var background: some View {
        if call.isVideoCall, let remoteTrack {
            RTCVideoRendererView(track: remoteTrack)
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.48),
                            .clear,
                            .black.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        } else {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.17, blue: 0.24), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Circle()
                    .fill(Color.accentColor.opacity(0.24))
                    .frame(width: 440, height: 440)
                    .blur(radius: 90)
                    .offset(x: 170, y: -260)
            }
            .ignoresSafeArea()
        }
    }

    private var callHeader: some View {
        VStack(spacing: 5) {
            Text(conversation.displayName)
                .font(.headline)
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(statusText(at: context.date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var contactIdentity: some View {
        VStack(spacing: 18) {
            AvatarView(
                conversation: conversation,
                imageData: model.avatarData(for: call.peerJID),
                size: 132
            )
            .overlay {
                Circle().stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 28, y: 14)

            Text(conversation.displayName)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(call.isVideoCall ? "Видеозвонок Luma" : "Аудиозвонок Luma")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    @ViewBuilder
    private var controls: some View {
        if call.isIncomingRinging {
            HStack(spacing: 52) {
                CallControlButton(
                    title: "Отклонить",
                    systemImage: "phone.down.fill",
                    color: .red,
                    action: model.rejectCall
                )
                CallControlButton(
                    title: "Ответить",
                    systemImage: call.isVideoCall ? "video.fill" : "phone.fill",
                    color: .green
                ) {
                    Task { await model.answerCall() }
                }
            }
        } else {
            VStack(spacing: 22) {
                HStack(spacing: call.isVideoCall ? 10 : 24) {
                    CallControlButton(
                        title: call.isMuted ? "Включить" : "Микрофон",
                        systemImage: call.isMuted ? "mic.slash.fill" : "mic.fill",
                        color: call.isMuted ? .white.opacity(0.34) : .white.opacity(0.18)
                    ) {
                        model.setCallMuted(!call.isMuted)
                    }

#if os(iOS)
                    CallControlButton(
                        title: "Динамик",
                        systemImage: call.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.fill",
                        color: call.isSpeakerEnabled ? .white.opacity(0.34) : .white.opacity(0.18)
                    ) {
                        model.setCallSpeakerEnabled(!call.isSpeakerEnabled)
                    }
#endif

                    if call.isVideoCall {
                        CallControlButton(
                            title: call.isCameraEnabled ? "Камера" : "Включить",
                            systemImage: call.isCameraEnabled ? "video.fill" : "video.slash.fill",
                            color: call.isCameraEnabled ? .white.opacity(0.18) : .white.opacity(0.34)
                        ) {
                            model.setCallCameraEnabled(!call.isCameraEnabled)
                        }
                        CallControlButton(
                            title: "Повернуть",
                            systemImage: "camera.rotate.fill",
                            color: .white.opacity(0.18),
                            action: model.switchCallCamera
                        )
                    }
                }

                CallControlButton(
                    title: "Завершить",
                    systemImage: "phone.down.fill",
                    color: .red,
                    action: model.endCall
                )
            }
        }
    }

    private func statusText(at date: Date) -> String {
        switch call.phase {
        case .ringing:
            return call.direction == .incoming ? "Входящий звонок" : "Вызов…"
        case .connecting:
            return "Соединение…"
        case .connected:
            guard let connectedAt = call.connectedAt else { return "Соединено" }
            let total = max(0, Int(date.timeIntervalSince(connectedAt)))
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            let seconds = total % 60
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

private struct CallControlButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 24, weight: .semibold))
                    }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(minWidth: 58)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(title)
    }
}

#Preview("Входящий видеозвонок") {
    CallView(model: PreviewSupport.model, call: PreviewSupport.callSnapshot())
}

#Preview("Аудиозвонок") {
    CallView(
        model: PreviewSupport.model,
        call: PreviewSupport.callSnapshot(
            media: [.audio],
            phase: .connected,
            isSpeakerEnabled: true
        )
    )
}
