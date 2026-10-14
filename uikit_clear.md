# Luma UI Kit — единый стандарт Web, Desktop и Android

Версия: 1.0. Дата: 14 октября 2026 года. Статус: целевой стандарт интерфейса.

Связанный документ: [техническое задание](tz_clear.md).

## Содержание

- [1. Назначение](#1-назначение)
- [2. Дизайн-принципы](#2-дизайн-принципы)
- [3. Единицы и токены](#3-единицы-и-токены)
- [4. Палитра](#4-палитра)
- [5. Типографика](#5-типографика)
- [6. Отступы, размеры и формы](#6-отступы-размеры-и-формы)
- [7. Поверхности, границы и elevation](#7-поверхности-границы-и-elevation)
- [8. Адаптивная компоновка](#8-адаптивная-компоновка)
- [9. Иконки](#9-иконки)
- [10. Компонент Avatar](#10-компонент-avatar)
- [11. Компонент ConversationRow](#11-компонент-conversationrow)
- [12. SearchField](#12-searchfield)
- [13. MessageRow и Bubble](#13-messagerow-и-bubble)
- [14. CompactReply и ThreadFocus](#14-compactreply-и-threadfocus)
- [15. ReactionChip и EmojiPicker](#15-reactionchip-и-emojipicker)
- [16. Composer](#16-composer)
- [17. MediaIsland и viewer](#17-mediaisland-и-viewer)
- [18. AttachmentPreview](#18-attachmentpreview)
- [19. LocationPicker](#19-locationpicker)
- [20. CallScene и CallHistoryCard](#20-callscene-и-callhistorycard)
- [21. Auth, Settings, Encryption и Lock](#21-auth-settings-encryption-и-lock)
- [22. Feedback, dialogs и слои](#22-feedback-dialogs-и-слои)
- [23. Анимации и жесты](#23-анимации-и-жесты)
- [24. Accessibility и ввод](#24-accessibility-и-ввод)
- [25. Каталог состояний и приёмка UI](#25-каталог-состояний-и-приёмка-ui)
- [26. Развитие стандарта](#26-развитие-стандарта)

## 1. Назначение

UI Kit определяет визуальный язык, токены, компоненты, состояния и адаптацию Luma для Web, Desktop и Android. Документ применяется независимо от UI framework и не требует конкретной реализации нативных материалов, шрифтов или системных иконок.

Цель — узнаваемый продукт с одинаковой иерархией и понятным поведением на разных устройствах. Совпадение физического пикселя между ОС не требуется; соответствие ролям, пропорциям и состояниям обязательно.

Документ нормативный: значения токенов реализуются централизованно, компоненты показываются в отдельном каталоге состояний. Примеры токенов и размеров не обозначают уже написанную библиотеку.

## 2. Дизайн-принципы

**UI-001.** Контент и общение находятся на первом плане. Декор не конкурирует с текстом, avatar и основным действием.

**UI-002.** Основной accent — синий. Outgoing сообщения синие, incoming нейтральные. Направление различается также выравниванием, а состояние — иконкой/подписью.

**UI-003.** Элементы округлые, поверхности спокойные, navigation и forms следуют привычкам платформы. Нет обязательного копирования внешнего вида одной ОС на другую.

**UI-004.** Полупрозрачность поддерживает иерархию, но не ухудшает чтение. При отсутствии blur/пониженной прозрачности используется определённый opaque fallback.

**UI-005.** Состояния loading/empty/error/disabled/selected являются частью компонента, а не отдельной импровизацией каждого экрана.

**UI-006.** Жест ускоряет действие, но для значимого действия есть видимый/доступный альтернативный control.

**UI-007.** Пользовательские строки — русские, короткие и точные. «Отправлено», «Доставлено» и «Прочитано» не заменяют друг друга.

**UI-008.** Маленькое окно, клавиатура, увеличение текста и reduced motion поддерживаются системно, а не исправляются после завершения дизайна.

## 3. Единицы и токены

| Величина | Web | Android | Desktop |
| --- | --- | --- | --- |
| Layout unit `u` | CSS px при стандартном масштабе | dp | Логическая единица UI, independent от device pixels |
| Размер текста | rem/em с role mapping | sp с font scale | Системный scaling / logical font size |
| Border | 1 CSS px или адаптированный hairline | 1 dp по роли | Логическая линия с корректным pixel snapping |
| Анимация | ms | ms | ms |
| Цвет | sRGB HEX + alpha | Эквивалент sRGB | Эквивалент sRGB |

При изменении device pixel ratio компонент не должен физически уменьшаться. Растровые assets поставляются в нужных масштабах; logo и функциональные icons предпочтительно в vector.

### 3.1. Обязательные группы токенов

`color.*`, `type.*`, `space.*`, `radius.*`, `size.*`, `border.*`, `shadow.*`, `motion.*`, `layer.*`, `breakpoint.*`.

Каждый токен имеет light/dark значение или единое значение, назначение и допустимое применение. Локальная константа не заменяет существующий токен тем же смыслом.

## 4. Палитра

### 4.1. Semantic colors

| Токен | Light | Dark | Назначение |
| --- | --- | --- | --- |
| `color.brand.accent` | #248FF5 | #68B5FF | Выбор, active icon, ссылка по проверенному контрасту |
| `color.action.fill` | #0969C8 | #0969C8 | Filled primary button с белым текстом |
| `color.action.onFill` | #FFFFFF | #FFFFFF | Текст primary action |
| `color.text.primary` | #172B40 | #F3F6FA | Основной текст |
| `color.text.secondary` | #526174 | #B8C3CF | Вторичный текст |
| `color.text.muted` | #5E6C7E | #A7B4C4 | Метаданные при достаточном контрасте |
| `color.surface.page` | #F4F7FA | #101821 | Фон приложения |
| `color.surface.base` | #FFFFFF | #18232F | Основные панели |
| `color.surface.raised` | #FFFFFF | #213040 | Dialog/card/popover |
| `color.surface.incoming` | #E7ECF2 | #293847 | Incoming bubble |
| `color.border.subtle` | #D7DFE8 | #3C4B5D | Divider/декоративная рамка |
| `color.border.control` | #7A899A | #8794A3 | Значимая граница control |
| `color.state.success` | #16713B | #6DDA91 | Успех/online/verified |
| `color.state.successFill` | #16713B | #16713B | Filled accept/success control, белый текст |
| `color.state.warning` | #8A4B00 | #FFC46B | Plaintext/предупреждение |
| `color.state.error` | #B4232F | #FF9199 | Ошибка/destructive text |
| `color.state.errorFill` | #B4232F | #B4232F | Destructive filled control |
| `color.state.onErrorFill` | #FFFFFF | #FFFFFF | Текст destructive filled control |
| `color.focus.ring` | #0969C8 | #8BC6FF | Keyboard focus |
| `color.overlay.scrim` | #000000 / 0.52 | #000000 / 0.64 | Модальная подложка |

Brand accent используется как цвет бренда; это не разрешение печатать мелкий белый текст на любой голубой поверхности. Filled actions используют `action.fill`. Для ссылок на светлом фоне применяется достаточно тёмный `action.fill` либо другой проверенный role token.

### 4.2. Сообщения и градиенты

| Токен | Значение | Назначение |
| --- | --- | --- |
| `gradient.message.outgoing` | #0969C8 → #0874BA | Outgoing text/audio/file bubble |
| `color.message.onOutgoing` | #FFFFFF | Основной текст outgoing |
| `color.message.outgoingMetadata` | Основной secondary вне bubble | Дата/status за пределами синей поверхности |
| `gradient.brand.hero` | #1461C7 → #1F9EF5 → #70D6F5 | Login/lock background, декоративная область |
| `gradient.media.video` | #0F2B4A → #176EA3 | Video placeholder |
| `gradient.media.videoNote` | #144D8F → #12A3D4 | VideoNote placeholder |
| `gradient.call` | #1C2B3D → #000000 | Call scene |

Направление градиентов — от верхнего левого угла к нижнему правому. Для текстовых bubbles используется тёмный сине-голубой градиент, чтобы белый body оставался читаемым; более яркий hero gradient остаётся декоративным.

Для обычного белого текста расчётный контраст с концами outgoing gradient — около 5.43:1 и 4.98:1. Контраст промежуточных цветов и всех фактических состояний проверяется при реализации. Полупрозрачный secondary text внутри bubble не должен снижать контраст ниже целевого порога.

### 4.3. Аватары и имена участников

Fallback avatar получает стабильный цвет по нормализованной identity. Цвет не меняется при rerender/перезапуске. Palette должна обеспечивать читаемый белый или тёмный foreground; случайный hue не используется без выбора контрастного текста.

Имя автора MUC может иметь устойчивый цвет, но не является единственным признаком identity. Имя остаётся читаемым в обеих темах. Цвет для имени и фон аватара могут отличаться по насыщенности.

### 4.4. Запрещённые применения

- Новый близкий синий для той же роли без добавления token.
- Белая мелкая подпись на ярком accent без проверки контраста.
- Ошибка/online/selected, различимые только цветом.
- Hardcoded light background с унаследованным dark foreground из другой темы.
- Прозрачный control без определённого фона/границы/focus state.

## 5. Типографика

Используется системный sans-serif шрифт платформы. Единая роль важнее одинакового имени font family. Fallback поддерживает кириллицу, emoji и символы JID. Mono нужен для fingerprint, не для всего интерфейса.

| Токен | Размер / line height | Weight | Применение |
| --- | --- | --- | --- |
| `type.brand` | 42 / 50 | 700 | Название на login |
| `type.hero` | 30 / 38 | 600 | Имя звонящего |
| `type.title` | 22 / 28 | 700 | Крупный заголовок формы/dialog |
| `type.heading` | 17 / 24 | 600 | Имя списка, toolbar title |
| `type.body` | 16 / 24 | 400 | Сообщение, поле, основной текст |
| `type.bodyStrong` | 16 / 24 | 600 | Выделенный текст/primary label |
| `type.subbody` | 14 / 20 | 400 | Preview списка, вторичные поля |
| `type.caption` | 12 / 16 | 400/500 | Метаданные, пояснения |
| `type.badge` | 12 / 16 | 700 | Unread/count |
| `type.mono` | 12 / 18 | 400 | Fingerprint/техническое значение |

Размеры масштабируются пользовательскими настройками; фиксированная высота row не должна обрезать увеличенный текст. Desktop compact density может уменьшать вторичный текст до 13/18, но основной message body не становится мелкой служебной подписью.

Таймеры/duration используют tabular numerals. Link/упоминания различимы, доступны клавиатуре и не ломают line wrapping.

### 5.1. Ограничение строк

- Имя и preview списка: 1 строка при обычном масштабе; при большом тексте допустим адаптивный рост.
- Имя звонящего: до 2 строк.
- Toast: до 2 строк, дальнейшее сообщение — dialog/inline error.
- Compact reply: 1 строка и ellipsis.
- Message body: без произвольного line clamp; длинный контент может иметь доступное «Показать полностью» только при отдельном согласованном лимите.
- JID/filename/fingerprint: безопасный wrap/ellipsis с возможностью прочитать/скопировать полное значение.

## 6. Отступы, размеры и формы

### 6.1. Spacing scale

| Токен | u |
| --- | --- |
| `space.1` | 4 |
| `space.2` | 8 |
| `space.3` | 12 |
| `space.4` | 16 |
| `space.5` | 20 |
| `space.6` | 24 |
| `space.7` | 32 |
| `space.8` | 40 |
| `space.9` | 48 |

Компонентные исключения допустимы для оптического выравнивания: bubble padding 13×9, input 14/12/9, metadata gap 4. Они именуются внутри компонента, не создают бессистемный глобальный scale.

### 6.2. Радиусы

| Токен | u | Применение |
| --- | --- | --- |
| `radius.small` | 6 | Reply thumbnail |
| `radius.control` | 12 | Компактная карточка/системный fallback |
| `radius.field` | 16 | Caption field |
| `radius.reply` | 17 | Compact reply |
| `radius.media` | 20 | Photo/video island |
| `radius.composer` | 21 | Поле composer |
| `radius.dialog` | 28 | Auth/dialog card |
| `radius.pill` | Половина высоты | Badge/chip/toast |
| `radius.circle` | 50% | Avatar/round control |

Message bubble имеет отдельную directional geometry: основное скругление 20, нижняя асимметрия/небольшой хвост на стороне отправителя с выступом около 4 u. Он не должен уменьшать внутреннюю область текста. Vector/path реализации обеих направлений являются зеркальными вариантами одного компонента.

Фото/видео не получают текстовый хвостик: у них самостоятельная островковая рамка.

### 6.3. Контролы

| Роль | Visual size | Hit area |
| --- | --- | --- |
| Composer send/attach/record | 42×42 | Touch min 48×48; pointer min 44×44 |
| Audio play | 44×44 | Touch min 48×48 |
| Standard icon button | 24 icon в 40/44 visual | Touch min 48×48 |
| Primary form action | Height min 48 | Вся кнопка |
| Call control | 58×58 circle | Не меньше visual size |
| Unread badge | min height 22 | Не отдельная обязательная target |
| Input | min height 44, composer visual min 42 | Не обрезается при scale |

Увеличение hit area не должно перекрывать target соседней кнопки. При узкой ширине gap и общий layout перераспределяются.

## 7. Поверхности, границы и elevation

| Уровень | Поверхность | Применение |
| --- | --- | --- |
| Page | page | Фон, timeline |
| Base | base | Sidebar, forms, основной контент |
| Raised | raised + border/elevation | Popover, dialog, floating panel |
| Glass | Полупрозрачная base surface + blur | Search/composer/toolbars |
| Inverse | Тёмная сцена + контрастный текст | Media viewer/call |

Glass light fallback: base opaque. Glass dark fallback: base opaque. При blur фон имеет достаточно непрозрачный слой для текста; blur не единственный источник читаемости. Reduced transparency отключает blur и сохраняет border.

Shadows:

- `shadow.floating`: black alpha 0.14, blur 24, offsetY 12 в light; более мягкий/ограниченный вариант в dark;
- `shadow.toast`: black alpha 0.18, blur 12, offsetY 4;
- `shadow.callPreview`: black alpha 0.38, blur 16, offsetY 8.

List row не получает отдельную тяжёлую тень. Border subtle декоративный; значимые focus/control boundaries используют более контрастный role token.

## 8. Адаптивная компоновка

### 8.1. Breakpoints

Это продуктовые диапазоны доступной ширины, а не определение типа устройства.

| Диапазон | Ширина | Layout |
| --- | --- | --- |
| Compact | <720 u | Одна основная панель, переход список → чат |
| Medium | 720…1099 u | Sidebar + detail при достаточной полезной ширине |
| Wide | ≥1100 u | Sidebar + detail, расширенная зона контента |

В medium split включается только если после sidebar остаётся минимум 400 u для detail; иначе compact. Приложение работает при viewport 320 u через reflow; специальные фиксированные размеры уменьшаются до доступной ширины.

### 8.2. Sidebar и detail

Sidebar min 240, preferred 290, max 380. Default desktop window ориентир 1080×720, рекомендуемый minimum 840×560; при фактически меньшем окне допускается compact layout, а не обрезанный недоступный контент.

Detail растёт с окном. Максимальная читаемая ширина обычного text bubble — 640 u и не более 78% доступной message row. Очень короткий текст не растягивается до максимума. Timeline может иметь центрированный content column с max 1000 u.

### 8.3. Platform shell

| Платформа/режим | Navigation |
| --- | --- |
| Android compact | Нижняя навигация: Контакты / Звонки / Чаты / Настройки |
| Mobile Web | Аналогичная compact bottom navigation, с учётом browser safe areas |
| Desktop/Web wide | Sidebar navigation/list + выбранный detail |
| Android large screen | Adaptive split/rail по доступной ширине |

Внутри compact чата нижняя глобальная навигация скрыта, Back возвращает к списку. Search остаётся сверху соответствующего списка. Keyboard/IME не перекрывает composer; изменение viewport не сбрасывает draft.

## 9. Иконки

Единый набор outline/filled vector icons выбирается для каждой платформы с согласованной семантикой. Использование конкретного proprietary symbol set не требуется. Толщина, оптический размер и baseline согласованы в каталоге.

| Роль | Графическая семантика |
| --- | --- |
| Контакты | Человек/контакты |
| Звонки | Телефон |
| Чаты | Два сообщения |
| Настройки | Шестерёнка |
| Новый чат | Карандаш/новое сообщение |
| Новая группа | Несколько людей |
| Поиск/очистить | Лупа/крестик в круге |
| Вложения | Плюс |
| Отправить | Стрелка вверх |
| Ответить/переслать | Стрелка влево/вправо с поворотом |
| OMEMO/plaintext | Закрытый/открытый замок |
| Decryption error | Щит с предупреждением |
| Retry | Круговая стрелка |
| Сохранить | Стрелка вниз/скачивание |
| Завершить звонок | Опущенная трубка |
| Turn camera | Камера с круговыми стрелками |

Обычный icon size 20/24 u; metadata 12/14. Иконка без текста имеет accessible name и tooltip на pointer, если смысл не очевиден. Emoji не заменяет функциональную пиктограмму кнопки.

## 10. Компонент Avatar

**UI-AVATAR.** Circle, photo fill с crop, fallback — initials/group icon и стабильный фон. Не смешивать photo fit с avatar fill: фотографии сообщений не обрезаются как avatar.

| Вариант | Размер |
| --- | --- |
| List | 50×50 |
| Profile | 64×64 |
| Call hero | 132×132 |
| Compact inline | 32×32 при необходимом контексте |

Initials около 35% diameter, semibold; group icon около 31%. Status dot bottom-end, diameter 25% avatar, border 2.5 u цветом окружающей поверхности. Direct dot означает online, group — joined. Accessible label включает имя и статус. Offline не рисуется ложным зелёным dot.

Состояния: photo, fallback, loading cached image, online/joined, offline, image error. Broken image не создаёт пустой невидимый avatar.

## 11. Компонент ConversationRow

Композиция: avatar → текстовая колонка → trailing time/unread. Gap avatar/text 12. Внешние insets horizontal 12, vertical 8; высота определяется содержимым, ориентир 72 u.

- Имя — heading.
- Preview — subbody secondary.
- Время — caption secondary.
- Межстрочный gap 4/5.
- Иконка group/encryption рядом с preview, не вместо имени.
- Badge count >0, white on action.fill, padding 7×3, min width 22.
- В основном списке значение выше 99 показывается «99+»; accessible name сообщает фактическое число.
- Multiaccount подпись — caption secondary, только когда нужно различать контекст.

Состояния: default, hover на pointer, pressed, keyboard focus, selected wide-panel, unread, online, muted при наличии функции, loading/empty отдельно от row.

Selected row: accent-tinted surface и ненавязчивый маркер/фон; hover слабее selected. Focus ring не исчезает на selected. Baseline focus outline 2 u с offset 2 u; при недостаточном контрасте используется двойная граница/контрастный separating layer.

## 12. SearchField

Поле располагается над фильтруемым списком. Height min 40 visual/48 touch target, radius pill либо control по platform shell. Horizontal inset 12, vertical 8, icon/text gap 8, outer margin 12.

Leading search icon, placeholder «Поиск чатов»/«Поиск контактов»/«Поиск звонков». Clear button появляется при непустом запросе. Native input behaviors сохраняются: selection, keyboard focus, paste и Escape очистки/закрытия по контексту.

Состояния: empty, filled, focused, disabled только при реальной невозможности, no results через отдельный empty state. Search field не обещает поиск message body, если реализована фильтрация списка.

## 13. MessageRow и Bubble

**UI-MESSAGE.** Incoming слева, outgoing справа. Outer horizontal inset 12, row gap 8. Opposite minimum space 54 для текста и 16 для media, с уменьшением в узком viewport. Body wrapping не расширяет страницу горизонтально.

Message stack:

1. optional group sender name;
2. optional compact source reply;
3. body/media;
4. reaction chips;
5. metadata.

### 13.1. Body

Text/file padding horizontal 13, vertical 9. Audio/voice — 13×10. Outgoing gradient + white; incoming neutral surface + primary. Body type.body.

Plaintext/decryption warning расположен в metadata и доступен screen reader. Не добавлять замок каждому слову или watermark поверх читаемого текста.

Text bubble использует общую directional rounded shape; media островок имеет независимый radius 20. Long URL/word безопасно переносится; copy возвращает исходный текст, а не строку с декоративными разрывами.

### 13.2. Metadata

Caption, gap 4, horizontal inset 4, вне основного colored body. Время hour:minute, marker «изм.», security warning и outgoing status.

| Состояние | Icon/подпись |
| --- | --- |
| Sending | Часы / «Отправка…» |
| Sent | Галочка / «Отправлено» |
| Delivered | Отличимая delivery-галочка / «Доставлено» |
| Read | Заполненный/двойной read marker / «Прочитано» |
| Failed | Warning red / «Не отправлено», доступен retry по ТЗ |

На compact можно оставить icon и доступный подробный label, на focus/hover показывать расшифровку. Статусы не различаются только tint.

### 13.3. Tombstone

Иконка удаления + «Сообщение удалено», subdued text/italic по доступности. Положение исходного сообщения сохраняется, прежние media/reaction/reply content не видны. Tombstone не приглашает к запрещённым edit/forward.

### 13.4. Selection и context menu

Touch: long press открывает actions; pointer: context click/явное menu; keyboard: доступная menu action. В selection mode видны checkmarks/count и панель массовых действий. Swipe reply отключён.

Список actions определяется ТЗ. Недоступное действие скрывается либо disabled с причиной, но не выполняет частично другую операцию под тем же названием.

## 14. CompactReply и ThreadFocus

Compact source bubble: max width 230, min height 34, radius 17, vertical padding 7, horizontal 10…12. Text subbody medium, one line, optional thumbnail 27×27/radius 6. Тонкий border 1.25 u; фон приглушённый.

Отступ/дуга отражают направление исходного сообщения. Curve width 58/height 34, stroke 2.4 round caps, horizontal offset около 18. Нельзя снижать opacity всего текста ниже readable contrast; muted effect достигается background/border, а не нечитаемой надписью.

При известном target компонент interactive и имеет label «Открыть ветку ответа». При preview без target он статичен и не показывает ложный hover-link.

ThreadFocus: затемнённый/raised отдельный слой, источник, число ответов, хронологическая ветка, selected reply metadata. Есть Close/Escape/Back и корректный focus restore. Bracket декоративный, не отдельный target. Это фокус replies в существующем чате.

## 15. ReactionChip и EmojiPicker

Chip: emoji + count, gap 3/4, padding 8×4, pill. Strip gap 5/8, wrap в узкой row.

| Вариант | Представление |
| --- | --- |
| Чужие реакции | Neutral subtle background + readable border |
| Есть own reaction | Accent-tinted background + accent border + accessible own state |
| Hover/focus | Нативная/общая interactive обратная связь |
| Pending mutation | Ненавязчивый progress, без ложного подтверждения failure |

Quick reactions: 👍 ❤️ 😂 😮 😢 🔥. Полный picker: header «Выберите эмодзи», Close/«Готово», grid, category navigation. Emoji visual 28, cell 46×46 с touch hit area минимум 48. Grid адаптивный; focused item виден и управляется keyboard.

Text search в emoji picker не обязателен. Если добавлен, он следует общему SearchField и не меняет базовую семантику reactions.

## 16. Composer

Horizontal structure: attach → multiline input → send/record. Gap 8. Outer horizontal 10/12, top 6/8, bottom 8 плюс safe area. Control visuals 42×42, hit targets по разделу размеров.

Input: min height 42 visual, radius 21, leading 14/trailing 12/vertical 9. Body font, от 1 до 6 строк до внутренней прокрутки. Placeholder «Сообщение»; edit mode «Изменить сообщение». Emoji control справа input, secondary, icon 20.

- Непустой draft: send arrow accent/action.
- Пустой draft: record action с доступным выбором audio/video.
- Reply/edit banner: над input body, автор/preview и Cancel.
- Upload preparation: progress и доступный cancel, текст не теряется.
- Recording: elapsed, waveform/indicator, cancel, finish/lock.
- Selection: separate action bar, обычная отправка не конфликтует с массовыми actions.

Keyboard contract Web/Desktop: Enter отправляет при настройке «Enter для отправки», Shift+Enter — новая строка; можно переключить поведение. IME composition не отправляет сообщение по промежуточному Enter. Esc закрывает локальный popup/отменяет reply/edit с сохранением исходного draft по сценарию.

Touch recording gestures не являются единственным способом: есть доступные «Начать», «Остановить», «Отменить». Back во время capture спрашивает о потере записи либо явно отменяет по утверждённому сценарию.

## 17. MediaIsland и viewer

### 17.1. Фото/видео

Default width 268, max available width минус row insets. Radius 20, border 1, thumbnail inset 6. Photo natural height по ratio, baseline clamp 164…328, с proportional уменьшением на узком экране. Object-fit/scale mode — contain.

Filename/size badge снизу: caption, white on достаточно тёмной scrim, padding 8×5, pill; inset 9. Expand icon сверху справа с hit area. Video имеет центральный play и duration.

Состояния: placeholder, loading, thumbnail, ready, playing для inline применимого типа, failed/retry. Error не замещается бесконечным spinner.

### 17.2. Audio/voice

Content default width 252 с clamp доступной ширины. Play circle 44, waveform около 30 high, progress/seek, duration и speed chip. Voice speed 1×/1.5×/2×; audio filename visible.

Seek имеет keyboard arrows/accessible slider semantics и touch target выше визуальной линии. Loading, paused, playing, ended и failed различимы.

### 17.3. VideoNote

Circle 144 idle, 176 playing при достаточном месте; при узком viewport размер уменьшается. Play icon 24, duration pill снизу, border 1. Увеличение не должно резко двигать viewport или перекрывать соседние controls.

### 17.4. Fullscreen viewer

Root overlay, тёмный фон, zoom/pan для фото, controls для видео. Обязательно доступны Close button, Escape на keyboard и Back на Android; vertical dismiss — дополнительный touch gesture. Close target располагается в safe area и не закрывает важное media.

Zoomed photo pan не запускает dismiss. После закрытия focus возвращается к исходному элементу, viewport остаётся на том же сообщении. Download/save — отдельное явное действие.

## 18. AttachmentPreview

Modal/panel с title «Перед отправкой», grid, подписью и action row. Grid cell min 128/max 190, column gap 18/20, row gap 22/24, container padding 16. В compact grid адаптируется до одной/двух колонок.

Caption field radius 16/padding 13×10, 1…4 строки. Нижняя panel raised/glass с opaque fallback, padding 14/16. Summary слева, primary send справа; mobile может переносить action row без обрезки.

На sending отмена/закрытие имеют определённую доступность; failed items остаются с clear status и retry. Caption не показывается как доставленная, если её отдельная отправка завершилась ошибкой.

## 19. LocationPicker

Header «Отправить геопозицию», карта/marker, текущая выбранная точка, «Моя геопозиция» и primary «Отправить». При denied permission — inline explanation и ручной выбор.

Map не поглощает все keyboard/Back actions. Выбор координат доступен через альтернативный ввод, если map недоступна. Preview location message — компактная карта/иконка и координаты/label; tap открывает просмотр без автоматического фонового tracking.

## 20. CallScene и CallHistoryCard

CallScene — inverse fullscreen/large overlay. Remote video занимает доступный фон, контрастная scrim защищает labels. Local video 118×168/radius 22, top-end с safe area; на compact масштабируется и не перекрывает controls.

Без video: call gradient, avatar 132, name hero до 2 строк, media type subbody, status/duration tabular. Основные controls снизу, visual circles 58 и подписанные labels.

- Incoming: decline red и accept green/dark-success fill с readable white text.
- Connecting: status и доступный cancel.
- Connected: mute, audio route при поддержке, camera/switch при наличии, hangup red.
- Permission/error: понятное пояснение и возврат без скрытой активной записи.

Control selected state передаётся icon + label/accessible state, а не только прозрачностью. Caption labels имеют достаточный контраст на scrim.

HistoryCard: max width 300, icon circle 42, content gap 12, title bodyStrong/subbodyStrong, subtitle caption, padding 14×10. Outcome icon/text: completed success, missed/failed/declined error, cancelled/answeredElsewhere neutral. Направление определяется также arrow/текстом.

## 21. Auth, Settings, Encryption и Lock

### 21.1. AuthCard

Hero gradient background; centered column max 460, outer horizontal 24/vertical 48, адаптация к keyboard. Logo tile 88/radius 26, brand 42, card radius 28/padding 24…28.

Form: JID, password с show/hide, advanced connection options, primary «Войти». Loading «Подключение…» и spinner. Error у поля/общая область без потери ввода. Native host/port и Web WSS endpoint представлены соответствующими полями, а не общим неработающим transport selector.

### 21.2. Settings

Grouped sections, стандартные switches/list rows/links. Profile avatar 64. Основные sections: аккаунты, профиль, соединение, шифрование, уведомления, блокировка, приватность.

Long values читаются/копируются; destructive logout отделён от обычных preferences. Multiaccount selection имеет checkmark и account identity.

### 21.3. EncryptionPanel

Итоговый режим чата, global/override control, список устройств, protocol badge, fingerprint mono, trust. Verified/trusted/undecided/compromised различаются текстом и символом. «Готово» не означает автоматической verification.

Fingerprint selectable/copyable, разбит на читаемые группы; label устройства не заменяет fingerprint. Empty devices объясняет следующий шаг, не показывает фиктивный secure success.

### 21.4. LockScreen

Hero/нейтральный фон и полностью скрытое sensitive content. Card radius 28, lock icon 44, title 22, field/action max 260 при обычной ширине, spacing около 22/24. Passcode input masked, explicit unlock, error inline и biometric action только при реальной доступности.

Lock не имитируется прозрачным blur поверх читаемого чата. Не существует автоматически перенесённой native-biometric кнопки в неподдержанном браузере.

## 22. Feedback, dialogs и слои

| Компонент | Контракт |
| --- | --- |
| Toast | Краткий результат, max 2 строки, закрываемый/доступный screen reader |
| Inline error | Ошибка поля/операции рядом с источником |
| Alert/dialog | Важная ошибка/подтверждение с ясными действиями |
| Loading | Spinner/progress + конкретная операция |
| Empty state | Название, пояснение, доступное next action |
| Connection status | Компактный читаемый статус в заголовке/панели |

Toast: padding 16×10, gap 8, pill, raised/glass fallback, shadow.toast. Default display 2.5 с; при accessibility/длинном тексте длительность увеличивается или доступно persistent alternative. Toast не единственное место критической ошибки.

Layers:

| Токен | Значение |
| --- | --- |
| `layer.base` | 0 |
| `layer.sticky` | 10 |
| `layer.popover` | 40 |
| `layer.dialog` | 80 |
| `layer.media` | 100 |
| `layer.call` | 200 |
| `layer.toast` | 300 |
| `layer.lock` | 400 |

Это роли stacking, не обязательные literal z-index в каждой технологии. При открытии слоя проверяются активные dialogs: неподходящий старый modal закрывается/уступает по сценарию. App lock имеет приоритет sensitive content. Error dialog при lock не раскрывает текст переписки.

Modal traps focus, имеет label и close action. После close focus восстанавливается. Browser/Android Back сначала закрывает верхний modal, затем navigates.

## 23. Анимации и жесты

| Токен/эффект | Значение |
| --- | --- |
| `motion.fast` | 120 ms |
| `motion.base` | 180…220 ms |
| `motion.panel` | 240…300 ms |
| Timeline entrance | До12 rows, stagger 35 ms, rise 16, scale 0.94 |
| Outgoing append | Spring около 440 ms; start scale 0.2/rise 12 при допустимом layout |
| Incoming append | Start scale 0.4/rise 10 |
| VideoNote resize | Spring около 320 ms |
| Reply swipe return | Spring около 240 ms |

Burst >4 appended rows/архив не анимируется как несколько свежих сообщений. Recycled rows не играют entrance повторно при каждом scroll.

Reduced motion: убрать scale/slide/stagger, оставить короткое fade или мгновенную смену. Важное состояние не зависит от завершения анимации. Animation cancellation не оставляет invisible interactive control.

Touch reply: horizontal activation 24, trigger 64, max offset 76; раннее доминирование горизонтали 1.6, после lock 1.05. Вертикальный scroll приоритетен. Haptic при пороге там, где поддержан и разрешён.

Record: hold около 240 ms, cancel left 92, lock up 78; размеры адаптируются к ограниченному пространству, доступные кнопки остаются.

Viewer swipe: vertical dominance 1.15, distance около 14% height clamp 88…140; fast predicted endpoint может завершать жест. На pointer Close/Escape остаются основным способом.

## 24. Accessibility и ввод

**UI-A11Y-001.** Целевой контраст обычного текста минимум 4.5:1, крупного 3:1; значимых controls/focus минимум 3:1 относительно соседних поверхностей. Проверяются фактические composite colors, не только исходные HEX.

**UI-A11Y-002.** Все действия доступны screen reader и имеют names/states. Icon-only button не называется именем файла icon.

**UI-A11Y-003.** Web/Desktop полностью поддерживают Tab/Shift+Tab, Enter/Space для действий, Escape для закрытия и предсказуемый focus order. Hover-only actions доступны также по focus/tap.

**UI-A11Y-004.** При text scale/zoom до 200% интерфейс reflow без потери основных действий. Fingerprint/URI можно прочитать полностью; text body не скрывается за fixed height.

**UI-A11Y-005.** Touch targets минимум 48×48 u для действий; визуально меньшая icon сохраняет просторный hit region. На pointer target не меньше 44×44 для основных icon actions.

**UI-A11Y-006.** Errors связаны с input, loading не бесконечно повторяется screen reader, live messages объявляются умеренно и не перехватывают focus.

**UI-A11Y-007.** Reduced motion/transparency и high contrast имеют определённые варианты. Цвет не единственный способ различения unread/failed/verified.

**UI-A11Y-008.** Record/call/media controls отражают фактическую активность camera/microphone. Для destructive есть явное подтверждение области действия.

## 25. Каталог состояний и приёмка UI

Поставляемая библиотека компонентов имеет отдельный доступный каталог/preview, не требующий реального XMPP login.

Обязательные fixtures:

- light/dark и reduced motion/transparency;
- compact 320/390, medium 840, wide 1280/1440;
- обычный и 200% текст;
- короткие/длинные имена/JID/URL/filename;
- чат без сообщений, search без результатов, offline и syncing;
- все delivery/security states;
- incoming/outgoing/group/reply/tombstone/reactions;
- media loading/ready/error и partial batch;
- recording start/locked/finalizing/error;
- incoming/connecting/active/failed call;
- keyboard focus, selection и menus;
- lock, denied permissions и уведомления без preview.

### 25.1. Чек-лист

- [ ] Все цвета/шрифты/spacing берутся из токенов по роли.
- [ ] Navigation соответствует ширине и платформе.
- [ ] Любая важная action доступна без жеста/hover.
- [ ] Focus не теряется в modal/viewer и возвращается после close.
- [ ] Long content и text scale не ломают layout.
- [ ] Incoming/outgoing/delivery/security определяются без одной лишь окраски.
- [ ] Media не обрезается неожиданно и не растягивается.
- [ ] Keyboard/IME не отправляет незавершённый ввод.
- [ ] Loading/ошибка/cancel завершаются корректным состоянием.
- [ ] Contrast проверен для фактических цветов и прозрачностей.
- [ ] Motion/transparency preferences работают.
- [ ] UI соответствует functional predicates `tz_clear.md`.

## 26. Развитие стандарта

Новый компонент сначала определяется как набор ролей/состояний, затем добавляется в tokens/catalog и после этого используется в экранах. Новый вариант существующего компонента получает имя и назначение; нельзя создавать похожую локальную копию с немного другим цветом/radius без причины.

Изменение токена проверяется на всех затронутых компонентах, light/dark и платформах. Несовместимые изменения версии UI Kit документируются и мигрируются согласованно.

Стандарт сохраняет общий характер Luma, при этом concrete native widget и способ реализации blur/vector/animation выбираются платформой. Ни одна из библиотек Web/Desktop/Android не считается реализованной только по существованию этого документа.
