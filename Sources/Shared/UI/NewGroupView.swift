import Foundation
import SwiftUI

@MainActor
struct NewGroupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var roomJID = ""
    @State private var name = ""
    @State private var nickname = ""
    @State private var invitees = ""
    @State private var isJoining = false

    var body: some View {
        #if os(iOS)
            NavigationStack {
                Form {
                    formcontent()
                }
                .navigationTitle("Новая группа")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                            .disabled(isJoining)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать / войти") { join() }
                            .fontWeight(.semibold)
                            .disabled(!canJoin || isJoining)
                    }
                }
                .onAppear {
                    if nickname.isEmpty {
                        nickname = model.suggestedGroupNickname
                    }
                }
            }
        #else
            List {
                formcontent()
                HStack {
                    Button("Отмена") { dismiss() }
                        .disabled(isJoining)
                        .buttonStyle(.glass)
                        .tint(.secondary)
                        .controlSize(.large)
                    Spacer()
                    Button("Создать / войти") { join() }
                        .fontWeight(.semibold)
                        .disabled(!canJoin || isJoining)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
            .navigationTitle("Новая группа")
            .onAppear {
                if nickname.isEmpty { nickname = model.suggestedGroupNickname }
            }
            .frame(minWidth: 480, minHeight: 330)
        #endif
    }

    @ViewBuilder
    private func formcontent() -> some View {
        Section("Комната") {
            TextField("room@conference.example.org", text: $roomJID)
                .disableAutocorrection(true)
                #if os(iOS)
                    .keyboardType(.emailAddress)
                #endif
            TextField("Название (необязательно)", text: $name)
            TextField("Ваш псевдоним", text: $nickname)
        }
        Section("Пригласить") {
            TextField(
                "alice@example.org, bob@example.org",
                text: $invitees,
                axis: .vertical
            )
            .lineLimit(2...5)
            #if os(iOS)
                .keyboardType(.emailAddress)
            #endif
            Text(
                "Укажите JID через запятую или с новой строки. Если комнаты ещё нет, Prosody создаст её с настройками по умолчанию."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Label(
            "Новая комната настраивается как неанонимная и доступная участникам, чтобы поддерживать групповое OMEMO. Режим шифрования можно изменить в меню замка внутри чата.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var canJoin: Bool {
        !roomJID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func join() {
        isJoining = true
        Task {
            await model.createOrJoinGroup(
                roomJID: roomJID,
                name: name.isEmpty ? nil : name,
                nickname: nickname,
                invitees: parsedInvitees
            )
            isJoining = false
            if model.errorMessage == nil { dismiss() }
        }
    }

    private var parsedInvitees: [String] {
        invitees.components(separatedBy: CharacterSet(charactersIn: ",;\n \t"))
            .filter { !$0.isEmpty }
    }
}

#Preview {
    NewGroupView(model: PreviewSupport.model)
}
