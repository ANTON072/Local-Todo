/// サイドバーで選ぶ、Inbox かアーカイブか。タグはここに入れない（タグはどちらにもかかるフィルタ。#18）。
enum TodoListKind: Hashable, CaseIterable {
    case inbox
    case archive

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

    func todos(in store: TodoStore) -> [Todo] {
        switch self {
        case .inbox: store.inboxTodos
        case .archive: store.archivedTodos
        }
    }
}
