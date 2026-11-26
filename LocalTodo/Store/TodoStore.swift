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
    /// 保留中の Todo。値は、完了のチェックを入れた（アーカイブでは外した）時刻。
    /// 確定するまで `completedAt` と一覧は変えず、見た目だけを切り替える。
    private(set) var pendingToggles: [Todo.ID: Date] = [:]

    /// 保留を確定するまでの猶予。最後の操作から数える。
    static let graceInterval: TimeInterval = 3

    /// 「何秒後にこの処理を動かすか」を受け取り、取り消す関数を返す。メインスレッドで動かす。
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> () -> Void

    /// 本物のタイマー。メインキューで動かす。
    static let mainQueueScheduler: Scheduler = { delay, action in
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    /// 取り消せるか・やり直せるかと、その操作の名前（メニューの表示に使う）。
    /// `UndoManager` は観測できないので、変わるたびにここへ写す。
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoActionName = ""
    private(set) var redoActionName = ""

    /// 取り消しの履歴。入力欄の文字の取り消しとは別に持つ（アプリを閉じると消える）。
    /// 操作ごとに1つのまとまりにするため、イベントごとの自動のまとめは使わない。
    @ObservationIgnored let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    @ObservationIgnored private let persistence: Persistence
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let scheduleTimer: Scheduler
    @ObservationIgnored private var cancelGraceTimer: (() -> Void)?

    /// - Parameters:
    ///   - persistence: 保存先。テストでは一時フォルダのものを渡す。保存の失敗を受け取るため、
    ///     `onSaveError` をこの TodoStore が差し替える。
    ///   - now: 今の時刻。テストで差し替える。
    ///   - scheduleTimer: 保留を確定するまでの猶予を数えるタイマー。テストでは、時間を進めたら動く偽物を渡す。
    init(
        persistence: Persistence,
        now: @escaping () -> Date = { .now },
        scheduleTimer: @escaping Scheduler = TodoStore.mainQueueScheduler
    ) {
        self.persistence = persistence
        self.now = now
        self.scheduleTimer = scheduleTimer
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
        guard let normalized = Self.normalizedTitle(title) else { return nil }
        let todo = Todo(title: normalized, createdAt: now())
        todos.append(todo)
        save()
        recordUndo("追加", [.add(todo, at: todos.count - 1)])
        return todo
    }

    /// 詳細ペインのタイトル欄に打たれた文字列を、`add(title:)` と同じ整え方でタイトルにする。
    /// 整えたあとが空なら確定しない（空のタイトルの Todo は一覧で見えなくなるため）。
    /// 整えたあとが今のタイトルと同じなら、置き換えも保存もしない
    /// （フォーカスが外れるたびに呼ばれるので、何も変えていない操作で保存や取り消しの履歴を増やさない）。
    /// - Returns: 欄に出す文字列。確定したら新しいタイトル、確定しなかったら今のタイトル。
    ///   ID の Todo がなければ何も変えず、整えた文字列（空なら空文字列）を返す。
    @discardableResult
    func commitTitle(id: Todo.ID, text: String) -> String {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return Self.normalizedTitle(text) ?? ""
        }
        let current = todos[index].title
        guard let normalized = Self.normalizedTitle(text), normalized != current else { return current }
        let before = todos[index]
        todos[index].title = normalized
        save()
        recordUndo("タイトルの編集", [.edit(before: before, after: todos[index])])
        return normalized
    }

    /// 前後の空白と改行を除き、途中の改行（続いたものは1つにまとめて）を半角スペースにする。空なら nil。
    private static func normalizedTitle(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\R+", with: " ", options: .regularExpression)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 同じ ID の Todo と置き換える。見つからなければ何もしない。
    /// 完了日時は受け取った値を無視して元の値を保つ（完了・戻すは専用の操作にする。#7）。
    /// - Parameter registersUndo: 取り消しの履歴に載せるか。ディスクリプションの打鍵は、
    ///   入力欄の標準の取り消しに任せるので、false にする。
    func update(_ todo: Todo, registersUndo: Bool = true) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        let before = todos[index]
        var updated = todo
        updated.completedAt = before.completedAt
        todos[index] = updated
        save()
        if registersUndo, before != updated {
            recordUndo("編集", [.edit(before: before, after: updated)])
        }
    }

    /// Inbox かアーカイブかを問わず1件を取り除く。見つからなければ何もしない。
    /// 保留中なら保留から外す（消した Todo に完了日時を書かないため）。
    func delete(id: Todo.ID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let removed = todos.remove(at: index)
        if pendingToggles.removeValue(forKey: id) != nil { restartGraceTimer() }
        save()
        recordUndo("削除", [.delete(removed, at: index)])
    }

    // MARK: - 完了とアーカイブ（保留）

    /// 完了のチェックを入れる（アーカイブでは外す）。猶予の間にもう一度呼ぶと保留から外れる。
    /// 最後の操作（外した場合も）から `graceInterval` たつと、保留中のものをまとめて確定する。
    /// 見つからなければ何もしない。
    func toggleCompletion(id: Todo.ID) {
        guard todos.contains(where: { $0.id == id }) else { return }
        if pendingToggles.removeValue(forKey: id) == nil {
            pendingToggles[id] = now()
        }
        restartGraceTimer()
    }

    /// 見た目の上で完了か。保留中なら、持っている状態（`isArchived`）と逆になる。
    /// 見つからなければ false。
    func isShownCompleted(id: Todo.ID) -> Bool {
        guard let todo = todos.first(where: { $0.id == id }) else { return false }
        return todo.isArchived != (pendingToggles[id] != nil)
    }

    /// 保留中のものをまとめて確定する。Inbox の Todo にはチェックした時刻を完了日時として入れ、
    /// アーカイブの Todo は完了日時を外して Inbox へ戻す。
    private func commitPending() {
        cancelGraceTimer?()
        cancelGraceTimer = nil
        guard !pendingToggles.isEmpty else { return }
        var mutations: [Mutation] = []
        var completes = false
        var restores = false
        // チェックした順に並べる（同じ時刻のときの順を決めておく）
        for (id, checkedAt) in pendingToggles.sorted(by: { $0.value < $1.value }) {
            guard let index = todos.firstIndex(where: { $0.id == id }) else { continue }
            let before = todos[index]
            if before.isArchived { restores = true } else { completes = true }
            todos[index].completedAt = before.isArchived ? nil : checkedAt
            mutations.append(.edit(before: before, after: todos[index]))
        }
        pendingToggles = [:]
        save()
        if !mutations.isEmpty {
            recordUndo(completes && restores ? "完了と戻す" : completes ? "完了" : "戻す", mutations)
        }
    }

    /// 猶予を最後の操作から数え直す。保留が空ならタイマーを止める。
    private func restartGraceTimer() {
        cancelGraceTimer?()
        cancelGraceTimer = nil
        guard !pendingToggles.isEmpty else { return }
        cancelGraceTimer = scheduleTimer(Self.graceInterval) { [weak self] in
            self?.commitPending()
        }
    }

    // MARK: - 取り消し

    /// 1つの操作が行った変更。取り消しはこれを逆向きに、やり直しは順向きに当てる。
    /// 取り消し・やり直しの前に、あとから消えた Todo があっても、残りだけを戻す。
    private enum Mutation {
        case add(Todo, at: Int)
        case delete(Todo, at: Int)
        /// 変わった項目だけを当てる（あとから別の項目を直していても、その直しを巻き込まない）。
        case edit(before: Todo, after: Todo)
    }

    /// 直前の操作を取り消す。保留中のものがあれば、先に確定する（いま押した完了をすぐ取り消せるように）。
    func undo() {
        commitPending()
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refreshUndoState()
    }

    /// 取り消した操作をやり直す。保留中のものがあれば、先に確定する。
    func redo() {
        commitPending()
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refreshUndoState()
    }

    /// 操作を行ったあとに呼び、取り消しの履歴に載せる。
    private func recordUndo(_ name: String, _ mutations: [Mutation]) {
        registerStep(mutations, name: name, isForward: true)
    }

    /// `isForward` が true なら、いま順向きに行ったところで、取り消しを登録する。
    /// 取り消しの中から呼ばれたときは、UndoManager が自動でやり直しの側に積む。
    private func registerStep(_ mutations: [Mutation], name: String, isForward: Bool) {
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { store in
            store.apply(mutations, forward: !isForward)
            store.registerStep(mutations, name: name, isForward: !isForward)
        }
        undoManager.setActionName(name)
        if opensGroup { undoManager.endUndoGrouping() }
        refreshUndoState()
    }

    private func apply(_ mutations: [Mutation], forward: Bool) {
        // 取り消しは、行ったのと逆の順に当てる
        for mutation in forward ? mutations : mutations.reversed() {
            switch (mutation, forward) {
            case (.add(let todo, let index), true), (.delete(let todo, let index), false):
                guard !todos.contains(where: { $0.id == todo.id }) else { continue }
                todos.insert(todo, at: min(index, todos.count))
            case (.add(let todo, _), false), (.delete(let todo, _), true):
                guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { continue }
                todos.remove(at: index)
                pendingToggles.removeValue(forKey: todo.id)
            case (.edit(let before, let after), _):
                guard let index = todos.firstIndex(where: { $0.id == before.id }) else { continue }
                let (from, to) = forward ? (before, after) : (after, before)
                todos[index] = todos[index].applying(to, changedFrom: from)
                if from.completedAt != to.completedAt { pendingToggles.removeValue(forKey: before.id) }
            }
        }
        restartGraceTimer()
        save()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
        undoActionName = undoManager.undoActionName
        redoActionName = undoManager.redoActionName
    }

    // MARK: - 保存

    /// 保留中のものを先に確定してから、すぐに保存し、終わるまで待つ。アプリの終了時に使う。
    func saveNow() {
        commitPending()
        persistence.saveNow(todos)
    }

    private func save() {
        persistence.scheduleSave(todos)
    }
}
