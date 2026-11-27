/// Inbox の並び順。アーカイブは完了日時の新しい順で固定なので、ここには含めない。
enum InboxSortOrder: String, CaseIterable {
    /// 期限日の早い順。期限なしは末尾。見出しで区切る。
    case dueDate
    /// 作成日時の新しい順。見出しは出さない。
    case createdAt

    var title: String {
        switch self {
        case .dueDate: "期限日順"
        case .createdAt: "作成日順"
        }
    }

    /// 起動時に保存値から戻す。空や未知の値（初回起動・将来の変更で残った古い値）は期限日順にする。
    init(storedValue: String) {
        self = Self(rawValue: storedValue) ?? .dueDate
    }

    var storedValue: String { rawValue }
}
