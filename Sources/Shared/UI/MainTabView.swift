import Foundation
import SwiftData
import SwiftUI

/// Telegram-style main screen. On iOS the root is a bottom tab bar
/// (Контакты / Звонки / Чаты / Настройки) with an inline search field at
/// the top of the chat and contact lists. On macOS the root is a Telegram
/// Desktop-style split view: a sidebar (menu, search, list) plus a detail
/// pane with the selected chat.
struct MainTabView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        #if os(macOS)
            MainSplitView(model: model)
        #else
            MainTabBarView(model: model)
        #endif
    }
}

// MARK: - Shared search field

/// Inline rounded search field, placed explicitly above the list it
/// filters. Used on both platforms so the position never depends on
/// navigation-bar search placement.
private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - iOS: bottom tab bar

#if os(iOS)
    private struct MainTabBarView: View {
        enum Tab: String, CaseIterable, Identifiable {
            case contacts
            case calls
            case chats
            case settings

            var id: String { rawValue }

            var title: String {
                switch self {
                case .contacts: return "Контакты"
                case .calls: return "Звонки"
                case .chats: return "Чаты"
                case .settings: return "Настройки"
                }
            }

            var icon: String {
                switch self {
                case .contacts: return "person.circle.fill"
                case .calls: return "phone.fill"
                case .chats: return "bubble.left.and.bubble.right.fill"
                case .settings: return "gearshape.fill"
                }
            }

            var selectedIcon: String {
                switch self {
                case .contacts: return "person.circle.fill"
                case .calls: return "phone.fill"
                case .chats: return "bubble.left.and.bubble.right.fill"
                case .settings: return "gearshape.fill"
                }
            }
        }

        @ObservedObject var model: AppModel
        @State private var selectedTab: Tab = .chats

        var body: some View {
            // Native TabView: on iOS 26 it renders the system floating
            // translucent tab bar (Liquid Glass).
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    tabContent(for: tab)
                        .tabItem {
                            Label(
                                tab.title,
                                systemImage: selectedTab == tab
                                    ? tab.selectedIcon : tab.icon
                            )
                        }
                        .tag(tab)
                }
            }
        }

        @ViewBuilder
        private func tabContent(for tab: Tab) -> some View {
            switch tab {
            case .contacts:
                ContactsTab(model: model)
            case .calls:
                CallsTab(model: model)
            case .chats:
                ChatsTab(model: model)
            case .settings:
                NavigationStack {
                    SettingsView(model: model, presentedAsTab: true)
                }
            }
        }
    }
#endif

// MARK: - Chats

private struct ChatsTab: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var showingNewChat = false
    @State private var showingNewGroup = false
    @State private var pendingGroupDeletion: Conversation?
    @FocusState private var searchFocused: Bool

    /// SwiftData-backed chat list. The query orders by last activity;
    /// `filteredConversations` applies the pinned-first ordering that
    /// matches `AppModel.sortConversations` (`Bool` is not `Comparable`,
    /// so pinning cannot be a `SortDescriptor`).
    @Query(
        sort: [
            SortDescriptor(\Conversation.lastActivity, order: .reverse)
        ]
    )
    private var storedConversations: [Conversation]

    private var conversations: [AccountConversation] {
        let source = model.conversations.isEmpty ? storedConversations : model.conversations
        guard let account = model.account else {
            return source.map {
                AccountConversation(
                    account: AccountConfiguration(jid: "preview@example.org"),
                    conversation: $0
                )
            }
        }
        return source.map { AccountConversation(account: account, conversation: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatList
            }
            .navigationTitle("")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Поиск чатов"
                )
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ConnectionBanner(model: model, text: "Чаты")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingNewGroup = true
                    } label: {
                        Image(systemName: "person.3.fill")
                    }
                    .accessibilityLabel("Новый групповой чат")
                    .help("Новый групповой чат")
                    Button {
                        showingNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Новый личный чат")
                    .help("Новый личный чат")
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView(model: model)
            }
            .sheet(isPresented: $showingNewGroup) {
                NewGroupView(model: model)
            }
            .alert(
                "Удалить групповой чат?",
                isPresented: Binding(
                    get: { pendingGroupDeletion != nil },
                    set: { if !$0 { pendingGroupDeletion = nil } }
                )
            ) {
                Button("Удалить", role: .destructive) {
                    if let pendingGroupDeletion {
                        model.deleteGroupChat(jid: pendingGroupDeletion.jid)
                    }
                    pendingGroupDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingGroupDeletion = nil }
            } message: {
                Text(
                    "Чат и его история будут удалены с этого устройства. Luma выйдет из комнаты, если вы в ней."
                )
            }
        }

    }

    private var filteredConversations: [AccountConversation] {
        let source =
            searchText.isEmpty
            ? conversations : conversations.filter(matchesSearch)
        return source.sorted(by: conversationSort)
    }

    private var chatList: some View {
        List {
            ForEach(filteredConversations) { item in
                let conversation = item.conversation
                NavigationLink {
                    ChatView(model: model, conversation: conversation)
                        .id(item.id)
                        .onAppear {
                            if item.account.normalizedJID != model.account?.normalizedJID {
                                Task {
                                    await model.switchAccount(to: item.account)
                                    model.selectConversation(id: conversation.jid)
                                }
                            } else {
                                model.selectConversation(id: conversation.jid)
                            }
                        }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        ConversationRow(
                            conversation: conversation,
                            imageData: model.avatarData(for: conversation.jid),
                            isEncrypted: model.encryptionEnabled(
                                for: conversation.jid
                            )
                        )
                        if model.accounts.count > 1 {
                            Text(item.account.normalizedJID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 52)
                        }
                    }
                }
                .listRowInsets(
                    EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if conversation.isGroup {
                        Button(role: .destructive) {
                            pendingGroupDeletion = conversation
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredConversations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Нет чатов" : "Ничего не найдено",
                    systemImage: searchText.isEmpty
                        ? "bubble.left" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Создайте личный или групповой чат."
                            : "Попробуйте другой JID или имя."
                    )
                )
            }
        }
    }

    private func conversationSort(_ lhs: AccountConversation, _ rhs: AccountConversation)
        -> Bool
    {
        let lhs = lhs.conversation
        let rhs = rhs.conversation
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.lastActivity != rhs.lastActivity {
            return lhs.lastActivity > rhs.lastActivity
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            == .orderedAscending
    }

    private func matchesSearch(_ item: AccountConversation) -> Bool {
        let conversation = item.conversation
        return conversation.displayName.localizedCaseInsensitiveContains(searchText)
            || conversation.jid.localizedCaseInsensitiveContains(searchText)
            || item.account.normalizedJID.localizedCaseInsensitiveContains(searchText)
    }
}

// MARK: - Contacts

private struct ContactsTab: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""

    @Query(
        sort: [
            SortDescriptor(\Conversation.lastActivity, order: .reverse)
        ]
    )
    private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contactsList
            }
            .navigationTitle("")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Поиск контактов"
                )
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ConnectionBanner(model: model, text: "Контакты")
                }
            }
        }
    }

    private var contactsList: some View {
        List {
            if !filteredRosterContacts.isEmpty {
                Section {
                    ForEach(filteredRosterContacts) { conversation in
                        contactLink(conversation)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 7,
                                    leading: 12,
                                    bottom: 7,
                                    trailing: 12
                                )
                            )
                    }
                }
            }

            if !filteredGroupContacts.isEmpty {
                Section {
                    ForEach(filteredGroupContacts) { conversation in
                        contactLink(conversation)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 7,
                                    leading: 12,
                                    bottom: 7,
                                    trailing: 12
                                )
                            )
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredRosterContacts.isEmpty && filteredGroupContacts.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Нет контактов" : "Ничего не найдено",
                    systemImage: searchText.isEmpty
                        ? "person.2" : "magnifyingglass",
                    description: Text(contactListDescription),
                )
            }
        }
    }

    @ViewBuilder
    private func contactLink(_ conversation: Conversation) -> some View {
        NavigationLink {
            ChatView(model: model, conversation: conversation)
                .id(conversation.jid)
                .onAppear { model.selectConversation(id: conversation.jid) }
        } label: {
            ContactRow(
                conversation: conversation,
                imageData: model.avatarData(for: conversation.jid)
            )
        }
    }

    private var filteredRosterContacts: [Conversation] {
        conversations
            .filter { !$0.isGroup && model.rosterContactJIDs.contains($0.jid) }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var filteredGroupContacts: [Conversation] {
        conversations
            .filter { $0.isGroup }
            .filter { searchText.isEmpty || matchesSearch($0) }
            .sorted(by: contactSort)
    }

    private var hasStoredContacts: Bool {
        !model.rosterContactJIDs.isEmpty
            || conversations.contains { $0.isGroup }
    }

    private var contactListDescription: String {
        if !searchText.isEmpty {
            return "Попробуйте другой JID или имя."
        }
        if !hasStoredContacts, model.connectionStatus != .connected {
            return
                "Подключитесь к серверу, чтобы загрузить roster Prosody и групповые комнаты."
        }
        return "Добавьте человека в roster или создайте групповой чат."
    }

    private func matchesSearch(_ conversation: Conversation) -> Bool {
        conversation.displayName.localizedCaseInsensitiveContains(searchText)
            || conversation.jid.localizedCaseInsensitiveContains(searchText)
    }

    private func contactSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            == .orderedAscending
    }
}

// MARK: - Calls

private struct CallsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.callHistoryMessages.isEmpty {
                    ContentUnavailableView(
                        "Нет звонков",
                        systemImage: "phone",
                        description: Text(
                            "История звонков появится здесь после первого вызова."
                        )
                    )
                } else {
                    List(model.callHistoryMessages) { message in
                        if let conversation = model.conversations.first(where: {
                            $0.jid == message.conversationID
                        }) {
                            NavigationLink {
                                ChatView(
                                    model: model,
                                    conversation: conversation
                                )
                                .id(conversation.jid)
                                .onAppear {
                                    model.selectConversation(
                                        id: conversation.jid
                                    )
                                }
                            } label: {
                                CallHistoryRow(
                                    model: model,
                                    message: message,
                                    conversation: conversation
                                )
                            }
                            .listRowInsets(
                                EdgeInsets(
                                    top: 7,
                                    leading: 12,
                                    bottom: 7,
                                    trailing: 12
                                )
                            )
                        } else {
                            CallHistoryRow(
                                model: model,
                                message: message,
                                conversation: nil
                            )
                            .listRowInsets(
                                EdgeInsets(
                                    top: 7,
                                    leading: 12,
                                    bottom: 7,
                                    trailing: 12
                                )
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Звонки")
                        .font(.headline)
                }
            }
        }
    }
}

private struct CallHistoryRow: View {
    @ObservedObject var model: AppModel
    let message: ChatMessage
    let conversation: Conversation?

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: message.callHistory?.isVideo == true
                    ? "video.fill" : "phone.fill"
            )
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(
                message.direction == .incoming
                    && message.callHistory?.outcome == .missed
                    ? Color.red : Color.accentColor
            )
            .frame(width: 34, height: 34)
            .background(Color.secondary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation?.displayName ?? message.conversationID)
                    .font(.headline)
                    .lineLimit(1)
                Text(message.callTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Text(message.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct ContactRow: View {
    let conversation: Conversation
    let imageData: Data?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                conversation: conversation,
                imageData: imageData,
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if !conversation.isGroup, conversation.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("В сети")
                    }
                }

                if conversation.isGroup {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                        Text(groupSubtitle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(conversation.jid)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            //            Image(systemName: "chevron.right")
            //                .font(.caption.bold())
            //                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var groupSubtitle: String {
        guard conversation.occupantCount > 0 else { return conversation.jid }
        return "\(conversation.occupantCount) участн. • \(conversation.jid)"
    }
}

// MARK: - macOS: Telegram Desktop-style split view

#if os(macOS)
    private struct MainSplitView: View {
        private enum Mode: String, CaseIterable, Identifiable {
            case contacts
            case calls
            case chats
            case settings

            var id: String { rawValue }

            var title: String {
                switch self {
                case .chats: return "Чаты"
                case .contacts: return "Контакты"
                case .calls: return "Звонки"
                case .settings: return "Настройки"
                }
            }

            var icon: String {
                switch self {
                case .chats: return "bubble.left.and.bubble.right.fill"
                case .contacts: return "person.circle.fill"
                case .calls: return "phone.fill"
                case .settings: return "gearshape.fill"
                }
            }

            var searchPrompt: String {
                switch self {
                case .chats: return "Поиск чатов"
                case .contacts: return "Поиск контактов"
                case .calls: return "Поиск звонков"
                case .settings: return "Поиск"
                }
            }
        }

        @ObservedObject var model: AppModel
        @State private var mode: Mode = .chats
        @State private var selectedJID: String?
        @State private var searchText = ""
        @State private var showingNewChat = false
        @State private var showingNewGroup = false
        @State private var pendingGroupDeletion: Conversation?

        /// SwiftData-backed chat list; pinned-first ordering is applied in
        /// `sortedChats` because `Bool` is not `Comparable` and cannot be a
        /// `SortDescriptor`.
        @Query(
            sort: [
                SortDescriptor(\Conversation.lastActivity, order: .reverse)
            ]
        )
        private var conversations: [Conversation]

        private var chatItems: [AccountConversation] {
            let source = model.conversations.isEmpty ? conversations : model.conversations
            guard let account = model.account else {
                return source.map {
                    AccountConversation(
                        account: AccountConfiguration(jid: "preview@example.org"),
                        conversation: $0
                    )
                }
            }
            return source.map { AccountConversation(account: account, conversation: $0) }
        }

        var body: some View {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(
                        min: 240,
                        ideal: 290,
                        max: 380
                    )
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(mode.title)
                                .font(.headline)
                        }
                        if mode != .settings {
                            ToolbarItemGroup(placement: .primaryAction) {
                                Button {
                                    showingNewGroup = true
                                } label: {
                                    Image(systemName: "person.3.fill")
                                }
                                .accessibilityLabel("Новый групповой чат")
                                .help("Новый групповой чат")
                                Button {
                                    showingNewChat = true
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                }
                                .accessibilityLabel("Новый личный чат")
                                .help("Новый личный чат")
                            }
                        }
                    }
            } detail: {
                detailPane
            }
            .frame(minWidth: 840, minHeight: 560)
            .sheet(isPresented: $showingNewChat) {
                NewChatView(model: model)
            }
            .sheet(isPresented: $showingNewGroup) {
                NewGroupView(model: model)
            }
            .alert(
                "Удалить групповой чат?",
                isPresented: Binding(
                    get: { pendingGroupDeletion != nil },
                    set: { if !$0 { pendingGroupDeletion = nil } }
                )
            ) {
                Button("Удалить", role: .destructive) {
                    if let pendingGroupDeletion {
                        model.deleteGroupChat(jid: pendingGroupDeletion.jid)
                    }
                    pendingGroupDeletion = nil
                }
                Button("Отмена", role: .cancel) { pendingGroupDeletion = nil }
            } message: {
                Text(
                    "Чат и его история будут удалены с этого устройства. Luma выйдет из комнаты, если вы в ней."
                )
            }
            .onAppear {
                ensureSelection()
            }
        }

        // MARK: Sidebar

        private var sidebar: some View {
            VStack(spacing: 0) {
                if mode != .settings {
                    ConnectionBanner(model: model, text: "")
                    SearchField(
                        text: $searchText,
                        prompt: mode.searchPrompt
                    )
                }
                sidebarList
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Mode.allCases) { item in
                        Button {
                            withAnimation(.easeInOut) {
                                switchMode(item)
                            }
                        } label: {
                            VStack {
                                Image(systemName: item.icon)
                                    .font(.largeTitle)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(
                            mode == item ? .accentColor : .secondary
                        )
                        .padding(.vertical, 8)
                        .buttonStyle(.plain)
                    }
                }
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.82),
                    value: mode
                )
                .glassEffect(in: .rect(cornerRadius: 20))
            }
        }

        private var sidebarList: some View {
            List(selection: $selectedJID) {
                switch mode {
                case .chats:
                    chatRows
                case .contacts:
                    contactRows
                case .calls:
                    callRows
                case .settings:
                    //                    NavigationStack {
                    SettingsView(model: model, presentedAsTab: true)
                //                    }
                //                    EmptyView()
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if mode == .chats && filteredChats.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Нет чатов" : "Ничего не найдено",
                        systemImage: searchText.isEmpty
                            ? "bubble.left" : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "Создайте личный или групповой чат."
                                : "Попробуйте другой JID или имя."
                        )
                    )
                }
                if mode == .contacts && filteredRoster.isEmpty
                    && filteredGroups.isEmpty
                {
                    ContentUnavailableView(
                        searchText.isEmpty
                            ? "Нет контактов" : "Ничего не найдено",
                        systemImage: searchText.isEmpty
                            ? "person.2" : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "Подключитесь к серверу, чтобы загрузить roster, или создайте групповой чат."
                                : "Попробуйте другой JID или имя."
                        )
                    )
                }
            }
        }

        @ViewBuilder
        private var chatRows: some View {
            ForEach(filteredChats) { item in
                let conversation = item.conversation
                ConversationRow(
                    conversation: conversation,
                    imageData: model.avatarData(for: conversation.jid),
                    isEncrypted: model.encryptionEnabled(for: conversation.jid)
                )
                .tag(item.id)
                .contextMenu {
                    if conversation.isGroup {
                        Button("Удалить", role: .destructive) {
                            pendingGroupDeletion = conversation
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private var contactRows: some View {
            if !filteredRoster.isEmpty {
                Section {
                    ForEach(filteredRoster) { conversation in
                        ContactRow(
                            conversation: conversation,
                            imageData: model.avatarData(for: conversation.jid)
                        )
                        .tag(conversation.jid)
                    }
                }
            }
            if !filteredGroups.isEmpty {
                Section {
                    ForEach(filteredGroups) { conversation in
                        ContactRow(
                            conversation: conversation,
                            imageData: model.avatarData(for: conversation.jid)
                        )
                        .tag(conversation.jid)
                    }
                }
            }
        }

        @ViewBuilder
        private var callRows: some View {
            ForEach(filteredCalls) { message in
                if let conversation = conversations.first(where: {
                    $0.jid == message.conversationID
                }) {
                    CallHistoryRow(
                        model: model,
                        message: message,
                        conversation: conversation
                    )
                    .tag(message.clientID)
                } else {
                    CallHistoryRow(
                        model: model,
                        message: message,
                        conversation: nil
                    )
                    .tag(message.clientID)
                }
            }
        }

        // MARK: Detail pane

        @ViewBuilder
        private var detailPane: some View {
            if mode == .settings {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "gearshape.fill",
                    description: Text("Выберите пункт из списка слева.")
                )
            } else if let conversation = selectedConversation
                ?? defaultConversation
            {
                ChatView(model: model, conversation: conversation)
                    .id(conversation.jid)
                    .onAppear {
                        if let item = chatItems.first(where: { $0.id == selectedJID }),
                           item.account.normalizedJID != model.account?.normalizedJID {
                            Task {
                                await model.switchAccount(to: item.account)
                                model.selectConversation(id: conversation.jid)
                            }
                        } else {
                            model.selectConversation(id: conversation.jid)
                        }
                    }
            } else {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Выберите пункт из списка слева.")
                )
            }
        }

        private var emptyTitle: String {
            switch mode {
            case .chats: return "Выберите чат"
            case .contacts: return "Выберите контакт"
            case .calls: return "Выберите звонок"
            case .settings: return "Настройки"
            }
        }

        private var selectedConversation: Conversation? {
            guard let selectedJID else { return nil }
            if mode == .calls {
                guard
                    let message = model.callHistoryMessages.first(where: {
                        $0.clientID == selectedJID
                    })
                else {
                    return nil
                }
                return chatItems.first(where: { $0.conversation.jid == message.conversationID })?.conversation
            }
            return chatItems.first(where: { $0.id == selectedJID || $0.conversation.jid == selectedJID })?.conversation
        }

        private var defaultConversation: Conversation? {
            mode == .chats ? sortedChats.first?.conversation : nil
        }

        // MARK: Filtering and sorting

        private var sortedChats: [AccountConversation] {
            chatItems.sorted(by: conversationSort)
        }

        private var filteredChats: [AccountConversation] {
            searchText.isEmpty ? sortedChats : sortedChats.filter(matchesChat)
        }

        private func matchesChat(_ item: AccountConversation) -> Bool {
            let conversation = item.conversation
            conversation.displayName.localizedCaseInsensitiveContains(
                searchText
            )
                || conversation.jid.localizedCaseInsensitiveContains(searchText)
                || item.account.normalizedJID.localizedCaseInsensitiveContains(searchText)
        }

        private func conversationSort(_ lhs: AccountConversation, _ rhs: AccountConversation)
            -> Bool
        {
            let lhs = lhs.conversation
            let rhs = rhs.conversation
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.lastActivity != rhs.lastActivity {
                return lhs.lastActivity > rhs.lastActivity
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(
                rhs.displayName
            )
                == .orderedAscending
        }

        private var filteredRoster: [Conversation] {
            conversations
                .filter {
                    !$0.isGroup && model.rosterContactJIDs.contains($0.jid)
                }
                .filter { searchText.isEmpty || matchesChat(AccountConversation(account: model.account ?? AccountConfiguration(jid: "preview@example.org"), conversation: $0)) }
                .sorted(by: contactSort)
        }

        private var filteredGroups: [Conversation] {
            conversations
                .filter { $0.isGroup }
                .filter { searchText.isEmpty || matchesChat(AccountConversation(account: model.account ?? AccountConfiguration(jid: "preview@example.org"), conversation: $0)) }
                .sorted(by: contactSort)
        }

        private func contactSort(_ lhs: Conversation, _ rhs: Conversation)
            -> Bool
        {
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                == .orderedAscending
        }

        private var filteredCalls: [ChatMessage] {
            guard !searchText.isEmpty else { return model.callHistoryMessages }
            return model.callHistoryMessages.filter { message in
                message.conversationID.localizedCaseInsensitiveContains(
                    searchText
                )
                    || (conversations.first(where: {
                        $0.jid == message.conversationID
                    })?.displayName
                        .localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // MARK: Selection

        private func switchMode(_ newMode: Mode) {
            mode = newMode
            selectedJID = nil
            searchText = ""
            if newMode == .chats {
                selectedJID = sortedChats.first?.id
            }
        }

        private func ensureSelection() {
            if mode == .chats, selectedJID == nil {
                selectedJID = sortedChats.first?.id
            }
        }
    }
#endif

#Preview {
    PreviewSupport.mainPreview()
}
