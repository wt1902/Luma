import SwiftUI

struct NewChatView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var jid = ""
    @State private var name = ""
    @State private var addToRoster = true

    var body: some View {
#if os(iOS)
        NavigationStack {
            Form {
                formcontent()
            }
            .navigationTitle("Новый чат")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Начать") {
                        model.openConversation(
                            jid: jid,
                            name: name.isEmpty ? nil : name,
                            addToRoster: addToRoster
                        )
                        if model.errorMessage == nil { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(jid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
#else
        List {
            formcontent()
            HStack {
                Button("Отмена") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(.secondary)
                            Spacer()
                Button("Начать") {
                    model.openConversation(
                        jid: jid,
                        name: name.isEmpty ? nil : name,
                        addToRoster: addToRoster
                    )
                    if model.errorMessage == nil { dismiss() }
                }
                .fontWeight(.semibold)
                .disabled(jid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .navigationTitle("Новый чат")
        .frame(minWidth: 380, minHeight: 220)
#endif
    }
    @ViewBuilder
    private func formcontent() -> some View {
        Section("Контакт") {
            TextField("user@example.org", text: $jid)
                .disableAutocorrection(true)
            #if os(iOS)
                .keyboardType(.emailAddress)
            #endif
            TextField("Имя (необязательно)", text: $name)
        }
        Section {
            Toggle("Добавить в roster", isOn: $addToRoster)
                .toggleStyle(.switch)
        } footer: {
            Text("Начать чат можно с любым полным JID. Для шифрования у контакта должно быть опубликовано хотя бы одно OMEMO-устройство.")
        }
    }
}

#Preview {
    NewChatView(model: PreviewSupport.model)
}
