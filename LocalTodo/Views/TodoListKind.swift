/// サイドバーで選ぶ、Inbox かアーカイブか。タグはここに入れない（タグはどちらにもかかるフィルタ。#18）。
enum TodoListKind: Hashable, CaseIterable {
    case inbox
    case archive

    /// `@AppStorage` に保存する文字列。
    var storedValue: String {
        switch self {
        case .inbox: "inbox"
        case .archive: "archive"
        }
    }

    /// 起動時に保存値から戻す。空や未知の値（初回起動など）は Inbox にする。
    init(storedValue: String) {
        self = Self.allCases.first { $0.storedValue == storedValue } ?? .inbox
    }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .archive: "アーカイブ"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .archive: "archivebox"
        }
    }

    /// アーカイブに直接 Todo を足す操作はないので、入力欄は Inbox にだけ出す。
    var showsNewTodoField: Bool {
        self == .inbox
    }

    func todos(in store: TodoStore, order: InboxSortOrder = .dueDate) -> [Todo] {
        switch self {
        case .inbox: store.inboxTodos(order: order)
        case .archive: store.archivedTodos
        }
    }
}
