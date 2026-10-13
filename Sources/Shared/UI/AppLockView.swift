import LocalAuthentication
import SwiftUI

@MainActor
struct AppLockView: View {
    @ObservedObject var model: AppModel
    @State private var passcode = ""
    @State private var attemptFailed = false
    @FocusState private var isFocused: Bool

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

            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Luma заблокирован")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                SecureField("Пароль", text: $passcode)
                    .focused($isFocused)
                    .textContentType(.password)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                    .onSubmit(submit)

                if attemptFailed {
                    Text("Неверный пароль")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.95))
                }

                Button(action: submit) {
                    Text("Разблокировать")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 260)
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(passcode.isEmpty)

                if model.biometricUnlockAvailable,
                    model.appLockBiometricIsEnabled
                {
                    Button {
                        Task { await biometricUnlock() }
                    } label: {
                        Label(
                            "Войти по \(model.biometricUnlockName)",
                            systemImage: model.biometricUnlockName == "Face ID"
                                ? "faceid" : "touchid"
                        )
                        .foregroundStyle(.white)
                    }
                }
            }
            .padding(28)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .padding(24)
        }
        .onAppear {
            isFocused = true
        }
        #if os(iOS)
            .task {
                // Auto-prompt biometrics once when the lock screen appears. iOS
                // only: on macOS the system Touch ID dialog blocks the window
                // and freezes the lock screen.
                guard model.biometricUnlockAvailable,
                    model.appLockBiometricIsEnabled
                else {
                    return
                }
                await biometricUnlock()
            }
        #endif
    }

    private func submit() {
        guard !passcode.isEmpty else { return }
        if model.unlockWithPasscode(passcode) {
            attemptFailed = false
            passcode = ""
        } else {
            attemptFailed = true
            passcode = ""
        }
    }

    private func biometricUnlock() async {
        _ = await model.unlockWithBiometrics()
    }
}

/// Configurable passcode sheet: setting up a new passcode, changing it, or
/// verifying the current one to disable the lock / toggle biometrics.
@MainActor
struct AppLockPasscodeSheet: View {
    enum Mode: Identifiable {
        case setup
        case change
        case verify(VerificationAction)

        enum VerificationAction: String {
            case disableLock
            case enableBiometrics
            case disableBiometrics
        }

        var id: String {
            switch self {
            case .setup: return "setup"
            case .change: return "change"
            case .verify(let action): return "verify-\(action.rawValue)"
            }
        }
    }

    let model: AppModel
    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    @State private var oldPasscode = ""
    @State private var passcode = ""
    @State private var repeatedPasscode = ""
    @State private var errorText: String?

    var body: some View {
        #if os(iOS)
            NavigationStack {
                Form {
                    formcontent()
                }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово", action: submit)
                            .disabled(!canSubmit)
                    }
                }
            }
        #else
            List {
                formcontent()
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: submit)
                        .disabled(!canSubmit)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    @ViewBuilder
    private func formcontent() -> some View {
        switch mode {
        case .setup:
            Section(title) {
                SecureField(fieldLabel, text: $passcode)
                    .textContentType(.password)
                SecureField("Повторите пароль", text: $repeatedPasscode)
                    .textContentType(.password)
            }
        case .verify:
            Section("Текущий пароль") {
                SecureField("Текущий пароль", text: $oldPasscode)
                    .textContentType(.password)
            }
        case .change:
            Section("Текущий пароль") {
                SecureField("Текущий пароль", text: $oldPasscode)
                    .textContentType(.password)
            }
            Section(title) {
                SecureField(fieldLabel, text: $passcode)
                    .textContentType(.password)
                SecureField("Повторите пароль", text: $repeatedPasscode)
                    .textContentType(.password)
            }
        }
        if let errorText {
            Section {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var title: String {
        switch mode {
        case .setup: return "Новый пароль"
        case .change: return "Новый пароль"
        case .verify: return "Пароль"
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .setup: return "Включить блокировку"
        case .change: return "Сменить пароль"
        case .verify(let action):
            switch action {
            case .disableLock: return "Выключить блокировку"
            case .enableBiometrics, .disableBiometrics:
                return "Подтвердите пароль"
            }
        }
    }

    private var fieldLabel: String {
        switch mode {
        case .setup, .change:
            return "Пароль (минимум \(AppLockPolicy.minimumLength) символа)"
        case .verify: return "Пароль"
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .setup:
            return !passcode.isEmpty && !repeatedPasscode.isEmpty
        case .change:
            return !oldPasscode.isEmpty && !passcode.isEmpty
                && !repeatedPasscode.isEmpty
        case .verify:
            return !oldPasscode.isEmpty
        }
    }

    private func submit() {
        errorText = nil
        switch mode {
        case .setup:
            guard AppLockPolicy.isValid(passcode) else {
                errorText =
                    "Пароль слишком короткий: минимум \(AppLockPolicy.minimumLength) символа."
                return
            }
            guard passcode == repeatedPasscode else {
                errorText = "Пароли не совпадают."
                repeatedPasscode = ""
                return
            }
            if model.enableAppLock(passcode: passcode) {
                dismiss()
            } else {
                errorText =
                    model.errorMessage ?? "Не удалось включить блокировку."
            }
        case .change:
            guard AppLockPolicy.isValid(passcode) else {
                errorText =
                    "Пароль слишком короткий: минимум \(AppLockPolicy.minimumLength) символа."
                return
            }
            guard passcode == repeatedPasscode else {
                errorText = "Пароли не совпадают."
                repeatedPasscode = ""
                return
            }
            if model.changeAppLockPasscode(from: oldPasscode, to: passcode) {
                dismiss()
            } else {
                errorText = "Неверный текущий пароль."
                oldPasscode = ""
            }
        case .verify(let action):
            switch action {
            case .disableLock:
                if model.disableAppLock(passcode: oldPasscode) {
                    dismiss()
                } else {
                    errorText = "Неверный пароль."
                    oldPasscode = ""
                }
            case .enableBiometrics:
                if model.setAppLockBiometricUnlock(true, passcode: oldPasscode)
                {
                    dismiss()
                } else {
                    errorText = "Неверный пароль."
                    oldPasscode = ""
                }
            case .disableBiometrics:
                if model.setAppLockBiometricUnlock(false, passcode: oldPasscode)
                {
                    dismiss()
                } else {
                    errorText = "Неверный пароль."
                    oldPasscode = ""
                }
            }
        }
    }
}

#Preview("Экран блокировки") {
    AppLockView(model: PreviewSupport.model)
}

#Preview("Настройка пароля") {
    AppLockPasscodeSheet(model: PreviewSupport.model, mode: .setup)
}
