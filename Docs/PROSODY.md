# Настройка Prosody для Luma

Ниже приведён ориентир для актуальных Prosody 0.12/13. Сохраните существующие
модули аутентификации, TLS и federation вашего сервера — пример показывает
только функции, необходимые клиенту.

```lua
VirtualHost "example.org"

modules_enabled = {
    -- ваши базовые модули;
    "roster";    -- RFC 6121: серверный список контактов
    "pep";       -- PEP: OMEMO device lists/bundles и XEP-0084 аватары
    "smacks";    -- XEP-0198
    "carbons";   -- XEP-0280
    "mam";       -- XEP-0313
    "turn_external"; -- XEP-0215: STUN/TURN для Jingle-звонков
}

-- Тот же секрет укажите в coturn как static-auth-secret.
turn_external_secret = "ЗАМЕНИТЕ_ДЛИННЫМ_СЛУЧАЙНЫМ_СЕКРЕТОМ"
turn_external_host = "turn.example.org"
turn_external_port = 3478
-- Необязательно: если coturn принимает TURN/TLS на 5349.
turn_external_tls_port = 5349

default_archive_policy = true
archive_expires_after = "1mon"
max_archive_query_results = 100

-- Рекомендуется SQL-хранилище для архива.
storage = {
    archive = "sql";
}

Component "upload.example.org" "http_file_share"
    -- Luma не задаёт собственного предела; выберите серверный лимит под диск
    -- и reverse proxy. Ниже пример на 1 ГиБ.
    http_file_share_size_limit = 1024 * 1024 * 1024
    http_file_share_expires_after = "1 month" -- Prosody 13
    modules_disabled = { "s2s" }

-- XEP-0045: групповые комнаты Luma/Conversations/Monal
Component "conference.example.org" "muc"
    name = "Групповые чаты"
    restrict_room_creation = false -- либо "local" для локальных пользователей
    modules_enabled = { "muc_mam" }
    muc_log_by_default = true
    muc_log_expires_after = "1mon"
```

## Аудио- и видеозвонки

Сам XMPP-сервер только согласовывает Jingle-сессию. Для двух клиентов с
доступными адресами этого достаточно, но за NAT/CGNAT нужен coturn. Начиная с
Prosody 0.12 проще всего использовать встроенный `mod_turn_external`, как в
примере выше: он публикует STUN/TURN и выдаёт клиенту временные учётные данные
через XEP-0215.

Минимальные соответствующие параметры coturn:

```ini
fingerprint
use-auth-secret
static-auth-secret=ЗАМЕНИТЕ_ТЕМ_ЖЕ_СЕКРЕТОМ
realm=example.org
listening-port=3478
tls-listening-port=5349
# Для TURN/TLS также задайте cert= и pkey=.
```

Откройте для coturn UDP/TCP 3478, при использовании TLS — TCP 5349, а также
настроенный UDP relay range. После перезапуска проверьте выдачу сервиса:

```bash
prosodyctl check turn
```

Без собственного TURN Luma использует публичный STUN только для обнаружения
адресов; STUN не может ретранслировать медиапоток, поэтому звонок между двумя
сложными NAT может не установиться.

Luma проверяет ответы XEP-0215 до создания WebRTC-соединения. Для `turn`/`turns`
Prosody должен выдать и `username`, и `password`; `stuns`/`turns` допускают TCP
(или отсутствие явного `transport`), а истёкшие временные credentials
игнорируются. Если одна серверная конфигурация всё же не принимается WebRTC,
клиент повторяет запуск с публичным STUN, затем с прямыми host candidates. В
Debug-консоли при таком fallback появляется строка `Luma WebRTC:` без URL и
учётных данных.

Для группового OMEMO комната должна быть неанонимной; рекомендуется также
members-only. При создании комнаты Luma сама отправляет owner configuration с
`muc#roomconfig_whois = anyone`, `muc#roomconfig_membersonly = true` и
`muc#roomconfig_persistentroom = true`, а также разрешает ролям moderator и
participant читать member list. Для уже существующей комнаты включите в
настройках владельца показ реальных JID всем участникам и доступ к списку
участников. Если вошедший
пользователь — владелец, Luma попробует изменить `whois` при первой зашифрованной
отправке; обычный участник не может менять эту настройку.

В Prosody 0.12.x срок хранения задаётся числом секунд, например
`http_file_share_expires_after = 31 * 24 * 60 * 60`; строковый интервал выше
используйте на Prosody 13.

Для `upload.example.org` нужен корректный HTTPS URL. Если компонент не является
прямым поддоменом VirtualHost, добавьте его в `disco_items`. При reverse proxy
задайте `http_host`/`http_external_url` согласно вашей топологии. Например, для
`example.com` за HTTPS reverse proxy:

```lua
Component "upload.example.com" "http_file_share"
    http_file_share_size_limit = 1024 * 1024 * 1024
    http_host = "upload.example.com"
    http_external_url = "https://upload.example.com/"
    trusted_proxies = { "127.0.0.1", "::1" }
    modules_disabled = { "s2s" }
```

Reverse proxy должен передавать `Host: upload.example.com` и
`X-Forwarded-Proto: https`. Иначе Prosody может выдать клиенту `http://` URL или
маршрут, возвращающий 404; Luma намеренно не понижает upload до HTTP.

Проверьте также:

- валидный сертификат и STARTTLS на 5222 либо direct TLS на 5223;
- SRV-записи `_xmpp-client._tcp` и, если используется, `_xmpps-client._tcp`;
- доступность server disco и upload component disco;
- права пользователей на PEP/pubsub nodes;
- доставку PEP notifications `urn:xmpp:avatar:metadata+notify` контактам;
- что MAM действительно пишет в постоянное хранилище, а не fallback memory.
- доступность `conference.example.org` через service discovery и возможность
  локального пользователя создать/войти в комнату.
- успешный `prosodyctl check turn` и доступность relay-портов coturn извне.

Полезные команды:

```bash
prosodyctl check config
prosodyctl check certs
prosodyctl shell module info http_file_share
prosodyctl shell http list upload.example.com
```

Начиная с 0.3.0 Luma различает ошибки discovery, получения upload slot,
транспортную ошибку PUT и HTTP status. Если приложение пишет, что XEP-0363 не
найден, проверьте `disco_items`; если показывает HTTP 404/413/5xx — проверяйте
`http_host`, proxy path и лимит файла соответственно.

## Push на iOS

`mod_cloud_notify` реализует серверную сторону XEP-0357, но одного включения
модуля недостаточно. Нужен доступный по XMPP push gateway разработчика Luma,
который принимает события Prosody и отправляет APNs. В текущем MVP клиент не
регистрирует такой endpoint, потому что его адрес, APNs topic и ключи зависят от
вашей Apple Developer учётной записи.

Когда gateway будет готов, включите `cloud_notify` вместе со `smacks`, `mam` и
`carbons`; не включайте передачу реального тела или sender в push без отдельного
решения по приватности.

### Совместимость с сервером Monal

Можно использовать открытый сервер
[`monal-im/fpush`](https://github.com/monal-im/fpush), но его нужно развернуть
для Luma либо договориться с владельцем уже работающего экземпляра о добавлении
отдельного push-модуля. Подключить Luma к production endpoint Monal как к
универсальному APNs relay нельзя: APNs device token относится к конкретному
приложению, а gateway должен подписывать запросы сертификатом этого приложения
и указывать его bundle ID (`app.luma.chat`) как topic.

`fpush` подключается к Prosody как XEP-0114 component и поддерживает несколько
приложений через `pushModule`. Минимальная конфигурация его APNs-модуля выглядит
так (секреты и сертификат не храните в репозитории):

```json
{
  "component": {
    "componentHostname": "push.example.org",
    "componentKey": "CHANGE_ME",
    "serverHostname": "127.0.0.1",
    "serverPort": 5347
  },
  "pushModules": {
    "lumaProdIOS": {
      "type": "apple",
      "is_default_module": true,
      "apns": {
        "certFilePath": "/run/secrets/luma-apns.p12",
        "certPassword": "CHANGE_ME",
        "topic": "app.luma.chat",
        "environment": "production"
      },
      "ratelimit": {
        "ratelimitTime": "20s",
        "ratelimitCleanupInterval": "300s",
        "enabled": true
      }
    }
  },
  "timeout": { "xmppconnectionError": "20s" }
}
```

Для полного подключения ещё нужны:

1. Push Notifications capability и подходящий provisioning profile для Luma.
2. Регистрация iOS-приложения в APNs и получение device token.
3. Отправка XEP-0357 `<enable/>` с `node` = APNs token, JID компонента и полем
   `pushModule=lumaProdIOS`; `<disable/>` при выходе из аккаунта.
4. `smacks`, `mam`, `carbons`, `cloud_notify` в Prosody и доступ компонента
   `push.example.org` по component-порту или s2s — в зависимости от схемы
   развёртывания.

Без APNs credentials от Apple Developer аккаунта приложение продолжит
показывать только уже реализованные локальные уведомления, пока процесс жив.
