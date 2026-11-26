import Foundation
import Observation

/// Todo の状態を持つただ1つの場所。ビューは一覧を受け取り、ここの操作を呼ぶだけにする。
///
/// 起動時に `Persistence` から全件を読み、以降はメモリ上の `todos` を正とする。
/// 操作はメインスレッドから呼ぶ（`Persistence` の決まりに合わせる）。
@Observable
final class TodoStore {
    /// 持っている順は、加わった順。一覧の並べ替えで、日時が同じときの順に使う。
    private(set) var todos: [Todo]
    /// 起動時にどこから読んだか。画面への出し方は #44。
    let loadSource: Persistence.LoadSource
    /// 最後の保存の失敗。画面への出し方は #44。
    private(set) var lastSaveError: Error?

    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private let now: () -> Date

    /// - Parameters:
    ///   - persistence: 保存先。テストでは一時フォルダのものを渡す。保存の失敗を受け取るため、
    ///     `onSaveError` をこの TodoStore が差し替える。
    ///   - now: 今の時刻。テストで差し替える。
    init(persistence: Persistence, now: @escaping () -> Date = { .now }) {
        self.persistence = persistence
        self.now = now
        let result = persistence.load()
        todos = result.todos
        loadSource = result.source
        persistence.onSaveError = { [weak self] error in
            self?.lastSaveError = error
        }
    }

    // MARK: - 一覧

    /// 作成日時の新しい順。
    var inboxTodos: [Todo] {
        sortedNewestFirst(todos.filter { !$0.isArchived }, by: \.createdAt)
    }

    /// 完了日時の新しい順。
    var archivedTodos: [Todo] {
        sortedNewestFirst(todos.filter(\.isArchived), by: { $0.completedAt ?? .distantPast })
    }

    /// 日時が同じなら、あとから加わったもの（配列で後ろにあるもの）を上にする。
    private func sortedNewestFirst(_ todos: [Todo], by date: (Todo) -> Date) -> [Todo] {
        todos.enumerated()
            .sorted { lhs, rhs in
                let (lhsDate, rhsDate) = (date(lhs.element), date(rhs.element))
                return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.offset > rhs.offset
            }
            .map(\.element)
    }

    // MARK: - 操作

    /// タイトルの前後の空白（改行を含む）を除き、途中の改行を半角スペースにして追加する。
    /// 続いた改行（`\r\n` や空の行）は1つのスペースにまとめる。タイトルは1行で表示するため。
    /// - Returns: 追加した Todo。除いたあとに空なら追加せず nil を返す。
    @discardableResult
    func add(title: String) -> Todo? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\R+", with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        let todo = Todo(title: trimmed, createdAt: now())
        todos.append(todo)
        save()
        return todo
    }

    /// 同じ ID の Todo と置き換える。見つからなければ何もしない。
    /// 完了日時は受け取った値を無視して元の値を保つ（完了・戻すは専用の操作にする。#7）。
    func update(_ todo: Todo) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        var updated = todo
        updated.completedAt = todos[index].completedAt
        todos[index] = updated
        save()
    }

    /// Inbox かアーカイブかを問わず1件を取り除く。見つからなければ何もしない。
    func delete(id: Todo.ID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos.remove(at: index)
        save()
    }

    // MARK: - 保存

    /// すぐに保存し、終わるまで待つ。アプリの終了時に使う。
    func saveNow() {
        persistence.saveNow(todos)
    }

    private func save() {
        persistence.scheduleSave(todos)
    }
}
