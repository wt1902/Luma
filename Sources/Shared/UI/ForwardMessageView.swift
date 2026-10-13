import SwiftData
import SwiftUI

@MainActor
struct ForwardMessageView: View {
    @ObservedObject var model: AppModel
    let messages: [ChatMessage]
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destinationJID = ""
    @State private var isForwarding = false

    /// SwiftData-backed destination list, ordered like the main chat list.
    @Query private var conversations: [Conversation]

    init(
        model: AppModel,
        messages: [ChatMessage],
        onComplete: @escaping () -> Void = {}
    ) {
        _model = ObservedObject(wrappedValue: model)
        self.messages = messages.filter(\.canBeForwarded)
        self.onComplete = onComplete
        _conversations = Query(
            sort: [
                SortDescriptor(\Conversation.lastActivity, order: .reverse),
            ]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section(messages.count == 1 ? "Пересылаемое сообщение" : "Пересылаемые сообщения") {
                    Label(forwardingSummary, systemImage: "arrowshape.turn.up.right.fill")
                        .fontWeight(.semibold)
                    ForEach(Array(messages.prefix(3))) { message in
                        Text(message.previewText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if messages.count > 3 {
                        Text("И ещё \(messages.count - 3)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !orderedConversations.isEmpty {
                    Section("Чаты") {
                        ForEach(orderedConversations) { conversation in
                            Button {
                                forward(to: conversation.jid)
                            } label: {
                                HStack(spacing: 11) {
                                    AvatarView(
                                        conversation: conversation,
                                        imageData: model.avatarData(for: conversation.jid),
                                        size: 34
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(conversation.displayName)
                                            .foregroundStyle(.primary)
                                        Text(conversation.jid)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "paperplane.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isForwarding)
                        }
                    }
                }

                Section("Другой адрес") {
                    TextField("user@example.org", text: $destinationJID)
                        .disableAutocorrection(true)
                    Button {
                        forward(to: destinationJID)
                    } label: {
                        Label("Переслать", systemImage: "paperplane.fill")
                    }
                    .disabled(
                        isForwarding
                            || destinationJID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .navigationTitle(messages.count == 1 ? "Переслать" : "Переслать сообщения")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .overlay {
                if isForwarding {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        ProgressView("Пересылка…")
                            .padding(18)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
#endif
    }

    /// Pinned-first ordering, matching the main chat list.
    private var orderedConversations: [Conversation] {
        conversations.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    private func forward(to jid: String) {
        guard !isForwarding, !messages.isEmpty else { return }
        isForwarding = true
        Task {
            let succeeded = await model.forwardMessages(messages, to: jid)
            isForwarding = false
            if succeeded {
                onComplete()
                dismiss()
            }
        }
    }

    private var forwardingSummary: String {
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

#Preview {
    ForwardMessageView(
        model: PreviewSupport.model,
        messages: [
            PreviewSupport.message(body: "Привет! Как дела?"),
            PreviewSupport.message(
                senderJID: "me@example.org",
                body: "Созвонимся вечером?",
                direction: .outgoing,
                delivery: .sent
            ),
        ]
    )
    .modelContainer(PreviewSupport.container)
}
