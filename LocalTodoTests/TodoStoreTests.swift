import XCTest

@testable import LocalTodo

@MainActor
final class TodoStoreTests: XCTestCase {
    private var directory: URL!
    private var clock: TestClock!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        clock = TestClock(now: try date(2026, 11, 25, 12, 0, 0))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 読み込み

    func testLoadsTodosFromFileAtStart() throws {
        try writeFile([Todo(title: "前回の分", createdAt: try date(2026, 11, 24, 9, 0, 0))])

        let store = makeStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["前回の分"])
    }

    func testLoadSourceIsFileWhenTodosJSONIsRead() throws {
        try writeFile([Todo(title: "前回の分")])
        XCTAssertEqual(makeStore().loadSource, .file)
    }

    func testLoadSourceIsNoFileOnFirstLaunch() {
        let store = makeStore()
        XCTAssertEqual(store.loadSource, .noFile)
        XCTAssertTrue(store.inboxTodos.isEmpty)
        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testLoadSourceIsBackupWhenOnlyBackupIsReadable() throws {
        try Data("壊れた中身".utf8).write(to: fileURL)
        try Persistence.encode([Todo(title: "バックアップ")]).write(to: backupURL)

        let store = makeStore()

        XCTAssertEqual(store.loadSource, .backup)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["バックアップ"])
    }

    func testLoadSourceIsUnreadableWhenNoFileCanBeRead() throws {
        try Data("壊れた中身".utf8).write(to: fileURL)

        let store = makeStore()

        XCTAssertEqual(store.loadSource, .unreadable)
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testMemoryIsTruthAfterLoading() throws {
        try writeFile([Todo(title: "読み込んだ分")])
        let store = makeStore()

        // 読み込んだあとにファイルが変わっても、メモリ上のデータを使い続ける
        try writeFile([Todo(title: "あとから書き換えた分")])

        XCTAssertEqual(store.inboxTodos.map(\.title), ["読み込んだ分"])
    }

    func testNoSaveErrorAtStart() {
        XCTAssertNil(makeStore().lastSaveError)
    }

    // MARK: - 追加

    func testAddPutsTodoInInbox() {
        let store = makeStore()

        store.add(title: "企画書を送る")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["企画書を送る"])
        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testAddReturnsAddedTodo() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "企画書を送る"))

        XCTAssertEqual(store.inboxTodos.map(\.id), [added.id])
        XCTAssertEqual(added.title, "企画書を送る")
    }

    func testAddUsesCurrentTimeAsCreatedAt() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "企画書を送る"))

        XCTAssertEqual(added.createdAt, clock.now)
        XCTAssertEqual(store.inboxTodos.first?.createdAt, clock.now)
    }

    func testAddedTodoIsNotCompleted() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "企画書を送る"))

        XCTAssertNil(added.completedAt)
    }

    func testAddTrimsLeadingAndTrailingSpaces() {
        let store = makeStore()

        store.add(title: "  企画書を送る  ")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["企画書を送る"])
    }

    func testAddTrimsLeadingAndTrailingNewlines() {
        let store = makeStore()

        store.add(title: "\n\t企画書を送る\r\n")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["企画書を送る"])
    }

    func testAddTrimsFullWidthSpaces() {
        let store = makeStore()

        // 全角の空白も、前後の空白として除く
        store.add(title: "\u{3000}企画書を送る\u{3000}")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["企画書を送る"])
    }

    func testAddKeepsSpacesInsideTitle() {
        let store = makeStore()

        store.add(title: " 企画書を  送る ")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["企画書を  送る"])
    }

    func testAddRejectsEmptyTitle() {
        let store = makeStore()

        XCTAssertNil(store.add(title: ""))
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testAddRejectsTitleOfOnlySpaces() {
        let store = makeStore()

        XCTAssertNil(store.add(title: "   "))
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testAddRejectsTitleOfOnlyNewlines() {
        let store = makeStore()

        XCTAssertNil(store.add(title: "\n\r\n\t \u{3000}"))
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testAddRejectingEmptyTitleKeepsExistingTodos() throws {
        try writeFile([Todo(title: "前回の分")])
        let store = makeStore()

        store.add(title: "  ")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["前回の分"])
    }

    func testAddAcceptsSingleCharacterTitle() {
        let store = makeStore()

        XCTAssertNotNil(store.add(title: " a "))
        XCTAssertEqual(store.inboxTodos.map(\.title), ["a"])
    }

    func testAddDoesNotExtractTags() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "資料を作る #仕事"))

        // タグの取り出しは #17 でする
        XCTAssertEqual(added.title, "資料を作る #仕事")
        XCTAssertTrue(added.tags.isEmpty)
    }

    func testAddDoesNotLinkURL() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "https://example.com/plan"))

        // URL のリンク化は #22 でする
        XCTAssertEqual(added.title, "https://example.com/plan")
        XCTAssertNil(added.titleURL)
        XCTAssertTrue(added.links.isEmpty)
    }

    func testAddGivesEachTodoItsOwnID() throws {
        let store = makeStore()

        let first = try XCTUnwrap(store.add(title: "同じタイトル"))
        let second = try XCTUnwrap(store.add(title: "同じタイトル"))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.inboxTodos.count, 2)
    }

    func testAddIsSaved() throws {
        let store = makeStore()

        store.add(title: "企画書を送る")

        waitForScheduledSave()
        XCTAssertEqual(try titlesInFile(), ["企画書を送る"])
    }

    // MARK: - 追加・タイトルの途中の改行

    func testAddReplacesNewlineInsideTitleWithSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\n卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
        XCTAssertEqual(store.inboxTodos.map(\.title), ["牛乳 卵"])
    }

    func testAddCollapsesConsecutiveLineFeedsIntoOneSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\n\n卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddReplacesCRLFWithOneSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\r\n卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddTrimsNewlinesAroundTitleInsteadOfReplacingThem() throws {
        let store = makeStore()

        // 前後の改行はスペースにせず、取り除く
        let added = try XCTUnwrap(store.add(title: "\n牛乳\n"))

        XCTAssertEqual(added.title, "牛乳")
    }

    func testAddReplacesCarriageReturnAloneWithSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\r卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddCollapsesConsecutiveCRLFsIntoOneSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\r\n\r\n卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddCollapsesMixedNewlinesIntoOneSpace() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "牛乳\n\r\n\r卵"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddReplacesEachSeparateNewlineWithItsOwnSpace() throws {
        let store = makeStore()

        // 離れた改行は、それぞれ1つのスペースになる
        let added = try XCTUnwrap(store.add(title: "牛乳\n卵\nパン"))

        XCTAssertEqual(added.title, "牛乳 卵 パン")
    }

    func testAddTrimsSurroundingNewlinesAndReplacesInnerOnes() throws {
        let store = makeStore()

        let added = try XCTUnwrap(store.add(title: "\r\n\n牛乳\n\n卵\r\n"))

        XCTAssertEqual(added.title, "牛乳 卵")
    }

    func testAddKeepsSpacesNextToInnerNewline() throws {
        let store = makeStore()

        // 置き換えるのは改行だけ。改行の両側の空白はそのまま残る
        let added = try XCTUnwrap(store.add(title: "牛乳 \n 卵"))

        XCTAssertEqual(added.title, "牛乳   卵")
    }

    func testAddKeepsTabInsideTitle() throws {
        let store = makeStore()

        // タブは改行ではないので置き換えない
        let added = try XCTUnwrap(store.add(title: "牛乳\t卵"))

        XCTAssertEqual(added.title, "牛乳\t卵")
    }

    func testAddSavesTitleWithNewlineReplaced() throws {
        let store = makeStore()

        store.add(title: "牛乳\n卵")

        waitForScheduledSave()
        XCTAssertEqual(try titlesInFile(), ["牛乳 卵"])
    }

    // MARK: - 編集

    func testUpdateReplacesTodoWithSameID() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "企画書を送る"))
        let link = TodoLink(url: try XCTUnwrap(URL(string: "https://example.com/a")), displayName: "資料 A")

        todo.title = "企画書を直して送る"
        todo.titleURL = URL(string: "https://example.com/plan")
        todo.links = [link]
        todo.descriptionText = "1行目\n2行目"
        todo.dueDate = CalendarDay(try date(2026, 11, 26, 9, 0, 0), calendar: Calendar(identifier: .gregorian))
        todo.tags = ["仕事"]
        store.update(todo)

        let updated = try XCTUnwrap(store.inboxTodos.first)
        XCTAssertEqual(store.inboxTodos.count, 1)
        XCTAssertEqual(updated, todo)
    }

    func testUpdateLeavesOtherTodosAlone() throws {
        let store = makeStore()
        let other = try XCTUnwrap(store.add(title: "ほかの Todo"))
        var todo = try XCTUnwrap(store.add(title: "企画書を送る"))

        todo.title = "企画書を直して送る"
        store.update(todo)

        XCTAssertEqual(store.inboxTodos.first { $0.id == other.id }, other)
    }

    func testUpdateWithUnknownIDDoesNothing() throws {
        let store = makeStore()
        store.add(title: "企画書を送る")
        let before = store.inboxTodos

        store.update(Todo(title: "知らない Todo"))

        XCTAssertEqual(store.inboxTodos, before)
        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testUpdateIgnoresCompletedAtOfInboxTodo() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "企画書を送る"))

        // 完了は #7 の専用の操作でする。編集では完了日時を変えない
        todo.completedAt = try date(2026, 11, 25, 13, 0, 0)
        store.update(todo)

        XCTAssertEqual(store.inboxTodos.map(\.id), [todo.id])
        XCTAssertNil(store.inboxTodos.first?.completedAt)
        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testUpdateIgnoresClearedCompletedAtOfArchivedTodo() throws {
        let completedAt = try date(2026, 11, 24, 18, 0, 0)
        var todo = Todo(title: "済んだ Todo", createdAt: try date(2026, 11, 24, 9, 0, 0), completedAt: completedAt)
        try writeFile([todo])
        let store = makeStore()

        // 戻すは #7 の専用の操作でする。編集では完了日時を消さない
        todo.completedAt = nil
        store.update(todo)

        XCTAssertEqual(store.archivedTodos.map(\.id), [todo.id])
        XCTAssertEqual(store.archivedTodos.first?.completedAt, completedAt)
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testUpdateIgnoresChangedCompletedAtOfArchivedTodo() throws {
        let completedAt = try date(2026, 11, 24, 18, 0, 0)
        var todo = Todo(title: "済んだ Todo", createdAt: try date(2026, 11, 24, 9, 0, 0), completedAt: completedAt)
        try writeFile([todo])
        let store = makeStore()

        todo.completedAt = try date(2026, 11, 25, 10, 0, 0)
        store.update(todo)

        XCTAssertEqual(store.archivedTodos.first?.completedAt, completedAt)
    }

    func testUpdateChangesArchivedTodo() throws {
        var todo = Todo(
            title: "済んだ Todo", createdAt: try date(2026, 11, 24, 9, 0, 0),
            completedAt: try date(2026, 11, 24, 18, 0, 0))
        try writeFile([todo])
        let store = makeStore()

        todo.title = "済んだ Todo（直した）"
        store.update(todo)

        XCTAssertEqual(store.archivedTodos.map(\.title), ["済んだ Todo（直した）"])
    }

    func testUpdateIsSaved() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "企画書を送る"))
        waitForScheduledSave()

        todo.title = "企画書を直して送る"
        store.update(todo)

        waitForScheduledSave()
        XCTAssertEqual(try titlesInFile(), ["企画書を直して送る"])
    }

    // MARK: - 削除

    func testDeleteRemovesInboxTodo() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "企画書を送る"))

        store.delete(id: todo.id)

        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testDeleteRemovesArchivedTodo() throws {
        let todo = Todo(
            title: "済んだ Todo", createdAt: try date(2026, 11, 24, 9, 0, 0),
            completedAt: try date(2026, 11, 24, 18, 0, 0))
        try writeFile([todo])
        let store = makeStore()

        store.delete(id: todo.id)

        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testDeleteRemovesOnlyThatTodo() throws {
        let store = makeStore()
        let first = try XCTUnwrap(store.add(title: "1件目"))
        let second = try XCTUnwrap(store.add(title: "2件目"))
        let third = try XCTUnwrap(store.add(title: "3件目"))

        store.delete(id: second.id)

        XCTAssertEqual(Set(store.inboxTodos.map(\.id)), [first.id, third.id])
    }

    func testDeleteWithUnknownIDDoesNothing() throws {
        let store = makeStore()
        store.add(title: "企画書を送る")
        let before = store.inboxTodos

        store.delete(id: UUID())

        XCTAssertEqual(store.inboxTodos, before)
    }

    func testDeleteTwiceDoesNothingTheSecondTime() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "消す"))
        let kept = try XCTUnwrap(store.add(title: "残す"))

        store.delete(id: todo.id)
        store.delete(id: todo.id)

        XCTAssertEqual(store.inboxTodos.map(\.id), [kept.id])
    }

    func testDeleteIsSaved() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "消す"))
        store.add(title: "残す")
        waitForScheduledSave()

        store.delete(id: todo.id)

        waitForScheduledSave()
        XCTAssertEqual(try titlesInFile(), ["残す"])
    }

    // MARK: - 一覧・Inbox

    func testInboxIsSortedByNewestCreatedAt() throws {
        let store = makeStore()
        store.add(title: "古い")
        clock.now += 1
        store.add(title: "新しい")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["新しい", "古い"])
    }

    func testInboxIsSortedByCreatedAtNotByFileOrder() throws {
        // ファイルの順と作成日時の順を逆にしておく
        try writeFile([
            Todo(title: "古い", createdAt: try date(2026, 11, 23, 9, 0, 0)),
            Todo(title: "新しい", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(title: "いちばん古い", createdAt: try date(2026, 11, 22, 9, 0, 0)),
        ])

        let store = makeStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["新しい", "古い", "いちばん古い"])
    }

    func testInboxPutsLaterAddedFirstWhenCreatedAtIsSame() throws {
        let store = makeStore()

        // 時刻を進めずに追加する
        store.add(title: "先に追加")
        store.add(title: "あとに追加")

        XCTAssertEqual(store.inboxTodos.map(\.title), ["あとに追加", "先に追加"])
    }

    func testInboxReversesFileOrderWhenCreatedAtIsSame() throws {
        let createdAt = try date(2026, 11, 24, 9, 0, 0)
        try writeFile([
            Todo(title: "1番目", createdAt: createdAt),
            Todo(title: "2番目", createdAt: createdAt),
            Todo(title: "3番目", createdAt: createdAt),
        ])

        let store = makeStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["3番目", "2番目", "1番目"])
    }

    func testInboxExcludesArchivedTodos() throws {
        try writeFile([
            Todo(title: "Inbox", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 10, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0)),
        ])

        let store = makeStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["Inbox"])
    }

    func testInboxKeepsOrderAfterUpdate() throws {
        let store = makeStore()
        var old = try XCTUnwrap(store.add(title: "古い"))
        clock.now += 1
        store.add(title: "新しい")

        // 編集しても作成日時は変わらないので、並びも変わらない
        old.title = "古い（直した）"
        store.update(old)

        XCTAssertEqual(store.inboxTodos.map(\.title), ["新しい", "古い（直した）"])
    }

    // MARK: - 一覧・アーカイブ

    func testArchiveIsSortedByNewestCompletedAt() throws {
        // 作成日時の順と完了日時の順を逆にしておく
        try writeFile([
            Todo(
                title: "先に完了", createdAt: try date(2026, 11, 20, 9, 0, 0),
                completedAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(
                title: "あとで完了", createdAt: try date(2026, 11, 19, 9, 0, 0),
                completedAt: try date(2026, 11, 23, 9, 0, 0)),
            Todo(
                title: "いちばん先に完了", createdAt: try date(2026, 11, 21, 9, 0, 0),
                completedAt: try date(2026, 11, 21, 18, 0, 0)),
        ])

        let store = makeStore()

        XCTAssertEqual(store.archivedTodos.map(\.title), ["あとで完了", "先に完了", "いちばん先に完了"])
    }

    func testArchiveReversesFileOrderWhenCompletedAtIsSame() throws {
        let completedAt = try date(2026, 11, 24, 18, 0, 0)
        try writeFile([
            Todo(title: "1番目", createdAt: try date(2026, 11, 24, 9, 0, 0), completedAt: completedAt),
            Todo(title: "2番目", createdAt: try date(2026, 11, 23, 9, 0, 0), completedAt: completedAt),
            Todo(title: "3番目", createdAt: try date(2026, 11, 22, 9, 0, 0), completedAt: completedAt),
        ])

        let store = makeStore()

        XCTAssertEqual(store.archivedTodos.map(\.title), ["3番目", "2番目", "1番目"])
    }

    func testArchiveExcludesInboxTodos() throws {
        try writeFile([
            Todo(title: "Inbox", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 10, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0)),
        ])

        let store = makeStore()

        XCTAssertEqual(store.archivedTodos.map(\.title), ["アーカイブ"])
    }

    // MARK: - すぐ保存

    func testSaveNowWritesCurrentTodosImmediately() throws {
        // 予約の保存が先に書かれないよう、待ち時間を長くする
        let store = makeStore(saveDelay: 10)
        store.add(title: "企画書を送る")

        store.saveNow()

        XCTAssertEqual(try titlesInFile(), ["企画書を送る"])
    }

    func testSaveNowKeepsArchivedTodos() throws {
        try writeFile([
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 10, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0))
        ])
        let store = makeStore(saveDelay: 10)
        store.add(title: "Inbox")

        store.saveNow()

        XCTAssertEqual(Set(try titlesInFile()), ["アーカイブ", "Inbox"])
    }

    // MARK: - 保存の失敗

    func testSaveErrorIsKeptAsState() throws {
        // フォルダのはずの場所にファイルを置き、書き込めないようにする
        let notADirectory = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: notADirectory)
        let clock = clock!
        let store = TodoStore(
            persistence: Persistence(directory: notADirectory, saveDelay: 0),
            now: { clock.now })

        store.add(title: "保存できない")
        store.saveNow()

        // 失敗はメインスレッドへ非同期に知らされるので、少し回して待つ
        let deadline = Date.now + 2
        while store.lastSaveError == nil && Date.now < deadline {
            RunLoop.main.run(until: .now + 0.01)
        }
        XCTAssertNotNil(store.lastSaveError)
    }

    // MARK: - 期限日順の並びと見出し

    func testInboxIsSortedByDueDateEarliestFirst() throws {
        try writeFile([
            Todo(title: "あさって", dueDate: try day(2026, 11, 27)),
            Todo(title: "昨日", dueDate: try day(2026, 11, 24)),
            Todo(title: "今日", dueDate: try day(2026, 11, 25)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["昨日", "今日", "あさって"])
    }

    func testInboxPutsNoDueDateLast() throws {
        try writeFile([
            Todo(title: "期限なし", createdAt: try date(2026, 11, 25, 9, 0, 0)),
            Todo(title: "遠い期限", dueDate: try day(2030, 1, 1)),
            Todo(title: "昨日", dueDate: try day(2026, 11, 24)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["昨日", "遠い期限", "期限なし"])
    }

    func testInboxSortsSameDueDateByCreatedAtNewestFirst() throws {
        try writeFile([
            Todo(title: "古い", dueDate: try day(2026, 11, 25), createdAt: try date(2026, 11, 1, 9, 0, 0)),
            Todo(title: "新しい", dueDate: try day(2026, 11, 25), createdAt: try date(2026, 11, 20, 9, 0, 0)),
            Todo(title: "中間", dueDate: try day(2026, 11, 25), createdAt: try date(2026, 11, 10, 9, 0, 0)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["新しい", "中間", "古い"])
    }

    func testInboxSortsNoDueDateByCreatedAtNewestFirst() throws {
        try writeFile([
            Todo(title: "古い", createdAt: try date(2026, 11, 1, 9, 0, 0)),
            Todo(title: "新しい", createdAt: try date(2026, 11, 20, 9, 0, 0)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["新しい", "古い"])
    }

    func testDueDateOrderBeatsCreatedAt() throws {
        try writeFile([
            Todo(title: "期限が遅い・新しい", dueDate: try day(2026, 12, 1), createdAt: try date(2026, 11, 20, 9, 0, 0)),
            Todo(title: "期限が早い・古い", dueDate: try day(2026, 11, 26), createdAt: try date(2026, 11, 1, 9, 0, 0)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.inboxTodos.map(\.title), ["期限が早い・古い", "期限が遅い・新しい"])
    }

    func testArchivedTodosOrderIsNotAffectedByDueDate() throws {
        try writeFile([
            Todo(title: "先に完了", dueDate: try day(2026, 11, 20), completedAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(title: "あとに完了", dueDate: try day(2026, 12, 20), completedAt: try date(2026, 11, 23, 9, 0, 0)),
        ])

        let store = makeTokyoStore()

        XCTAssertEqual(store.archivedTodos.map(\.title), ["あとに完了", "先に完了"])
    }

    func testSectionsAssignHeadingsByDueDate() throws {
        try writeFile([
            Todo(title: "昨日", dueDate: try day(2026, 11, 24)),
            Todo(title: "今日", dueDate: try day(2026, 11, 25)),
            Todo(title: "明日", dueDate: try day(2026, 11, 26)),
            Todo(title: "期限なし"),
        ])

        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 12, 0, 0))

        XCTAssertEqual(sections.map(\.heading), [.beforeToday, .today, .afterToday, .noDueDate])
        XCTAssertEqual(sections.map { $0.todos.map(\.title) }, [["昨日"], ["今日"], ["明日"], ["期限なし"]])
    }

    func testSectionsBoundaryBetweenYesterdayAndToday() throws {
        try writeFile([
            Todo(title: "昨日の終わり", dueDate: try day(2026, 11, 24)),
            Todo(title: "今日", dueDate: try day(2026, 11, 25)),
        ])

        // 今日の 0:00 ちょうど
        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 0, 0, 0))

        XCTAssertEqual(sections.first { $0.heading == .beforeToday }?.todos.map(\.title), ["昨日の終わり"])
        XCTAssertEqual(sections.first { $0.heading == .today }?.todos.map(\.title), ["今日"])
    }

    func testSectionsBoundaryBetweenTodayAndTomorrow() throws {
        try writeFile([
            Todo(title: "今日", dueDate: try day(2026, 11, 25)),
            Todo(title: "明日", dueDate: try day(2026, 11, 26)),
        ])

        // 今日の 23:59:59
        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 23, 59, 59))

        XCTAssertEqual(sections.first { $0.heading == .today }?.todos.map(\.title), ["今日"])
        XCTAssertEqual(sections.first { $0.heading == .afterToday }?.todos.map(\.title), ["明日"])
    }

    func testSectionsUseGivenNowNotStoreClock() throws {
        try writeFile([Todo(title: "11/25 が期限", dueDate: try day(2026, 11, 25))])
        let store = makeTokyoStore()  // ストアの時計は 11/25

        let sections = store.inboxSections(now: try date(2026, 11, 26, 12, 0, 0))

        XCTAssertEqual(sections.map(\.heading), [.beforeToday])
    }

    func testSectionsOmitHeadingsWithNoTodos() throws {
        try writeFile([
            Todo(title: "今日", dueDate: try day(2026, 11, 25)),
            Todo(title: "期限なし"),
        ])

        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 12, 0, 0))

        XCTAssertEqual(sections.map(\.heading), [.today, .noDueDate])
    }

    func testSectionsAreEmptyWhenInboxIsEmpty() throws {
        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 12, 0, 0))

        XCTAssertTrue(sections.isEmpty)
    }

    func testSectionsAreEmptyWhenOnlyArchivedTodosExist() throws {
        try writeFile([Todo(title: "完了", dueDate: try day(2026, 11, 20), completedAt: try date(2026, 11, 21, 9, 0, 0))])

        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 12, 0, 0))

        XCTAssertTrue(sections.isEmpty)
    }

    func testSectionsKeepSortOrderInsideEachHeading() throws {
        try writeFile([
            Todo(title: "明後日", dueDate: try day(2026, 11, 27)),
            Todo(title: "明日", dueDate: try day(2026, 11, 26)),
            Todo(title: "一昨日", dueDate: try day(2026, 11, 23)),
            Todo(title: "昨日", dueDate: try day(2026, 11, 24)),
        ])

        let sections = makeTokyoStore().inboxSections(now: try date(2026, 11, 25, 12, 0, 0))

        XCTAssertEqual(sections.map { $0.todos.map(\.title) }, [["一昨日", "昨日"], ["明日", "明後日"]])
    }

    // MARK: - ヘルパー

    /// 期限日の見出しのテスト用。「今日」を決めるカレンダーを Asia/Tokyo にしたストア。
    private func makeTokyoStore() -> TodoStore {
        let clock = clock!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return TodoStore(
            persistence: Persistence(directory: directory, saveDelay: Self.saveDelay),
            now: { clock.now },
            calendar: calendar)
    }

    /// 東京の暦での期限日。
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return CalendarDay(try date(year, month, day, 12, 0, 0), calendar: calendar)
    }

    /// テストから進められる「今の時刻」。
    private final class TestClock {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }

    private var fileURL: URL { directory.appendingPathComponent("todos.json") }
    private var backupURL: URL { directory.appendingPathComponent("todos.backup.json") }

    private nonisolated static let saveDelay: TimeInterval = 0.05

    private func makeStore(saveDelay: TimeInterval = TodoStoreTests.saveDelay) -> TodoStore {
        let clock = clock!
        return TodoStore(
            persistence: Persistence(directory: directory, saveDelay: saveDelay),
            now: { clock.now })
    }

    private func writeFile(_ todos: [Todo]) throws {
        try Persistence.encode(todos).write(to: fileURL)
    }

    private func titlesInFile() throws -> [String] {
        try Persistence.decode(Data(contentsOf: fileURL)).map(\.title)
    }

    /// 予約された保存が書き込まれるまで待つ。
    private func waitForScheduledSave() {
        Thread.sleep(forTimeInterval: Self.saveDelay + 0.25)
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)))
    }
}
