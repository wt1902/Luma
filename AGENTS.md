# Repository Guidelines

Luma is an XMPP client for iOS, iPadOS, macOS, and watchOS, built with SwiftUI
and the Martin / MartinOMEMO libraries. The Xcode project is generated from
`project.yml` by XcodeGen — never edit `Luma.xcodeproj` directly.

## Project Structure

- `Sources/App/` — iOS/macOS app entry point (`LumaApp.swift`).
- `Sources/Shared/` — shared code:
  - `Models/` — value types and pure policy enums (`ArchiveSyncPagination`,
    `ChatTypingPolicy`, …) plus the SwiftData `@Model` classes
    (`ChatMessage`, `Conversation`).
  - `UI/` — SwiftUI views; chat/contact lists read SwiftData through
    `@Query` (`MainTabView`, `ChatView`, `ForwardMessageView`); the main
    screen is Telegram-style: an iOS native `TabView` tab bar
    (Контакты/Звонки/Чаты/Настройки) with inline search fields above
    the lists, and a
    macOS Telegram Desktop-style split view (`MainSplitView`: sidebar
    with menu/search/list plus a chat detail pane).
  - `XMPP/` — `XMPPService` (MAM/OMEMO/MUC), `LumaCallEngine`, OMEMO store,
    `LumaOMEMO2Module` (urn:xmpp:omemo:2 wire format: AES-256-CBC + HMAC
    payload, SCE envelope, device/bundle PEP nodes — shares the Double
    Ratchet sessions with the legacy module), `SASLprep` (RFC 4013),
    SCRAM-SHA-512 mechanism, SASL failure observer/messages.
  - `Persistence/` — `ArchiveStore` (per-account SwiftData container),
    `ArchiveMetadataRecord` (durable MAM checkpoint metadata),
    `LegacyArchiveImporter` (one-time legacy JSON snapshot migration),
    preferences.
  - `Services/`, `Security/` — media, notifications, credentials.
- `Sources/Watch/` — single-target watchOS app.
- `Tests/` — XCTest unit tests.
- `Resources/`, `Config/`, `Brand/`, `Docs/` — assets, plists/entitlements,
  icons, architecture/security docs.

## Build, Test & Development

- `make project` — regenerate `Luma.xcodeproj` from `project.yml`
  (requires `brew install xcodegen`).
- `make open` — regenerate and open Xcode.
- `make verify` — run `Scripts/verify.sh`: grep-based structural invariants
  plus an optional simulator build.
- `make clean` — remove the generated project and DerivedData.
- `xcodebuild test -project Luma.xcodeproj -scheme Luma \
-destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'` — build and
  run the test suite.

## Coding Style

- Swift 5.9; 4-space indentation (set in `project.yml`).
- UI-facing state is `@MainActor` (`AppModel`, `XMPPService`); keep heavy work
  (OMEMO decryption, media, persistence) off the main actor.
- Prefer small, pure value types and unit-testable policy enums over inline
  branching.
- UI strings are Russian; identifiers and code comments are English.
- No formatter/linter; `Scripts/verify.sh` is the guard — keep its greps in
  sync when you change constants or symbols.

## Testing

- XCTest with `@testable import Luma`; one file per model/policy
  (e.g., `ArchiveSyncPaginationTests.swift`), methods named `test...`.
- Unit-test pure logic (policies, pagination, checkpoints); network/UI flows
  are verified manually.
- When a policy constant changes, update the matching `Tests/*` assertions and
  the `Scripts/verify.sh` guard in the same commit.

## Commit & Pull Request

- Short, imperative, English subject lines (see `git log`: "mam fixes",
  "fix errors and warnings").
- CI (`.github/workflows/ios.yml`) runs `xcodebuild test` on push to
  `main`/`develop` and on PRs to `main`; PRs must keep it green.
- Update `README.md` / `Docs/*` whenever behaviour or architecture changes.
