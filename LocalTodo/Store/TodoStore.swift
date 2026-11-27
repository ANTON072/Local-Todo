import Foundation
import Observation

/// Inbox の、1つの見出しとそこに入る Todo。
struct DueSection: Identifiable, Equatable {
    let heading: DueHeading
    let todos: [Todo]

    var id: DueHeading { heading }
}

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
    /// 期限日の「今日」を決めるカレンダー（タイムゾーン）。テストで差し替える。
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let scheduleTimer: Scheduler
    @ObservationIgnored private var cancelGraceTimer: (() -> Void)?

    /// - Parameters:
    ///   - persistence: 保存先。テストでは一時フォルダのものを渡す。保存の失敗を受け取るため、
    ///     `onSaveError` をこの TodoStore が差し替える。
    ///   - now: 今の時刻。テストで差し替える。
    ///   - calendar: 期限日の「今日」を決めるカレンダー。テストで差し替える。
    ///   - scheduleTimer: 保留を確定するまでの猶予を数えるタイマー。テストでは、時間を進めたら動く偽物を渡す。
    init(
        persistence: Persistence,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current,
        scheduleTimer: @escaping Scheduler = TodoStore.mainQueueScheduler
    ) {
        self.persistence = persistence
        self.now = now
        self.calendar = calendar
        self.scheduleTimer = scheduleTimer
        let result = persistence.load()
        todos = result.todos
        loadSource = result.source
        persistence.onSaveError = { [weak self] error in
            self?.lastSaveError = error
        }
    }

    // MARK: - 一覧

    /// 期限日の早い順。期限なしは末尾。同じ期限日の中は、作成日時の新しい順。
    /// 作成日時も同じなら、あとから加わったもの（配列で後ろにあるもの）を上にする。
    var inboxTodos: [Todo] {
        inboxTodos(order: .dueDate)
    }

    /// 並び順を指定した Inbox。作成日順は、期限日と関係なく作成日時の新しい順
    /// （同じなら、あとから加わったものを上にする）。
    func inboxTodos(order: InboxSortOrder) -> [Todo] {
        let active = todos.enumerated().filter { !$0.element.isArchived }
        switch order {
        case .dueDate:
            return active.sorted { lhs, rhs in
                switch (lhs.element.dueDate, rhs.element.dueDate) {
                case (let lhsDay?, let rhsDay?) where lhsDay != rhsDay: return lhsDay < rhsDay
                case (.some, .none): return true
                case (.none, .some): return false
                default: return Self.isNewer(lhs, than: rhs)
                }
            }.map(\.element)
        case .createdAt:
            return active.sorted(by: Self.isNewer).map(\.element)
        }
    }

    private static func isNewer(_ lhs: (offset: Int, element: Todo), than rhs: (offset: Int, element: Todo)) -> Bool {
        let (lhsDate, rhsDate) = (lhs.element.createdAt, rhs.element.createdAt)
        return lhsDate != rhsDate ? lhsDate > rhsDate : lhs.offset > rhs.offset
    }

    /// Inbox を見出しで区切ったもの。見出しは「期限切れ」「今日」「明日以降」「期限なし」の順で、
    /// Todo が1件もない見出しは含めない。「今日」は `now` で決める（呼ぶたびに取り直す）。
    func inboxSections(now: Date) -> [DueSection] {
        let grouped = Dictionary(grouping: inboxTodos) { $0.dueHeading(now: now, calendar: calendar) }
        return DueHeading.allCases.compactMap { heading in
            grouped[heading].map { DueSection(heading: heading, todos: $0) }
        }
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
    /// タイトルの `#タグ` は取り除いてタグにする（`titleAndTags(from:)`）。
    /// - Returns: 追加した Todo。除いたあと（タグを取り除いたあとも）に空なら追加せず nil を返す。
    @discardableResult
    func add(title: String) -> Todo? {
        guard let parsed = titleParts(from: title) else { return nil }
        let todo = Todo(title: parsed.title, titleURL: parsed.link, tags: parsed.tags, createdAt: now())
        todos.append(todo)
        save()
        recordUndo("追加", [.add(todo, at: todos.count - 1)])
        return todo
    }

    /// 詳細ペインのタイトル欄に打たれた文字列を、`add(title:)` と同じ整え方でタイトルにする。
    /// 整えたあとが空なら確定しない（空のタイトルの Todo は一覧で見えなくなるため）。
    /// タイトルの `#タグ` は取り除き、その Todo がすでに持つタグの後ろに足す（置き換えない）。
    /// タイトルに URL があれば、タイトルのリンクをその URL に置き換える（なければ今のリンクのまま）。
    /// 整えたあとのタイトルが今と同じで、足すタグもなく、リンクも変わらないなら、置き換えも保存もしない
    /// （フォーカスが外れるたびに呼ばれるので、何も変えていない操作で保存や取り消しの履歴を増やさない）。
    /// - Returns: 欄に出す文字列。確定したら新しいタイトル、確定しなかったら今のタイトル。
    ///   ID の Todo がなければ何も変えず、整えた文字列（空なら空文字列）を返す。
    @discardableResult
    func commitTitle(id: Todo.ID, text: String) -> String {
        let parsed = titleParts(from: text)
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return parsed?.title ?? "" }
        let current = todos[index].title
        // 何も編集していない（整えたあとが今のタイトルと同じ）なら、何もしない。
        // 抽出し直すと、タイトルに残した2つ目の URL が、リンクを置き換えてしまうため
        // （全体が URL のタイトルは、リンク欄で外したリンクが復活してしまう）。
        guard Self.normalizedTitle(text) != current else { return current }
        guard let parsed else { return current }
        let tags =
            todos[index].tags
            + parsed.tags.filter { new in
                !todos[index].tags.contains { TagParser.isSameTag($0, new) }
            }
        let link = parsed.link ?? todos[index].titleURL
        guard parsed.title != current || tags != todos[index].tags || link != todos[index].titleURL else {
            return current
        }
        let before = todos[index]
        todos[index].title = parsed.title
        todos[index].tags = tags
        todos[index].titleURL = link
        save()
        recordUndo("タイトルの編集", [.edit(before: before, after: todos[index])])
        return parsed.title
    }

    /// 入力された文字列を、タイトルと、そこから取り出したタグ・タイトルのリンクにする。
    /// タイトルは `normalizedTitle` で整えたあと、`TagParser` で `#タグ` を、続けて
    /// `LinkTitleFetcher` で URL を取り除く。タグを先に取るのは、`https://x.com #仕事` のように、
    /// タグを取ったあとが「タイトル全体が URL」になる入力を、追加できるようにするため
    /// （URL を先に取ると、残りがタグだけになってタイトルが空になる）。
    /// 取り除いたあとのタイトルが空なら nil（空のタイトルの Todo は一覧で見えないため）。
    ///
    /// タグは、全 Todo（アーカイブも含む）にすでにある同じタグの書き方にそろえる。
    /// 複数の書き方があれば、配列で先にある Todo の書き方にする。1回の入力の中の重複は、
    /// 最初に出た書き方を残す。
    private func titleParts(from text: String) -> (title: String, tags: [String], link: URL?)? {
        guard let normalized = Self.normalizedTitle(text) else { return nil }
        let parsed = TagParser.parse(normalized)
        guard !parsed.title.isEmpty else { return nil }
        var known = todos.flatMap(\.tags)
        var tags: [String] = []
        for name in parsed.names {
            let canonical = known.first { TagParser.isSameTag($0, name) } ?? name
            if !known.contains(canonical) { known.append(canonical) }
            if !tags.contains(where: { TagParser.isSameTag($0, canonical) }) { tags.append(canonical) }
        }
        let extracted = LinkTitleFetcher.extract(from: parsed.title)
        return (extracted.title, tags, extracted.url)
    }

    // MARK: - タイトルのリンク

    /// 取り消しのメニューに出す、タイトルのリンクの変更の名前。
    static let titleLinkActionName = "リンクの編集"

    /// 詳細ペインのリンク欄に書かれた文字列で、タイトルのリンクを変える。
    /// - 空（空白だけも）：リンクを外す。
    /// - `http(s)://` の URL：リンクをその URL にする。
    /// - それ以外：何も変えない。
    /// 変わらなければ、保存も取り消しの履歴もしない。1回の変更を1件の取り消しにする。
    /// - Returns: 欄に出す文字列。変えたら新しいリンク（外したら空）、変えなかったら今のリンク。
    @discardableResult
    func commitTitleURL(id: Todo.ID, text: String) -> String {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return "" }
        let current = todos[index].titleURL
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let new: URL?
        if trimmed.isEmpty {
            new = nil
        } else if let url = LinkTitleFetcher.parseLinkField(trimmed) {
            new = url
        } else {
            return current?.absoluteString ?? ""
        }
        guard new != current else { return current?.absoluteString ?? "" }
        let before = todos[index]
        todos[index].titleURL = new
        save()
        recordUndo(Self.titleLinkActionName, [.edit(before: before, after: todos[index])])
        return new?.absoluteString ?? ""
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

    // MARK: - 期限日

    /// 取り消しのメニューに出す、期限日の変更の名前。
    static let dueDateActionName = "期限日の編集"

    /// カレンダーで日を選ぶ。1回の操作を1件として取り消しの履歴に載せる。
    func setDueDay(id: Todo.ID, day: CalendarDay) {
        setDueDate(id: id, to: day)
    }

    /// × で期限を外す。
    func removeDueDate(id: Todo.ID) {
        setDueDate(id: id, to: nil)
    }

    /// 変わらなければ（今と同じ日を選んだときなど）何もせず、取り消しの履歴にも載せない。
    private func setDueDate(id: Todo.ID, to dueDate: CalendarDay?) {
        guard let index = todos.firstIndex(where: { $0.id == id }), todos[index].dueDate != dueDate else { return }
        let before = todos[index]
        todos[index].dueDate = dueDate
        save()
        recordUndo(Self.dueDateActionName, [.edit(before: before, after: todos[index])])
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

    /// 保留中のものを確定したときの取り消しの名前。保留中のものがなければ空文字列。
    /// 保留中は、取り消すと先に確定されるので、メニューの表示名にこれを使う。
    var pendingActionName: String {
        var completes = false
        var restores = false
        for id in pendingToggles.keys {
            guard let todo = todos.first(where: { $0.id == id }) else { continue }
            if todo.isArchived { restores = true } else { completes = true }
        }
        return completes || restores ? Self.completionActionName(completes: completes, restores: restores) : ""
    }

    private static func completionActionName(completes: Bool, restores: Bool) -> String {
        completes && restores ? "完了と戻す" : completes ? "完了" : "戻す"
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
            recordUndo(Self.completionActionName(completes: completes, restores: restores), mutations)
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
            let applied = store.apply(mutations, forward: !isForward)
            store.registerStep(applied, name: name, isForward: !isForward)
        }
        undoManager.setActionName(name)
        if opensGroup { undoManager.endUndoGrouping() }
        refreshUndoState()
    }

    /// 変更を当てる。Todo を取り除くときは、そのときの Todo（取り消しの履歴に載らない更新を含む）を
    /// 取っておき、次に登録する取り消し・やり直しに使えるよう、作り直した変更を返す。
    @discardableResult
    private func apply(_ mutations: [Mutation], forward: Bool) -> [Mutation] {
        var result = mutations
        // 取り消しは、行ったのと逆の順に当てる
        for position in forward ? Array(mutations.indices) : mutations.indices.reversed() {
            switch (mutations[position], forward) {
            case (.add(let todo, let index), true), (.delete(let todo, let index), false):
                guard !todos.contains(where: { $0.id == todo.id }) else { continue }
                todos.insert(todo, at: min(index, todos.count))
            case (.add(let todo, _), false):
                guard let index = remove(id: todo.id) else { continue }
                result[position] = .add(index.todo, at: index.position)
            case (.delete(let todo, _), true):
                guard let index = remove(id: todo.id) else { continue }
                result[position] = .delete(index.todo, at: index.position)
            case (.edit(let before, let after), _):
                guard let index = todos.firstIndex(where: { $0.id == before.id }) else { continue }
                let (from, to) = forward ? (before, after) : (after, before)
                todos[index] = todos[index].applying(to, changedFrom: from)
                if from.completedAt != to.completedAt { pendingToggles.removeValue(forKey: before.id) }
            }
        }
        restartGraceTimer()
        save()
        return result
    }

    /// 取り除いた Todo と、取り除いた位置。保留中なら保留から外す。なければ nil。
    private func remove(id: Todo.ID) -> (todo: Todo, position: Int)? {
        guard let position = todos.firstIndex(where: { $0.id == id }) else { return nil }
        pendingToggles.removeValue(forKey: id)
        return (todos.remove(at: position), position)
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
