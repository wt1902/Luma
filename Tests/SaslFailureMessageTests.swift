import Martin
import XCTest
@testable import Luma

final class SaslFailureMessageTests: XCTestCase {
    func testNotAuthorizedProducesActionableMessage() {
        let message = SaslFailureMessage.describe(
            error: SaslError.not_authorized, condition: nil, serverText: nil)
        XCTAssertEqual(
            message,
            "Сервер отклонил имя пользователя или пароль. Проверьте JID и пароль.")
    }

    func testServerTextWinsOverCondition() {
        let message = SaslFailureMessage.describe(
            error: SaslError.not_authorized,
            condition: "not-authorized",
            serverText: "Bad password")
        XCTAssertEqual(message, "Сервер отклонил вход: Bad password")
    }

    func testAccountDisabledIsExplained() {
        let message = SaslFailureMessage.describe(
            error: SaslError.not_authorized,
            condition: "account-disabled",
            serverText: nil)
        XCTAssertEqual(
            message,
            "Аккаунт отключён на сервере. Обратитесь к администратору сервера.")
    }

    func testCredentialsExpiredIsExplained() {
        let message = SaslFailureMessage.describe(
            error: SaslError.not_authorized,
            condition: "credentials-expired",
            serverText: nil)
        XCTAssertEqual(message, "Срок действия пароля истёк. Обновите пароль на сервере.")
    }

    func testProsodyProofMismatchIsExplained() {
        let message = SaslFailureMessage.describe(
            error: SaslError.not_authorized,
            condition: "not-authorized",
            serverText: "The response provided by the client doesn't match the one we calculated")
        XCTAssertEqual(
            message,
            "Пароль не совпадает с сохранённым на сервере. Проверьте пароль (например, через значок глаза) и не используйте автозаполнение другого аккаунта.")
    }

    func testTemporaryAuthFailureIsExplained() {
        let message = SaslFailureMessage.describe(
            error: SaslError.temporary_auth_failure, condition: nil, serverText: nil)
        XCTAssertEqual(
            message,
            "Сервер временно не может проверить учётные данные. Попробуйте через минуту.")
    }
}

