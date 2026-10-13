import Foundation
import SwiftUI

@MainActor
struct GroupInfoView: View {
    @ObservedObject var model: AppModel
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String
    @State private var invitees = ""
    @State private var isJoining = false
    @State private var isInviting = false
    @State private var confirmingDeletion = false

    init(model: AppModel, conversation: Conversation) {
        self.model = model
        self.conversation = conversation
        _nickname = State(initialValue: conversation.groupNickname ?? model.suggestedGroupNickname)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Групповой чат") {
                    LabeledContent("Комната", value: conversation.jid)
                    LabeledContent("Состояние", value: liveConversation.isGroupJoined ? "Подключено" : "Не подключено")
                    LabeledContent("Участников", value: "\(liveConversation.occupantCount)")
                    TextField("Ваш псевдоним", text: $nickname)
                        .disabled(liveConversation.isGroupJoined)
                }

                if !liveConversation.isGroupJoined {
                    Section {
                        Button {
                            join()
                        } label: {
                            Label(liveConversation.invitedBy == nil ? "Войти в комнату" : "Принять приглашение", systemImage: "person.2.fill")
                        }
                        .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
                    } footer: {
                        if let inviter = liveConversation.invitedBy {
                            Text("Приглашение от \(inviter)")
                        }
                    }
                } else {
                    Section("Пригласить участников") {
                        TextField("user@example.org, ещё@example.org", text: $invitees, axis: .vertical)
                            .lineLimit(2...4)
                        Button {
                            invite()
                        } label: {
                            if isInviting {
                                ProgressView()
                            } else {
                                Label("Отправить приглашения", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(parsedInvitees.isEmpty || isInviting)
                    }

                    Section {
                        Button(role: .destructive) {
                            model.leaveGroup(jid: conversation.jid)
                            dismiss()
                        } label: {
                            Label("Покинуть комнату", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingDeletion = true
                    } label: {
                        Label("Удалить чат", systemImage: "trash")
                    }
                } footer: {
                    Text("Чат и его история будут удалены с этого устройства.")
                }

                Section {
                    Label(
                        model.encryptionEnabled(for: conversation.jid)
                            ? "Для комнаты включено OMEMO. Нужны неанонимный MUC и OMEMO-устройства у всех участников."
                            : "OMEMO для этой комнаты выключено: сообщения передаются открытым текстом внутри TLS.",
                        systemImage: model.encryptionEnabled(for: conversation.jid) ? "lock.fill" : "lock.open"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(conversation.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .alert("Удалить групповой чат?", isPresented: $confirmingDeletion) {
                Button("Удалить", role: .destructive) {
                    model.deleteGroupChat(jid: conversation.jid)
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Чат и его история будут удалены с этого устройства. Luma выйдет из комнаты, если вы в ней.")
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 500)
#endif
    }

    private var liveConversation: Conversation {
        model.conversations.first(where: { $0.jid == conversation.jid }) ?? conversation
    }

    private var parsedInvitees: [String] {
        invitees.components(separatedBy: CharacterSet(charactersIn: ",;\n \t"))
            .filter { !$0.isEmpty }
    }

    private func join() {
        isJoining = true
        Task {
            await model.joinGroup(jid: conversation.jid, nickname: nickname)
            isJoining = false
        }
    }

    private func invite() {
        let outgoing = parsedInvitees
        guard !outgoing.isEmpty else { return }
        isInviting = true
        Task {
            await model.inviteMembers(outgoing, to: conversation.jid)
            invitees = ""
            isInviting = false
        }
    }
}

#Preview {
    GroupInfoView(
        model: PreviewSupport.model,
        conversation: PreviewSupport.conversation(
            jid: "team@conference.example.org",
            displayName: "Команда Luma",
            kind: .group,
            isGroupJoined: true,
            occupantCount: 7
        )
    )
}
