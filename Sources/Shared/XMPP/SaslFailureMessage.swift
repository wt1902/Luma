import Foundation
import Martin

/// Turns a SASL authentication failure into an actionable Russian message.
/// The raw `<failure/>` condition (captured by `LumaSaslFailureModule`)
/// wins over Martin's `SaslError`, because Martin maps every unknown RFC
/// 6120 condition (e.g. `account-disabled`) to `not_authorized`.
enum SaslFailureMessage {
    static func describe(error: Error, condition: String?, serverText: String?) -> String {
        if let serverText, !serverText.isEmpty {
            // Prosody's SCRAM proof mismatch: the password the client used
            // differs from the one stored on the server. Translate it into an
            // actionable message (most often this is a typo or password
            // autofill substituting another account's password).
            if serverText.localizedCaseInsensitiveContains(
                "doesn't match the one we calculated"
            ) {
                return "Пароль не совпадает с сохранённым на сервере. Проверьте пароль (например, через значок глаза) и не используйте автозаполнение другого аккаунта."
            }
            return "Сервер отклонил вход: \(serverText)"
        }
        switch condition {
        case "account-disabled":
            return "Аккаунт отключён на сервере. Обратитесь к администратору сервера."
        case "credentials-expired":
            return "Срок действия пароля истёк. Обновите пароль на сервере."
        case "encryption-required":
            return "Сервер требует шифрование канала для входа."
        case "malformed-request":
            return "Сервер не смог обработать запрос входа. Попробуйте ещё раз."
        case "restricted-connection":
            return "Сервер ограничил подключения с этого адреса."
        default:
            break
        }
        if let saslError = error as? SaslError {
            switch saslError {
            case .not_authorized:
                return "Сервер отклонил имя пользователя или пароль. Проверьте JID и пароль."
            case .temporary_auth_failure:
                return "Сервер временно не может проверить учётные данные. Попробуйте через минуту."
            case .server_not_trusted:
                return "Сервер не прошёл проверку подписи SCRAM."
            case .incorrect_encoding:
                return "Сервер не принял кодировку учётных данных."
            case .invalid_authzid:
                return "Сервер отклонил идентификатор авторизации."
            case .invalid_mechanism, .mechanism_too_weak:
                return "Сервер не поддерживает доступные способы входа."
            case .aborted:
                return "Вход прерван."
            }
        }
        return error.localizedDescription
    }
}
