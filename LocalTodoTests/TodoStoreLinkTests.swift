import XCTest

@testable import LocalTodo

/// タイトルのリンクに関する `TodoStore` の操作（追加・タイトルの確定・リンクの欄の確定）のテスト。
@MainActor
final class TodoStoreLinkTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoStoreLinkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ text: String) -> URL {
        URL(string: text)!
    }

    // MARK: - 追加（Issue のケース）

    func testAddWholeURLTitleKeepsTitleAndSetsLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "https://example.com/a"))

        XCTAssertEqual(todo.title, "https://example.com/a")
        XCTAssertEqual(todo.titleURL, url("https://example.com/a"))
        XCTAssertEqual(store.todos.first, todo)
    }

    func testAddURLInMiddleExtractsLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "資料 https://a.com 確認"))

        XCTAssertEqual(todo.title, "資料 確認")
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
    }

    func testAddURLAtStartExtractsLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "https://a.com 資料"))

        XCTAssertEqual(todo.title, "資料")
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
    }

    func testAddURLAtEndExtractsLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "資料 https://a.com"))

        XCTAssertEqual(todo.title, "資料")
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
    }

    func testAddTwoURLsUsesFirstAsLinkAndKeepsSecondInTitle() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "資料 https://a.com と https://b.com を見る"))

        XCTAssertEqual(todo.title, "資料 と https://b.com を見る")
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
    }

    func testAddDomainOnlyHasNoLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "メモ example.com を読む"))

        XCTAssertEqual(todo.title, "メモ example.com を読む")
        XCTAssertNil(todo.titleURL)
    }

    func testAddWholeURLWithTagBecomesWholeURLTitleAfterTagExtraction() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "https://x.com #仕事"))

        XCTAssertEqual(todo.tags, ["仕事"])
        XCTAssertEqual(todo.titleURL, url("https://x.com"))
        XCTAssertEqual(todo.title, "https://x.com")
    }

    func testAddURLInTitleWithTagExtractsBoth() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "資料 https://a.com #仕事"))

        XCTAssertEqual(todo.tags, ["仕事"])
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
        XCTAssertEqual(todo.title, "資料")
    }

    // MARK: - 追加の取り消し・やり直し（Issue のケース）

    func testUndoAddRemovesTodoAndRedoRestoresItWithLink() throws {
        let store = try makeStore([])
        let added = try XCTUnwrap(store.add(title: "資料 https://a.com"))

        store.undo()
        XCTAssertTrue(store.todos.isEmpty)

        store.redo()
        XCTAssertEqual(store.todos.first?.id, added.id)
        XCTAssertEqual(store.todos.first?.title, "資料")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    // MARK: - 追加（境目）

    func testAddWithLinkAndTagIsSingleUndoStepNamedAdd() throws {
        let store = try makeStore([])
        store.add(title: "資料 https://a.com #仕事")

        XCTAssertEqual(store.undoActionName, "追加")
        store.undo()

        XCTAssertTrue(store.todos.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    func testAddNormalizesNewlinesBeforeExtractingURL() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "資料\nhttps://a.com\n確認"))

        XCTAssertEqual(todo.title, "資料 確認")
        XCTAssertEqual(todo.titleURL, url("https://a.com"))
    }

    func testAddNonHttpSchemeHasNoLink() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "ftp://example.com/x を見る"))

        XCTAssertEqual(todo.title, "ftp://example.com/x を見る")
        XCTAssertNil(todo.titleURL)
    }

    // MARK: - 確定（Issue のケース）

    func testCommitTitleWithoutURLKeepsExistingLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "新しい資料")

        XCTAssertEqual(store.todos.first?.title, "新しい資料")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    func testCommitTitleWithURLReplacesLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "資料 https://b.com")

        XCTAssertEqual(store.todos.first?.title, "資料")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
        XCTAssertEqual(shown, "資料")
    }

    func testUndoCommitTitleRestoresTitleAndLinkTogether() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])
        store.commitTitle(id: todo.id, text: "提案 https://b.com")

        XCTAssertEqual(store.undoActionName, "タイトルの編集")
        store.undo()

        XCTAssertEqual(store.todos.first?.title, "資料")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
        XCTAssertFalse(store.canUndo)

        store.redo()
        XCTAssertEqual(store.todos.first?.title, "提案")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
    }

    // MARK: - 確定（境目）

    func testCommitTitleSetsLinkOnTodoWithoutLink() throws {
        let todo = Todo(title: "資料")
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "資料 https://a.com")

        XCTAssertEqual(store.todos.first?.title, "資料")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    func testCommitTitleWithTagAndURLIsSingleUndoStep() throws {
        let todo = Todo(title: "資料")
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "提案 https://a.com #仕事")

        XCTAssertEqual(store.todos.first?.title, "提案")
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))

        store.undo()
        XCTAssertEqual(store.todos.first?.title, "資料")
        XCTAssertEqual(store.todos.first?.tags, [])
        XCTAssertNil(store.todos.first?.titleURL)
        XCTAssertFalse(store.canUndo)
    }

    func testCommitTitleChangingOnlyLinkCommitsAndCanUndo() throws {
        // タイトルが同じでもリンクが変わるときは確定する
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "資料 https://b.com")

        XCTAssertEqual(store.undoActionName, "タイトルの編集")
        store.undo()
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    func testCommitSameTitleAndSameLinkChangesNothing() throws {
        // 保存・読み込みで createdAt がミリ秒に丸められるので、丸めても変わらない日時にする
        let todo = Todo(
            title: "資料", titleURL: url("https://a.com"), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "資料 https://a.com")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "資料")
    }

    func testCommitUnchangedWholeURLTitleChangesNothing() throws {
        let todo = Todo(
            title: "https://a.com", titleURL: url("https://a.com"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "https://a.com")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "https://a.com")
    }

    func testCommitWholeURLTitleReplacesLinkAndKeepsTitleAsURL() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.todos.first?.title, "https://b.com")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
        XCTAssertEqual(shown, "https://b.com")
    }

    func testCommitTitleWithDomainOnlyKeepsExistingLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "メモ example.com")

        XCTAssertEqual(store.todos.first?.title, "メモ example.com")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    // MARK: - リンクの欄（Issue のケース）

    func testCommitLinkFieldChangesLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
        XCTAssertEqual(shown, "https://b.com")
        XCTAssertEqual(store.todos.first?.title, "資料")
    }

    func testCommitEmptyLinkFieldRemovesLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "")

        XCTAssertNil(store.todos.first?.titleURL)
        XCTAssertEqual(shown, "")
    }

    func testCommitLinkFieldWithoutSchemeChangesNothingAndReturnsCurrent() throws {
        let todo = Todo(
            title: "資料", titleURL: url("https://a.com"), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "b.com")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "https://a.com")
    }

    func testCommitLinkFieldWithFtpChangesNothingAndReturnsCurrent() throws {
        let todo = Todo(
            title: "資料", titleURL: url("https://a.com"), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "ftp://b.com")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "https://a.com")
    }

    func testCommitLinkFieldIsSingleUndoStepNamedLinkEdit() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])
        store.commitTitleURL(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.undoActionName, "リンクの編集")
        store.undo()
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
        XCTAssertFalse(store.canUndo)

        store.redo()
        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
    }

    // MARK: - リンクの欄（境目）

    func testCommitLinkFieldSetsLinkOnTodoWithoutLink() throws {
        let todo = Todo(title: "資料")
        let store = try makeStore([todo])

        store.commitTitleURL(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
    }

    func testCommitEmptyLinkFieldUndoRestoresLink() throws {
        let todo = Todo(title: "資料", titleURL: url("https://a.com"))
        let store = try makeStore([todo])
        store.commitTitleURL(id: todo.id, text: "")

        XCTAssertEqual(store.undoActionName, "リンクの編集")
        store.undo()

        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
    }

    func testCommitSameLinkInFieldChangesNothing() throws {
        let todo = Todo(
            title: "資料", titleURL: url("https://a.com"), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "https://a.com")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "https://a.com")
    }

    func testCommitEmptyLinkFieldOnTodoWithoutLinkChangesNothing() throws {
        let todo = Todo(title: "資料", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "")
    }

    func testCommitInvalidLinkFieldOnTodoWithoutLinkReturnsEmpty() throws {
        let todo = Todo(title: "資料")
        let store = try makeStore([todo])

        let shown = store.commitTitleURL(id: todo.id, text: "b.com")

        XCTAssertNil(store.todos.first?.titleURL)
        XCTAssertEqual(shown, "")
    }

    func testCommitLinkFieldDoesNotRewriteTitle() throws {
        // リンクの欄の変更では、タイトルの文字は書き換えない
        let todo = Todo(title: "https://a.com", titleURL: url("https://a.com"))
        let store = try makeStore([todo])

        store.commitTitleURL(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.todos.first?.title, "https://a.com")
    }

    func testCommitLinkFieldWorksOnArchivedTodo() throws {
        let todo = Todo(title: "資料", completedAt: Date(timeIntervalSince1970: 1000))
        let store = try makeStore([todo])

        store.commitTitleURL(id: todo.id, text: "https://b.com")

        XCTAssertEqual(store.todos.first?.titleURL, url("https://b.com"))
    }

    // MARK: - 未編集のタイトルの確定（レビュー指摘）

    func testCommitUneditedTitleWithLeftoverURLChangesNothing() throws {
        // 2つ目の URL はタイトルに残る。何も編集せずに確定（フォーカスを外すだけ）しても、
        // 残した URL を再抽出して、リンクを置き換えない
        let store = try makeStore([])
        let todo = try XCTUnwrap(store.add(title: "資料 https://a.com と https://b.com"))
        XCTAssertEqual(todo.title, "資料 と https://b.com")

        let shown = store.commitTitle(id: todo.id, text: todo.title)

        XCTAssertEqual(store.todos.first?.title, "資料 と https://b.com")
        XCTAssertEqual(store.todos.first?.titleURL, url("https://a.com"))
        XCTAssertEqual(shown, "資料 と https://b.com")
        XCTAssertEqual(store.undoActionName, "追加")
    }

    func testCommitUneditedWholeURLTitleDoesNotRestoreRemovedLink() throws {
        // リンク欄でリンクを外したあと、未編集のタイトル（全体が URL）を確定しても、リンクは復活しない
        let store = try makeStore([])
        let todo = try XCTUnwrap(store.add(title: "https://a.com"))
        store.commitTitleURL(id: todo.id, text: "")

        store.commitTitle(id: todo.id, text: "https://a.com")

        XCTAssertNil(store.todos.first?.titleURL)
        XCTAssertEqual(store.undoActionName, "リンクの編集")
    }

    // MARK: - ヘルパー

    private func makeStore(_ todos: [Todo]) throws -> TodoStore {
        try Persistence.encode(todos).write(to: directory.appendingPathComponent("todos.json"))
        return TodoStore(persistence: Persistence(directory: directory, saveDelay: 0.05))
    }
}
