import SwiftUI

struct LoginView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var jid = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var displayName = ""
    @State private var resource = ""
    @State private var showAdvanced = false
    @State private var manualHost = ""
    @State private var manualPort = ""
    @State private var directTLS = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.38, blue: 0.78),
                    Color(red: 0.12, green: 0.62, blue: 0.96),
                    Color(red: 0.44, green: 0.84, blue: 0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 420, height: 420)
                .offset(x: -210, y: -260)

            ScrollView {
                VStack(spacing: 28) {
                    brand
                    loginCard
                }
                .frame(maxWidth: 460)
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white)
                    .frame(width: 88, height: 88)
                    .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 39, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("Luma")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Приватный XMPP без привязки к одному серверу")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
        }
    }

    private var loginCard: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("XMPP-аккаунт")
                    .font(.headline)
                TextField("you@example.org", text: $jid)
                    #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    #endif
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .padding()
                    .glassEffect()
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Пароль")
                    .font(.headline)
                HStack(spacing: 8) {
                    Group {
                        if passwordVisible {
                            TextField("Пароль", text: $password)
                                .textContentType(.oneTimeCode)
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("Пароль", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.plain)
                        }
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .textFieldStyle(.roundedBorder)

                    Button {
                        passwordVisible.toggle()
                    } label: {
                        Image(systemName: passwordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(passwordVisible ? "Скрыть пароль" : "Показать пароль")
                }
                .padding()
                .glassEffect()
            }

            DisclosureGroup("Дополнительные настройки", isExpanded: $showAdvanced) {
                VStack(spacing: 14) {
                    TextField("Отображаемое имя", text: $displayName)
                        .textFieldStyle(.plain)
                        .padding()
                        .glassEffect()
                    TextField("Автоматически (Luma-XXXX)", text: $resource)
                        .textFieldStyle(.plain)
                        .padding()
                        .glassEffect()
                    Text(
                        "Оставьте пустым — Luma создаст уникальный ресурс для этого устройства, чтобы macOS и iOS не конфликтовали между собой."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    TextField("Сервер вручную (необязательно)", text: $manualHost)
                        .textFieldStyle(.plain)
                        .padding()
                        .glassEffect()
                    TextField(
                        directTLS ? "Порт, обычно 5223" : "Порт, обычно 5222", text: $manualPort
                    )
                    .textFieldStyle(.plain)
                    .padding()
                    .glassEffect()
                    Toggle("Direct TLS", isOn: $directTLS)
                        .toggleStyle(.switch)
                    Text(
                        "Без ручного адреса Luma использует DNS SRV и автоматически выбирает STARTTLS/direct TLS."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 14)
            }

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if model.isAuthenticating {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.isAuthenticating ? "Подключение…" : "Войти")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.isAuthenticating)

            Label(
                "Сообщения отправляются с OMEMO. Пароль хранится только в Keychain.",
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(26)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 24, y: 12)
    }

    private func signIn() async {
        let port = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines))
        let account = AccountConfiguration(
            jid: jid,
            displayName: displayName,
            resource: resource,
            manualHost: manualHost,
            manualPort: port,
            usesDirectTLS: directTLS
        )
        await model.signIn(account: account, password: password)

        // When LoginView is presented from Settings, close the sheet only
        // after AppModel has completed a successful sign-in. On failure the
        // model clears the active account, so the form remains available for
        // correcting the credentials.
        guard model.account?.normalizedJID == account.normalizedJID else { return }
        dismiss()
    }
}

#Preview {
    LoginView(model: PreviewSupport.model)
}
