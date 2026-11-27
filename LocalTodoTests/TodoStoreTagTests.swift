import XCTest

@testable import LocalTodo

/// タイトルからタグを取り出す `TodoStore` の操作（追加・タイトルの確定）のテスト。
@MainActor
final class TodoStoreTagTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoStoreTagTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 追加（Issue のケース）

    func testAddMovesTagOutOfTitle() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "企画書を送る #仕事"))

        XCTAssertEqual(todo.title, "企画書を送る")
        XCTAssertEqual(todo.tags, ["仕事"])
        XCTAssertEqual(store.todos.first, todo)
    }

    func testAddMovesMultipleTagsWithFullWidthMark() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "買い物 ＃牛乳 #急ぎ"))

        XCTAssertEqual(todo.title, "買い物")
        XCTAssertEqual(todo.tags, ["牛乳", "急ぎ"])
    }

    func testAddMovesTagOnSecondLine() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "企画書\n#仕事"))

        XCTAssertEqual(todo.title, "企画書")
        XCTAssertEqual(todo.tags, ["仕事"])
    }

    func testAddKeepsHashInsideWordAsTitle() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "C# を勉強"))

        XCTAssertEqual(todo.title, "C# を勉強")
        XCTAssertTrue(todo.tags.isEmpty)
    }

    func testAddTagOnlyInputReturnsNilAndAddsNothing() throws {
        let store = try makeStore([])

        XCTAssertNil(store.add(title: "#仕事"))
        XCTAssertTrue(store.todos.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - 追加・書き方をそろえる（Issue のケース）

    func testAddAlignsSpellingWithTagInInbox() throws {
        let store = try makeStore([Todo(title: "a", tags: ["Work"])])

        let todo = try XCTUnwrap(store.add(title: "x #work"))

        XCTAssertEqual(todo.tags, ["Work"])
    }

    func testAddAlignsSpellingWithTagOnlyInArchive() throws {
        let archived = Todo(title: "a", tags: ["Work"], completedAt: Date(timeIntervalSince1970: 1000))
        let store = try makeStore([archived])

        let todo = try XCTUnwrap(store.add(title: "x #work"))

        XCTAssertEqual(todo.tags, ["Work"])
    }

    func testAddAlignsToEarlierTodoWhenSpellingsDiffer() throws {
        let store = try makeStore([
            Todo(title: "a", tags: ["Work"]),
            Todo(title: "b", tags: ["work"]),
        ])

        let todo = try XCTUnwrap(store.add(title: "x #WORK"))

        XCTAssertEqual(todo.tags, ["Work"])
    }

    func testAddDropsDuplicateWithinOneInputKeepingFirstSpelling() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "x #Work #work"))

        XCTAssertEqual(todo.tags, ["Work"])
    }

    // MARK: - 追加・書き方をそろえる（境目）

    func testAddKeepsOwnSpellingWhenNoTodoHasTheTag() throws {
        let store = try makeStore([Todo(title: "a", tags: ["Home"])])

        let todo = try XCTUnwrap(store.add(title: "x #Work"))

        XCTAssertEqual(todo.tags, ["Work"])
    }

    func testAddTreatsFullWidthLettersAsDifferentTag() throws {
        let store = try makeStore([Todo(title: "a", tags: ["Ｗork"])])

        let todo = try XCTUnwrap(store.add(title: "x #work"))

        XCTAssertEqual(todo.tags, ["work"])
    }

    func testAddAlignsSpellingPerTag() throws {
        let store = try makeStore([
            Todo(title: "a", tags: ["Work"]),
            Todo(title: "b", tags: ["Home"]),
        ])

        let todo = try XCTUnwrap(store.add(title: "x #home #work #new"))

        XCTAssertEqual(todo.tags, ["Home", "Work", "new"])
    }

    func testAddAppliesTitleNormalizationBeforeParsingTags() throws {
        let store = try makeStore([])

        let todo = try XCTUnwrap(store.add(title: "  企画書\r\n\r\n資料 #仕事  \n"))

        XCTAssertEqual(todo.title, "企画書 資料")
        XCTAssertEqual(todo.tags, ["仕事"])
    }

    func testAddTagOnlyInputAfterWhitespaceReturnsNil() throws {
        let store = try makeStore([])

        XCTAssertNil(store.add(title: "  \n#仕事 #急ぎ  "))
        XCTAssertTrue(store.todos.isEmpty)
    }

    // MARK: - 追加の取り消し・やり直し（Issue のケース）

    func testUndoAddRemovesTodoAndRedoRestoresItWithTags() throws {
        let store = try makeStore([])
        let added = try XCTUnwrap(store.add(title: "企画書 #仕事"))

        store.undo()
        XCTAssertTrue(store.todos.isEmpty)

        store.redo()
        XCTAssertEqual(store.todos.first?.id, added.id)
        XCTAssertEqual(store.todos.first?.title, "企画書")
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
    }

    func testAddWithTagsIsSingleUndoStepNamedAdd() throws {
        let store = try makeStore([])
        store.add(title: "企画書 #仕事 #急ぎ")

        XCTAssertEqual(store.undoActionName, "追加")
        store.undo()

        XCTAssertTrue(store.todos.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - 確定（Issue のケース）

    func testCommitTitleMovesTagIntoTagsAndKeepsTitle() throws {
        let todo = Todo(title: "企画書")
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "企画書 #仕事")

        XCTAssertEqual(store.todos.first?.title, "企画書")
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
        XCTAssertEqual(shown, "企画書")
    }

    func testUndoCommitTitleRestoresEmptyTagsAndRedoAppliesAgain() throws {
        let todo = Todo(title: "企画書")
        let store = try makeStore([todo])
        store.commitTitle(id: todo.id, text: "企画書 #仕事")

        XCTAssertEqual(store.undoActionName, "タイトルの編集")
        store.undo()
        XCTAssertEqual(store.todos.first?.tags, [])

        store.redo()
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
    }

    func testCommitTitleAppendsToExistingTags() throws {
        let todo = Todo(title: "企画書", tags: ["仕事"])
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "企画書 #急ぎ")

        XCTAssertEqual(store.todos.first?.tags, ["仕事", "急ぎ"])
    }

    func testCommitTitleWithSameTitleAndSameTagChangesNothing() throws {
        // 保存・読み込みで createdAt がミリ秒に丸められるので、丸めても変わらない日時にする
        let todo = Todo(title: "企画書", tags: ["仕事"], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "企画書 #仕事")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "企画書")
    }

    func testCommitTitleWithTagOfDifferentCaseChangesNothing() throws {
        let todo = Todo(title: "x", tags: ["Work"])
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "x #WORK")

        XCTAssertEqual(store.todos.first?.tags, ["Work"])
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "x")
    }

    func testCommitTagOnlyTitleDoesNotCommit() throws {
        // 保存・読み込みで createdAt がミリ秒に丸められるので、丸めても変わらない日時にする
        let todo = Todo(title: "企画書", tags: ["仕事"], createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "#急ぎ")

        XCTAssertEqual(store.todos.first, todo)
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "企画書")
    }

    // MARK: - 確定（境目）

    func testCommitTitleChangesTitleAndAddsTagInOneUndoStep() throws {
        let todo = Todo(title: "企画書")
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "提案書 #仕事")

        XCTAssertEqual(store.todos.first?.title, "提案書")
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
        XCTAssertEqual(shown, "提案書")

        store.undo()
        XCTAssertEqual(store.todos.first?.title, "企画書")
        XCTAssertEqual(store.todos.first?.tags, [])
        XCTAssertFalse(store.canUndo)
    }

    func testCommitTitleChangesOnlyTitleKeepsTags() throws {
        let todo = Todo(title: "企画書", tags: ["仕事"])
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "提案書")

        XCTAssertEqual(store.todos.first?.title, "提案書")
        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
        XCTAssertEqual(shown, "提案書")
    }

    func testCommitTitleWithoutTagKeepsExistingTagsWhenTitleUnchanged() throws {
        let todo = Todo(title: "企画書", tags: ["仕事"])
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "企画書")

        XCTAssertEqual(store.todos.first?.tags, ["仕事"])
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(shown, "企画書")
    }

    func testCommitTitleAlignsSpellingWithOtherTodo() throws {
        let other = Todo(title: "a", tags: ["Work"])
        let todo = Todo(title: "x")
        let store = try makeStore([other, todo])

        store.commitTitle(id: todo.id, text: "x #work")

        XCTAssertEqual(store.todos.last?.tags, ["Work"])
    }

    func testCommitTitleAlignsSpellingWithArchivedTodo() throws {
        let archived = Todo(title: "a", tags: ["Work"], completedAt: Date(timeIntervalSince1970: 1000))
        let todo = Todo(title: "x")
        let store = try makeStore([archived, todo])

        store.commitTitle(id: todo.id, text: "x #work")

        XCTAssertEqual(store.todos.last?.tags, ["Work"])
    }

    func testCommitTitleDropsDuplicateWithinOneInput() throws {
        let todo = Todo(title: "x")
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "x #Work #work")

        XCTAssertEqual(store.todos.first?.tags, ["Work"])
    }

    func testCommitTitleKeepsHashInsideWordAndAddsNoTag() throws {
        let todo = Todo(title: "x")
        let store = try makeStore([todo])

        let shown = store.commitTitle(id: todo.id, text: "C# を勉強")

        XCTAssertEqual(store.todos.first?.title, "C# を勉強")
        XCTAssertTrue(store.todos.first?.tags.isEmpty ?? false)
        XCTAssertEqual(shown, "C# を勉強")
    }

    func testCommitTagOnlyTitleOnTodoWithoutTagsAddsNoTag() throws {
        let todo = Todo(title: "企画書")
        let store = try makeStore([todo])

        store.commitTitle(id: todo.id, text: "  #急ぎ  ")

        XCTAssertEqual(store.todos.first?.tags, [])
    }

    // MARK: - ヘルパー

    private func makeStore(_ todos: [Todo]) throws -> TodoStore {
        try Persistence.encode(todos).write(to: directory.appendingPathComponent("todos.json"))
        return TodoStore(persistence: Persistence(directory: directory, saveDelay: 0.05))
    }
}
