import Foundation
import SwiftUI

struct WatchChatListView: View {
    @ObservedObject var model: WatchSessionModel

    var body: some View {
        NavigationStack {
            Group {
                if model.chats.isEmpty {
                    ContentUnavailableView(
                        "Нет чатов",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text("Откройте Luma на iPhone для синхронизации.")
                    )
                } else {
                    List(model.chats) { chat in
                        NavigationLink(value: chat) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chat.name).font(.headline).lineLimit(1)
                                    Spacer()
                                    if chat.unread > 0 {
                                        Text("\(chat.unread)")
                                            .font(.caption2.bold())
                                            .padding(5)
                                            .background(.blue, in: Circle())
                                    }
                                }
                                Text(chat.messages.last?.body ?? chat.jid)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Luma")
            .navigationDestination(for: WatchSnapshot.Chat.self) { chat in
                WatchChatView(model: model, chat: chat)
            }
        }
        .alert("Luma", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Ошибка")
        }
    }
}

private struct WatchChatView: View {
    @ObservedObject var model: WatchSessionModel
    let chat: WatchSnapshot.Chat
    @StateObject private var voiceRecorder = WatchVoiceRecorder()
    @State private var reply = ""

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(chat.messages) { message in
                    HStack {
                        if message.outgoing { Spacer(minLength: 16) }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                if message.encrypted {
                                    Image(systemName: "lock.fill").font(.caption2)
                                }
                                Text(message.body)
                            }
                            Text(message.timestamp, format: .dateTime.hour().minute())
                                .font(.caption2)
                                .opacity(0.7)
                        }
                        .padding(7)
                        .background(message.outgoing ? Color.blue : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
                        if !message.outgoing { Spacer(minLength: 16) }
                    }
                    .id(message.id)
                }

                Section {
                    TextField("Ответ", text: $reply)
                    Button("Отправить") {
                        model.send(text: reply, to: chat.jid)
                        reply = ""
                    }
                    .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Голосовое") {
                    voiceComposer

                    if let status = model.voiceStatus(for: chat.jid) {
                        Label(status, systemImage: "iphone.and.arrow.forward")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Быстрый ответ") {
                    ForEach(["Хорошо", "Спасибо!", "Отвечу позже"], id: \.self) { text in
                        Button(text) { model.send(text: text, to: chat.jid) }
                    }
                }
            }
            .navigationTitle(chat.name)
            .onAppear {
                if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onDisappear {
                voiceRecorder.reset()
            }
        }
    }

    @ViewBuilder
    private var voiceComposer: some View {
        if voiceRecorder.isRecording {
            VStack(spacing: 8) {
                Label(
                    formatDuration(voiceRecorder.elapsed),
                    systemImage: "waveform"
                )
                .font(.headline.monospacedDigit())
                .foregroundStyle(.red)

                ProgressView(
                    value: voiceRecorder.elapsed,
                    total: WatchVoiceRecorder.maximumDuration
                )
                .tint(.red)

                HStack(spacing: 8) {
                    Button(role: .destructive) {
                        voiceRecorder.cancelRecording()
                    } label: {
                        Label("Отмена", systemImage: "xmark")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        finishVoiceRecording()
                    } label: {
                        Label("Готово", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .font(.caption)
            }
        } else if let recording = voiceRecorder.recording {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        do {
                            try voiceRecorder.togglePlayback()
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    } label: {
                        Image(systemName: voiceRecorder.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(voiceRecorder.isPlaying ? "Пауза" : "Прослушать")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Предпрослушивание")
                            .font(.caption)
                        Text(formatDuration(recording.duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    if model.sendVoice(
                        fileURL: recording.url,
                        duration: recording.duration,
                        to: chat.jid
                    ) {
                        _ = voiceRecorder.detachRecording()
                    }
                } label: {
                    Label("Отправить голосовое", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    voiceRecorder.discardRecording()
                } label: {
                    Label("Удалить запись", systemImage: "trash")
                }
                .font(.caption)
            }
        } else {
            Button {
                Task {
                    do {
                        try await voiceRecorder.start()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("Записать голосовое", systemImage: "mic.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func finishVoiceRecording() {
        do {
            try voiceRecorder.finish()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    MainActor.assumeIsolated {
        WatchChatListView(model: WatchSessionModel())
    }
}
