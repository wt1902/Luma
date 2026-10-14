# Luma UI Kit — стандарт интерфейса

Версия документа: 1.0. Дата фиксации: 14 октября 2026 года.

Документ фиксирует существующий дизайн Luma для повторного использования в новых экранах и при сопровождении. Здесь UI Kit означает библиотеку визуальных правил и компонентов продукта; приложение написано преимущественно на SwiftUI, а не на одноимённом UIKit framework.

Основание: текущие `Sources/App`, `Sources/Shared/UI`, UI policies в `Sources/Shared/Models`, `Sources/Watch/WatchViews.swift`, ресурсы цвета и `project.yml`. Исходный коммит: `6969863d1e4db434004f8e5e032ada270a4b948f`. Документ составлен по коду; screenshots и фактический рендеринг на устройствах в этом сеансе не получены. Системные материалы, SF Symbols и размеры semantic fonts зависят от платформы, версии ОС, настроек и accessibility.

Функциональное поведение подробнее описано в [обратном ТЗ](../tz.md). При расхождении старого описания с этим документом для текущего дизайна приоритет имеет исполняемый компонент, на который дана ссылка.

## Содержание

- [1. Правила применения](#1-правила-применения)
- [2. Визуальный характер](#2-визуальный-характер)
- [3. Палитра](#3-палитра)
- [4. Типографика](#4-типографика)
- [5. Геометрия и поверхности](#5-геометрия-и-поверхности)
- [6. Иконки](#6-иконки)
- [7. Каркас экранов](#7-каркас-экранов)
- [8. Avatar](#8-avatar)
- [9. ConversationRow и контакт](#9-conversationrow-и-контакт)
- [10. Поиск](#10-поиск)
- [11. Лента чата](#11-лента-чата)
- [12. Message bubble](#12-message-bubble)
- [13. Replies и reactions](#13-replies-и-reactions)
- [14. Composer](#14-composer)
- [15. Медиа](#15-медиа)
- [16. Call UI](#16-call-ui)
- [17. Формы и системные листы](#17-формы-и-системные-листы)
- [18. Feedback и overlays](#18-feedback-и-overlays)
- [19. Анимации и жесты](#19-анимации-и-жесты)
- [20. Watch UI](#20-watch-ui)
- [21. Состояния компонента](#21-состояния-компонента)
- [22. Текст и доступность](#22-текст-и-доступность)
- [23. Известные неоднородности](#23-известные-неоднородности)
- [24. Порядок добавления нового UI](#24-порядок-добавления-нового-ui)
- [25. Каталог компонентов и источников](#25-каталог-компонентов-и-источников)

## 1. Правила применения

- Новые экраны продолжают существующий визуальный язык: системные навигация и формы, синий accent, полупрозрачные поверхности, скруглённые элементы, SF Symbols.
- Сначала переиспользуется имеющийся компонент, затем существующий вариант, и только затем создаётся новый.
- Числа в таблицах — значения SwiftUI в points, если не указана другая единица. RGB — нормализованные значения 0…1.
- Semantic colors и font styles сохраняются как semantic, без подмены случайными HEX и фиксированным размером.
- Имена токенов в этом документе — документальные обозначения. Единого исполняемого `LumaTheme`/`DesignTokens` в проекте сейчас нет.
- «Стандарт» — правило для будущих экранов на основе текущих компонентов. «Факт/исключение» — существующая неоднородность, которая не должна автоматически распространяться на новые компоненты.
- Изменение документа само по себе не изменяет UI. Унификация разных текущих значений требует отдельного изменения приложения.

## 2. Визуальный характер

Luma сочетает нативную Apple-навигацию, Telegram-подобные списки/компоновку чата и Messages-подобную подачу ответов/анимаций. Основной контент спокойный: имя, сообщение и действие важнее декоративной рамки.

| Принцип | Применение |
| --- | --- |
| Нативность | TabView, NavigationStack, NavigationSplitView, Form, List, системные sheets/alerts/pickers |
| Акцент | Синий для действий и выбора; сине-голубой градиент исходящих |
| Полупрозрачность | Glass/material для управления и вторичных поверхностей |
| Иерархия | Primary → secondary → caption; текст не дублируется крупными декоративными заголовками |
| Разделение | Отступы и скруглённые поверхности; divider там, где меняется зона работы |
| Состояние | Иконка, текст, progress и доступность действия; цвет дополняет их |
| Контекст | Действия над сообщением — context menu, массовые — selection mode |
| Адаптация | Общие роли компонентов при разной навигации iOS/Mac/Watch |

## 3. Палитра

### 3.1. Основные цвета

| Документальный токен | Значение | Источник / использование |
| --- | --- | --- |
| `accent.root` | RGB 0.14, 0.56, 0.96 ≈ #248FF5 | `LumaApp`: `.tint(...)` |
| `accent.asset` | RGB 0.145, 0.565, 0.965 ≈ #2590F6 | `Resources/Shared.xcassets/AccentColor.colorset` |
| `text.primary` | `.primary` | Основной текст на адаптивных светлых поверхностях |
| `text.secondary` | `.secondary` | Подписи, время, вторичная информация |
| `text.onOutgoing` | `.white` | Текст исходящего bubble |
| `surface.incoming` | `.secondary.opacity(0.13)` | Входящий bubble |
| `surface.timeline` | `.secondary.opacity(0.035)` | Фон ChatView |
| `surface.photoPlaceholder` | `.secondary.opacity(0.12)` | Фотоостровок/placeholder |
| `border.media` | `.secondary.opacity(0.18)` | Рамка фото/видео, 1 pt |
| `state.success` | `.green` | Online, verified, completed call |
| `state.warning` | `.orange` | Plaintext и предупреждение |
| `state.error` | `.red` | Ошибка, destructive, неудачный звонок |
| `overlay.dark` | `.black` с локальной opacity | Viewer, подписи на media, звонок |

**Различие accent:** `.tint` на уровне корня и `Color.accentColor` из assets не являются одним числом. В новых компонентах переиспользовать `.tint`/`Color.accentColor` по роли, не добавлять третий близкий синий. Не считать таблицу результатом уже выполненной унификации.

### 3.2. Градиенты

Все перечисленные линейные градиенты направлены topLeading → bottomTrailing, кроме явно заданного источником другого направления.

| Название | RGB stops | Применение |
| --- | --- | --- |
| `gradient.auth` | (0.08, 0.38, 0.78) → (0.12, 0.62, 0.96) → (0.44, 0.84, 0.96) | LoginView, AppLockView |
| `gradient.outgoing` | (0.13, 0.51, 0.94) → (0.12, 0.63, 0.94) | Исходящее сообщение |
| `gradient.videoPlaceholder` | (0.06, 0.17, 0.29) → (0.09, 0.43, 0.64) | Видеоостровок |
| `gradient.videoNote` | (0.08, 0.30, 0.56) → (0.07, 0.64, 0.83) | Круглое видеосообщение |
| `gradient.call` | (0.11, 0.17, 0.24) → black | Экран звонка без remote video |
| `gradient.avatar` | baseColor → baseColor.opacity(0.68) | Fallback аватара |

### 3.3. Детерминированные цвета участников

Avatar fallback: hue = `colorSeed % 360 / 360`, saturation 0.68, brightness 0.88. Sender name в группе: отдельный hash JID, saturation 0.72, brightness 0.78. Цвет участника стабилен для идентичности, но avatar color и sender color не обязаны совпадать.

### 3.4. Тёмная тема

Большинство основных поверхностей использует semantic colors/materials и наследует системный color scheme. Отдельного переключателя темы или самостоятельной полной dark palette в текущей реализации нет. Auth gradients, белый текст исходящих и тёмный call/viewer сохраняют собственные цвета.

Для новых компонентов нужны light/dark проверки; документ не утверждает уже проведённый аудит контраста.

## 4. Типографика

Основной шрифт — системный SwiftUI. Название конкретного установленного семейства не закрепляется как файл шрифта.

| Роль | Стиль | Пример |
| --- | --- | --- |
| Имя чата/контакта | `.headline` | ConversationRow |
| Превью последнего сообщения | `.subheadline` | ConversationRow |
| Текст сообщения | унаследованный стандартный Text font | MessageBubble |
| Название call card | `.subheadline.weight(.semibold)` | MessageBubble |
| Подпись call card | `.caption`, opacity 0.78 | Длительность/результат |
| Время списка | `.caption`, secondary | ConversationRow |
| Метаданные bubble | `.caption2`, secondary | Время, delivery, «изм.» |
| Имя автора MUC | `.caption.weight(.semibold)` | Цветной sender name |
| Badge unread | `.caption2.bold()` | Белый текст capsule |
| Compact reply | `.callout.weight(.medium)` | Однострочная цитата |
| Пояснение формы | `.caption` / `.footnote` по экрану | Login, настройки, группа |
| Fingerprint | `.system(.caption, design: .monospaced)` | Шифрование |
| Таймер/длительность | `.monospacedDigit()` | Запись, player, звонок |
| Бренд login | system 42, bold, rounded | «Luma» |
| Имя в active call | system 30, semibold, rounded | До двух строк |
| Lock heading | `.title2.weight(.bold)` | «Luma заблокирован» |

Не превращать `.headline` в произвольные «17 px» в переносимом стандарте: semantic style может меняться платформой и Dynamic Type. Фиксированные sizes из таблицы применяются именно к указанным special components.

Обрезка: имя/preview списка — одна строка; имя звонящего — две; toast — две; compact reply — одна. Основной message body не обрезается правилом preview.

## 5. Геометрия и поверхности

### 5.1. Повторяющиеся интервалы

В реализации встречаются интервалы 3/4/5/6/7/8/10/12/13/14/16/18/22/24/28. Это не строго реализованная сетка кратности четырём. При повторении существующего компонента использовать его реальные значения.

| Роль | Значение |
| --- | --- |
| Между avatar и текстом списка | 12 |
| Между строками текста списка | 5 |
| Horizontal row insets списка чатов | 12 |
| Vertical listRowInsets чатов | 6 |
| Дополнительный vertical padding ConversationRow | 2 |
| Horizontal padding message row | 12 |
| Text/file bubble внутренний padding | horizontal 13, vertical 9 |
| Audio/voice bubble padding | horizontal 13, vertical 10 |
| Composer основной gap | 8 |
| Composer horizontal padding | 10 |
| Composer bottom / top | 8 / 6 |
| Input leading / trailing / vertical | 14 / 12 / 9 |
| Auth screen horizontal / vertical padding | 24 / 48 |

### 5.2. Формы

| Роль | Форма |
| --- | --- |
| Avatar, online dot, call control | Circle |
| Unread badge, media caption, toast, reactions | Capsule |
| Auth/lock card | RoundedRectangle continuous, radius 28 |
| Composer input | Glass rect, radius 21 |
| Photo/video island | RoundedRectangle continuous, radius 20 |
| Compact reply | RoundedRectangle continuous, radius 17 |
| Reply thumbnail | RoundedRectangle continuous, radius 6 |
| Attachment caption field | RoundedRectangle, radius 16 |
| Watch message | RoundedRectangle, radius 11 |
| Call local-video preview | RoundedRectangle continuous, radius 22 |
| Основной message bubble | Собственный ChatBubbleShape |

**Фактическая форма bubble:** `MessageBubble.messageBubbleShape` возвращает `ChatBubbleShape(isOutgoing:)`. Его path содержит нижний хвостик/асимметрию на стороне сообщения и опорные скругления около 20 pt. Не заменять его обычным RoundedRectangle при реализации «такого же» текстового bubble. Старые формулировки README/tz об отсутствии хвостиков расходятся с этим исполняемым shape. Фото/видео имеют независимую островковую рамку.

### 5.3. Материалы

- `.glassEffect()` — search field общего компонента, login inputs, composer controls, часть новых/платформенных действий.
- `.glassEffect(in: .rect(cornerRadius: 21))` — composer input.
- `.regularMaterial` — login/lock card и toast.
- `.ultraThinMaterial` — selection panel, нижняя панель предпросмотра вложений и другие явно заданные контекстом поверхности.
- `.buttonStyle(.glassProminent)` — основное действие login и ряд Mac forms.
- `.buttonStyle(.borderedProminent)` — часть системных forms, lock, attachment send, Watch.
- `.buttonStyle(.plain)` — управление внутри списка/bubble/player, где оформление рисует компонент.

Это несколько существующих контекстных вариантов, не требование заменить каждую кнопку на glass. Внешний вид материала не закрепляется статическим цветом.

### 5.4. Тени и границы

| Компонент | Значение |
| --- | --- |
| Login card | black opacity 0.14, radius 24, y 12 |
| Login logo tile | black opacity 0.16, radius 22, y 10 |
| Toast | black opacity 0.18, radius 12, y 4; border primary opacity 0.06 |
| Avatar звонящего | black opacity 0.32, radius 28, y 14; white border opacity 0.14, 1 pt |
| Local video | black opacity 0.38, radius 16, y 8; white border opacity 0.24, 1 pt |
| Media island | secondary border opacity 0.18, 1 pt |
| Reaction | 0.8 pt border; цвет зависит от own state |

На обычную строку чата не добавляется карточная тень. Использовать тень как отделение overlay/крупного элемента, а не универсальный декор.

## 6. Иконки

Основной набор — SF Symbols. Размер и weight задаются по компоненту; пользовательское действие имеет accessibility label, если состоит только из icon.

| Роль | Symbol |
| --- | --- |
| Контакты / звонки / чаты / настройки | `person.circle.fill` / `phone.fill` / `bubble.left.and.bubble.right.fill` / `gearshape.fill` |
| Поиск / очистить | `magnifyingglass` / `xmark.circle.fill` |
| Новый личный / групповой | `square.and.pencil` / `person.3.fill` |
| Вложение | Знак `+` в composer; набор файлов — `doc.on.doc` |
| Отправка | `arrow.up`; в preview — `arrow.up.circle.fill` |
| Emoji / voice / videoNote | `face.smiling` / `mic.fill` / `video.circle` |
| Location | `location.fill` |
| Ответ / пересылка | `arrowshape.turn.up.left` / `arrowshape.turn.up.right` |
| Редактирование / сохранить файл | `pencil` / `square.and.arrow.down` |
| Удалить / retract | `trash` / `trash.slash` |
| OMEMO / plaintext / decrypt error | `lock.fill` или `lock.shield.fill` по контексту / `lock.open` / `exclamationmark.shield` |
| Play / pause | `play.fill` / `pause.fill` |
| Раскрыть media | `arrow.up.left.and.arrow.down.right` |
| Звонок завершить | `phone.down.fill` |
| Switch camera | `camera.rotate.fill` |
| Toast success | `checkmark.circle.fill` |

Не заменять SF Symbols emoji в функциональных icon buttons. Emoji допустимы как пользовательские реакции и текстовый preview типов сообщений.

## 7. Каркас экранов

### 7.1. iOS/iPadOS

Native TabView: **Контакты → Звонки → Чаты → Настройки**. Начальный выбор — Чаты. Иконки selected/unselected сейчас одинаковые по SF name; выделение даёт системный tab UI.

Каждый сценарий использует NavigationStack соответствующего контекста. В pushed ChatView tab bar скрывается и восстанавливается при возврате. Верхний поиск списка остаётся над строками; `.searchable` и общий SearchField — существующие разные реализации, их итоговое расположение проверяется UI tests.

iPhone: portrait и обе landscape. iPad: все четыре orientation. Отдельная фиксированная desktop-sidebar ширина не переносится автоматически на iPad.

### 7.2. macOS

NavigationSplitView: sidebar + detail. Sidebar width min 240, ideal 290, max 380. Минимальный общий размер 840 × 560, default app window 1080 × 720.

Слева переключение режимов, поиск и список. Справа выбранный чат/контакт/звонок либо соответствующий empty state, настройки в своём контексте. Режимы: Чаты, Контакты, Звонки, Настройки. Новые chat/group actions — toolbar с `.help`.

Используются нативные SavePanel, QuickLook и AppKit интеграции; iPhone fullscreen не следует буквально имитировать отдельным окном Mac.

### 7.3. Watch

NavigationStack → List чатов → List истории/ответов. Нет нижней панели четырёх вкладок. Компактные semantic fonts и системные кнопки, самостоятельные упрощённые message bubbles. Не переносить размеры 268 pt media cards на экран часов.

## 8. Avatar

Источник: `Sources/Shared/UI/Components/AvatarView.swift`.

| Параметр | Значение |
| --- | --- |
| Default size | 50 × 50 |
| В профиле settings | 64 × 64 |
| В active call | 132 × 132 |
| Image | scaledToFill, clip Circle |
| Инициалы | size ×0.35, semibold, rounded, white |
| Group fallback icon | `person.3.fill`, size ×0.31, semibold, white |
| Online/joined dot | size ×0.25, green, bottomTrailing |
| Dot border | background, 2.5 pt |

Для direct dot означает online, для group — joined. Он не обозначает новое сообщение. Fallback color детерминирован по JID. Accessibility label включает имя и статус.

## 9. ConversationRow и контакт

Источник: `ConversationRow.swift`, `MainTabView.swift`.

Композиция: avatar слева, две строки текста, справа время сверху и unread снизу. Верхняя строка — имя headline и время caption secondary. Нижняя — group/encryption indicator, preview subheadline secondary, optional group count и unread badge.

- Preview заменяется JID, если lastMessage пуст.
- Время не показывается для distantPast.
- Direct lock icon показывается при непустом lastMessage; plaintext icon orange.
- Unread badge только при count >0; текст `min(count,99)`, именно «99», без «99+».
- Badge horizontal padding 7, vertical 3, white text, tint capsule.
- Имя и preview lineLimit 1.
- При нескольких аккаунтах подпись account JID caption2 secondary, leading padding 52.
- Contact rows используют имя, JID/статус и group subtitle; не вся строка contact обязана содержать preview последнего сообщения.

Пустые списки используют ContentUnavailableView с русским заголовком, SF Symbol и пояснением. Search-empty и data-empty различаются текстом.

## 10. Поиск

Общий SearchField:

- HStack gap 6;
- magnifyingglass и clear icon — 13 pt;
- input plain, autocorrection off, iOS autocapitalization never;
- clear button только при непустом вводе;
- внутренние отступы horizontal 10, vertical 7;
- glassEffect;
- внешние horizontal 12, vertical 6.

Существующие `.searchable` поля сохраняют нативную геометрию. Документ не предписывает эти padding нативному SearchField ОС. Главное правило размещения — над списком и в его контексте.

## 11. Лента чата

Лента занимает доступную ширину; incoming слева, outgoing справа. Message row HStack gap 8, horizontal padding 12. Противоположный spacer: минимум 54 для немедийных сообщений и 16 для media.

Внутри message stack gap 4. Group incoming имеет имя автора над содержимым с horizontal padding 8. Метаданные и reactions располагаются рядом с сообщением в его выравнивании, не в отдельной колонке списка.

Outer vertical padding MessageBubble: 7 для photo/video, 2 для остальных. Photo/video компонент добавляет собственные 5 vertical; не заменять эти два уровня одним случайным gap.

Даты показаны разделителями с локализованной датой. Фон timeline — secondary opacity 0.035. Подгрузка сверху должна сохранять позицию чтения. Кнопка вниз — 46 ×46, trailing 14, bottom 12.

## 12. Message bubble

### 12.1. Текст и файл

Incoming: semantic primary foreground + secondary opacity 0.13 background. Outgoing: white foreground + синий градиент. Text/file padding 13×9; shape — ChatBubbleShape. Audio/voice используют тот же background/shape с padding 13×10.

Обычный body — Text, на Mac доступно textSelection. Файл — кнопка с mediaContent и системной иконкой. System не означает всегда одинаковый серый центрированный label: call card и tombstone имеют свои варианты.

### 12.2. Metadata

HStack gap 4, font caption2, secondary, horizontal padding 4. Содержит security warning при необходимости, «изм.», время hour/minute и для outgoing delivery icon/text. У call card delivery indicator не показывается.

| Delivery | Icon | Текущий текст |
| --- | --- | --- |
| sending | `clock` | `Sending...` |
| sent | `checkmark` | `Sended` |
| delivered | `checkmark.circle.dotted` | `Delivered` |
| failed | `exclamationmark.circle.fill`, red | `Error` |
| read | `checkmark.circle.fill` | `Read` |

Это зафиксированные исключения русской локализации, включая опечатку `Sended`. Для новых строк стандарт — русский; автоматическая замена перечисленных строк этим документом не выполнена.

### 12.3. Удалённое сообщение

`trash.slash` + «Сообщение удалено», subheadline italic, gap 7, padding 13×9, прежнее directional background/shape. Outgoing foreground white opacity 0.86, incoming secondary. Реакции, edit и прежние вложения не должны оставаться видимыми.

### 12.4. Context menu и selection

Меню включает только доступные для конкретного сообщения действия: реакция, ответ, пересылка, копирование, сохранение, повтор, редактирование, выбор, удаление у меня/у всех. Destructive actions отмечены role destructive и требуют предусмотренного сценарием подтверждения.

Selection mode показывает count и панель массовых действий, отключает swipe-reply и обычное context menu. Accessibility сообщает selected/not selected. Нельзя рисовать активную кнопку действия, которое запрещено модельным predicate.

## 13. Replies и reactions

### 13.1. Compact reply

- весь reference opacity 0.56;
- ширина max 230, высота min 34;
- callout medium, lineLimit 1;
- radius 17, vertical padding 7;
- leading/trailing 10/12 по направлению;
- background primary opacity 0.018;
- border replyColor opacity 0.75, width 1.25;
- optional thumbnail 27×27, radius 6;
- дуга 58×34, stroke 2.4, round caps, offset ±18;
- направление отражает исходное сообщение, а не только новый ответ.

При наличии target нажатие открывает фокус ветки; legacy preview без id выглядит цитатой, но не притворяется существующей ссылкой. ReplyThreadOverlay — отдельный затемнённый focus context с root/ответами и bracket; не является новым экраном полноценного канала.

### 13.2. Reaction chip

Strip gap 5. Chip: emoji + count, внутренний gap 3, padding horizontal 8/vertical 4, Capsule. Count caption2 semibold.

| Состояние | Background | Border |
| --- | --- | --- |
| Есть own reaction | accent opacity 0.20 | accent opacity 0.55, 0.8 pt |
| Только чужие | secondary opacity 0.12 | secondary opacity 0.16, 0.8 pt |

Тап по chip переключает собственную реакцию. Quick choices: 👍 ❤️ 😂 😮 😢 🔥.

### 13.3. EmojiPicker

Заголовок «Выберите эмодзи», кнопка «Готово», grid и горизонтальные category icons снизу. Adaptive grid min 44, column gap 4, row gap 6; emoji font 28, cell 46×46. Selected category — accent background opacity 0.15, radius 10, icon 18 medium, button 44×44. Minimum height 360, macOS min width 380. Текстового поиска сейчас нет.

## 14. Composer

Основная горизонталь: attachment button → input → send/record. HStack выровнен bottom. Composer прозрачен; input/control имеют собственную glass surface.

Input: min height 42, radius 21, padding leading 14/trailing 12/vertical 9. TextField vertical axis, 1…6 строк. Placeholder «Сообщение» либо «Изменить сообщение». Emoji icon 20 regular, secondary.

Send: 42×42, arrow.up 18 bold, accent при доступности, secondary при disabled, glassEffect. При пустом draft вместо send — record control. Attachment control также 42×42.

Reply/edit banner располагается внутри input над полем, с цветной вертикалью и явной отменой. Selection mode заменяет обычную зону ввода панелью выбранных сообщений. Во время capture вместо поля показываются recording strip/timer/cancel/lock hints.

Для нового composer-действия: сохранять текущую высоту соседних controls, учитывать multiline expansion и не перекрывать safe area/клавиатуру.

## 15. Медиа

### 15.1. Фото/видеоостровок

| Параметр | Значение |
| --- | --- |
| Width | 268 |
| Photo height | natural по ratio, clamp 164…328 |
| Photo ratio clamp | 0.45…2.2, fallback 4:3 |
| Внутренний inset thumbnail | 6 |
| Radius / border | 20 / 1 pt secondary opacity 0.18 |
| Thumbnail mode | scaledToFit |
| Верхний expand icon | caption bold, padding 7, black opacity 0.42 circle |
| Нижняя подпись | caption2 semibold, white, padding 8×5, black opacity 0.48 capsule |
| Overlay inset | 9 |

Видео использует аналогичную рамку и свой расчёт islandHeight по thumbnail. Центральный play 22 bold, padding 15, black opacity 0.38. Loading заменяет/сопровождает соответствующий control. Не растягивать bitmap с нарушением ratio и не заменять fit на crop для обычного media island.

### 15.2. Voice/audio

Player content width 252. Play/pause 44×44, symbol 18 bold. Voice waveform height 30; seek track — 3 pt с knob 9×9 в соответствующем компоненте. Duration caption2 monospacedDigit. Speed chip caption bold, padding 6×3, accent opacity 0.14. Скорости 1×/1.5×/2×. Audio filename subheadline semibold.

Цвета управления учитывают incoming/outgoing: на синем bubble белые/полупрозрачные элементы, на incoming semantic/accent. Player должен показывать loading, paused, playing и progress.

### 15.3. VideoNote

Circle diameter 144 в покое и 176 при playback. Play symbol 24 bold с padding 17 и black opacity 0.34. Duration badge caption2 monospacedDigit semibold, padding 7×3, black opacity 0.48; container inset 12. Border white opacity 0.18, 1 pt.

Увеличение — spring response 0.32, damping 0.82. После завершения/исчезновения/запуска другого exclusive media возвращается к stopped presentation.

### 15.4. Attachment preview перед отправкой

NavigationStack, title «Перед отправкой», scroll grid, divider, нижняя material panel. Grid adaptive min 128/max 190, column gap 18, row gap 22, outer padding 16. Нижняя панель gap 10/padding 14, ultraThinMaterial.

Caption 1…4 строки, padding 13×10, secondary opacity 0.10, radius 16. Кнопка «Отправить»/«Отправка…», borderedProminent, disabled при пустом наборе/отправке. Неудача — красная caption с retry icon; failed drafts остаются видимыми. На Mac minimum 560×560.

### 15.5. Fullscreen viewer

MediaViewer поверх всего основного окна. Тёмный фон, исходное фото с zoom/pan либо системное видео. Свайп вертикально закрывает; увеличенное фото продолжает pan. Отдельный обязательный крестик не является текущим паттерном. Для обычных файлов используется системный QuickLook, не imitation media viewer.

## 16. Call UI

Full-window тёмная сцена, white foreground, крупное имя, статус и controls снизу. Remote video занимает фон; локальное — верхняя правая карточка 118×168, radius 22, top 92/trailing 18.

Без remote video: тёмный градиент, декоративный accent circle 440, opacity 0.24. Avatar 132, имя 30 semibold rounded, два ряда максимум. Подпись типа звонка subheadline white opacity 0.66; статус subheadline monospacedDigit white opacity 0.72.

Call control: круг 58×58, symbol 24 semibold, caption ниже. Incoming: decline red и answer green, horizontal gap 52. Active controls: полупрозрачные белые круги opacity 0.18/0.34 по состоянию, mic/camera/speaker/rotate; hangup red отдельно. Speaker control платформенно iOS.

History card в чате: icon circle 42, направление badge, content gap 12, title subheadline semibold, subtitle caption opacity 0.78, padding 14×10, max width 300. Completed accent green; declined/missed/unanswered/failed red; cancelled/answeredElsewhere secondary. Outgoing foreground white.

## 17. Формы и системные листы

### 17.1. Login

Полноэкранный auth gradient; контент max width 460, horizontal padding 24, vertical 48. Brand block: белая tile 88×88, radius 26, symbol 39 semibold, название 42 bold rounded.

Карточка regularMaterial, radius 28, padding 26, main spacing 18. Поля и дополнительный DisclosureGroup. Main action glassProminent, large control size, inner content height 34; spinner при подключении. Кнопка видимости пароля имеет label и не заменяет SecureField молча.

### 17.2. Settings / new chat / group / encryption

Переиспользуются Form/Section, Toggle switch, NavigationLink и нативная toolbar. Заголовки и объяснения по-русски. Main/cancel actions в стандартных toolbar placements на iOS; на Mac формы могут иметь нижнюю action row.

Ключевые settings sections: аккаунты, профиль, аккаунт, соединение, шифрование, уведомления, блокировка, приватность чата. Profile avatar 64; fingerprint monospaced caption selectable. Device trust: verified green, trusted blue, undecided orange, compromised red; protocol badge различает OMEMO 2 и legacy.

### 17.3. App lock

Auth gradient + material card radius 28/padding 28, outer padding 24; vertical spacing 22. Lock symbol 44 semibold, title2 bold white, password field max width 260, centered, roundedBorder. Кнопка «Разблокировать» borderedProminent, inner content max width 260/height 34. Error «Неверный пароль» caption medium white opacity 0.95. Биометрия — отдельная подписанная кнопка.

Lock должен скрывать underlying chat/media/call content, а не только накладывать полупрозрачный scrim на читаемую переписку.

## 18. Feedback и overlays

| Вид | Паттерн |
| --- | --- |
| Ошибка | System alert «Luma», сообщение, OK |
| Подтверждение destructive | Alert/confirmation по контексту, destructive button, Отмена |
| Короткий success | Toast capsule regularMaterial |
| Долгая операция | ProgressView и контекстный label, disabled controls |
| Empty state | ContentUnavailableView с SF Symbol и пояснением |
| Connection status | ConnectionBanner в контексте заголовка |

Toast: gap 8, subheadline medium, horizontal padding 16/vertical 10, top 8, максимум две строки, auto dismiss 2.5 с, checkmark.circle.fill accent.

ConnectionBanner фактически использует caption white и mini white ProgressView в состояниях «Подключение», «Ожидание сети», «Обновление». В обычном ready state — переданный заголовок headline. Контраст этого white banner на любой возможной светлой поверхности не подтверждён; не считать его универсальной готовой плашкой для любого фона.

Root layering: main → media viewer z100 → call z200 → toast z300. Lock выбирается вместо основного набора слоёв. QuickLook — отдельная системная презентация.

## 19. Анимации и жесты

| Эффект | Значение |
| --- | --- |
| Открытие timeline | Последние 12 rows; stagger 35 мс; rise 16; scale 0.94 |
| Lifetime entrance | 0.75 с |
| Outgoing launch | scale 0.2, rise 12 |
| Incoming launch | scale 0.4, rise 10 |
| Append spring | response 0.44, damping 0.68 |
| History burst | Более 4 appended rows не анимируются как отдельные fresh sends |
| Root account change | easeInOut 0.22 с |
| Root media/call | easeInOut 0.2 с |
| Toast | spring response 0.3, damping 0.85 |
| Composer capture switch | easeInOut 0.18 с |
| Reply swipe return | spring response 0.24, damping 0.82 |

Reply swipe: горизонтальный trigger 64; activation 24; maximum visual offset 76; lock dominance 1.6/follow 1.05. Gesture starts на bubble, не на пустом пространстве/metadata. При достижении порога — light haptic на iOS. Вертикальная прокрутка должна оставаться приоритетной.

Media dismiss: vertical минимум 8, dominance 1.15; distance clamp 88…140 в зависимости от 14% height либо predicted endpoint 1.35×threshold. Не смешивать этот gesture с pan zoomed photo.

Record: long press около 0.22–0.24 с, cancel left 92, lock up 78. UI отражает recording/finalizing и не обещает отправку до завершения recorder.

Анимационные значения отражают код; независимый тест Reduce Motion не выполнен. Для новых анимаций требуется проверить accessibility settings и отсутствие повторной анимации при archive updates.

## 20. Watch UI

| Компонент | Стандарт |
| --- | --- |
| Chat list | Native List, имя headline, preview caption secondary, one line |
| Unread | caption2 bold, padding 5, blue Circle, исходное число |
| Message | padding 7, radius 11, outgoing blue, incoming secondary opacity 0.25 |
| Time | caption2, opacity 0.7 |
| Message spacing | inner VStack 3, opposite spacer min 16 |
| Reply | TextField «Ответ», кнопка «Отправить», disabled при пустом тексте |
| Quick replies | «Хорошо», «Спасибо!», «Отвечу позже» |
| Voice idle | prominent red «Записать голосовое» |
| Voice recording | red timer/progress, «Отмена» и «Готово» |
| Voice preview | play/pause, duration, «Отправить голосовое», destructive «Удалить запись» |
| Transfer status | caption2 secondary label с iPhone symbol |

Watch outgoing использует Color.blue, не gradient.outgoing телефона. Это намеренно зафиксированный платформенный вариант. На Watch unread сейчас не ограничивается 99, в отличие от ConversationRow.

## 21. Состояния компонента

Для каждого нового интерактивного компонента определять применимые состояния:

| Состояние | Отображение / действие |
| --- | --- |
| Default | Обычная поверхность и основное содержимое |
| Pressed | Нативный button style либо существующая feedback-анимация |
| Disabled | `.disabled`, secondary/системное приглушение; действие недоступно |
| Loading | ProgressView вместо/рядом с control, без ложного success |
| Empty | Объяснение и применимое next action |
| Error | Контекстный текст/alert, явная возможность retry где предусмотрено |
| Selected | Существующий accent/outline/check и accessibility state |
| Incoming/outgoing | Выравнивание, цвет, metadata и shape по направлению |
| Light/dark | Semantic foreground/background либо explicit inverse scene |
| Focused | Системный keyboard/focus behavior; поле не скрыто overlay |

Не всем компонентам нужны все состояния. Сеть/OMEMO predicates определяют доступность; UI Kit не отменяет функциональные ограничения `tz.md`.

## 22. Текст и доступность

- Основной язык новых UI строк — русский, короткие глаголы: «Отправить», «Сохранить», «Отмена», «Готово».
- Progress label обозначает действие: «Подключение…», «Отправка…», «Соединение…».
- Ошибка объясняет доступное пользователю действие, а не только внутренний enum.
- Destructive действия должны различать «Удалить у меня» и «Удалить у всех».
- Иконки без текста имеют accessibilityLabel; медиа — label/hint; selected state сообщается текстом.
- Время и меняющиеся числа используют monospacedDigit в соответствующих компактных controls.
- Существуют identifiers `chat-timeline`, `bubble-<id>`, `reply-banner`, `info-toast`; сохранять их при визуальном рефакторинге.
- Не заявлять аудит VoiceOver/Dynamic Type/contrast только по наличию modifiers. Это отдельная проверка на устройствах.
- Контрольная рамка composer 42×42 — факт текущего кода, а не гарантия минимального 44×44 hit area у каждой кнопки. При расширении доступности проверять effective hit target отдельно.

## 23. Известные неоднородности

| Область | Факт | Как использовать дальше |
| --- | --- | --- |
| Accent | root и asset отличаются | Переиспользовать semantic accent; унификация отдельно |
| Bubble | Custom shape с хвостиком, старые тексты говорят обратное | Текущий shape — эталон существующего bubble |
| Delivery labels | Английские строки и `Sended` | Не распространять на новые тексты; исправление отдельно |
| Search | Shared custom и native searchable | Сохранять верхнее расположение, не считать padding общим для native |
| Buttons | Glass и borderedProminent | Выбирать по существующему контексту |
| Spacing | Нет единой 4-pt системы | Копировать конкретный pattern, не выдумывать новую сетку |
| Watch accent/badge | Color.blue, число без clamp99 | Платформенный вариант |
| Connection banner | White foreground на прозрачной поверхности | Проверить контраст в месте использования |
| Responsive media | Фиксированная ширина 268 | Проверять узкую ширину и большой Dynamic Type |
| Dark/accessibility | Semantic база, без полного аудита | Проверять каждое изменение на Apple runtimes |

## 24. Порядок добавления нового UI

1. Выбрать ближайший существующий экран и компонент из каталога ниже.
2. Описать цель, primary action и применимые состояния.
3. Сохранить navigation pattern платформы.
4. Использовать semantic text/colors; специальные значения взять из соответствующей таблицы.
5. Переиспользовать AvatarView, player, media preview, toast, форму или bubble вместо копирования логики.
6. Проверить loading/error/disabled/empty, keyboard, selection и доступность действия.
7. Проверить light/dark, маленькое/большое окно, iPhone landscape, Dynamic Type и VoiceOver, если затронуты.
8. При изменении существующего pattern обновить этот документ и связанные previews/UI tests; при изменении функциональной политики — также tz.md/tests/verify guard.

### Чек-лист визуальной приёмки

- [ ] Экран выглядит частью Luma и использует подходящий platform shell.
- [ ] Accent, typography и material роли совпадают с соседними экранами.
- [ ] Нет нового близкого синего или случайного radius вместо имеющегося компонента.
- [ ] Long names/body, empty state и ошибки не ломают layout.
- [ ] Media не обрезается неожиданно и не выходит за рамку.
- [ ] Incoming/outgoing/selected/disabled различимы.
- [ ] Scroll/reply swipe/media pan не конфликтуют.
- [ ] Loading не оставляет вечный блокирующий spinner.
- [ ] Controls доступны клавиатуре/VoiceOver по применимости.
- [ ] Системные safe areas, toolbar/tab bar и overlays не перекрывают важный контент.
- [ ] Проверены платформы, затронутые изменением.

## 25. Каталог компонентов и источников

Пути относительно корня репозитория. Исходник компонента содержит окончательные значения локальной геометрии и платформенные ветви.

| Область | Эталон |
| --- | --- |
| App tint / window | `Sources/App/LumaApp.swift` |
| Layering / toast / alert | `Sources/Shared/UI/RootView.swift` |
| Navigation / search / lists | `Sources/Shared/UI/MainTabView.swift` |
| List row / avatar / connection | `Sources/Shared/UI/Components/ConversationRow.swift`, `AvatarView.swift`, `ConnectionBanner.swift` |
| Timeline / composer / selection | `Sources/Shared/UI/ChatView.swift` |
| Message / reaction / metadata | `Sources/Shared/UI/Components/MessageBubble.swift` |
| Bubble shape | `Sources/Shared/UI/Components/ChatBubbleShape.swift` |
| Reply curves / focus | `Sources/Shared/UI/Components/BubbleShapes.swift`, `ReplyThreadOverlay.swift` |
| Photo / video / videoNote | `Sources/Shared/UI/Components/PhotoAttachmentPreview.swift`, `VideoAttachmentPreview.swift`, `VideoNotePreview.swift` |
| Voice / audio | `Sources/Shared/UI/Components/AudioMessagePlayer.swift` |
| Viewer | `Sources/Shared/UI/Components/MediaViewer.swift` |
| Emoji | `Sources/Shared/UI/Components/EmojiPickerView.swift` |
| Attachment preparation UI | `Sources/Shared/UI/AttachmentPreviewView.swift` |
| Calls | `Sources/Shared/UI/CallView.swift`, `Components/RTCVideoRendererView.swift` |
| Login / lock | `Sources/Shared/UI/LoginView.swift`, `AppLockView.swift` |
| Settings / encryption | `Sources/Shared/UI/SettingsView.swift`, `EncryptionDevicesView.swift` |
| New chat/group / group info | `Sources/Shared/UI/NewChatView.swift`, `NewGroupView.swift`, `GroupInfoView.swift` |
| Forward / location | `Sources/Shared/UI/ForwardMessageView.swift`, `LocationPickerView.swift`, `Components/LocationMessagePreview.swift` |
| Camera capture | `Sources/Shared/UI/SystemPhotoCameraView.swift`, `VideoNoteCaptureView.swift` |
| Server diagnostics | `Sources/Shared/UI/ServerInfoView.swift` |
| Preview fixtures | `Sources/Shared/UI/PreviewSupport.swift` и локальные `#Preview` |
| Animation / gestures | `Sources/Shared/Models/ChatMessageEntrancePolicy.swift`, `MessageReplySwipePolicy.swift`, `ChatScrollPositionPolicy.swift` |
| Watch | `Sources/Watch/WatchViews.swift` |
| Visual regression tests | `UITests/LayoutCheckUITests.swift`, `UITests/TimelineUITests.swift` |

Документ является baseline текущего UI. Он не объявляет новый дизайн уже реализованным и не подменяет screenshots живого приложения иллюстрациями.
