/// 新規追加の入力欄で ⌘Enter を押したときの動き。
enum NewTodoInput {
    /// store に追加し、入力欄に残す文字列を返す。
    /// 追加できたら空にする。空白だけで追加できなかったら、打った文字を残す。
    static func submit(_ text: String, to store: TodoStore) -> String {
        store.add(title: text) == nil ? text : ""
    }
}
