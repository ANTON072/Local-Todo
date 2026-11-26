import XCTest

@testable import LocalTodo

/// サイドバーで選ぶ Inbox／アーカイブが、一覧に出す Todo と入力欄の有無に正しく答えるか。
@MainActor
final class TodoListKindTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoListKindTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 並び

    func testSidebarListsInboxThenArchive() {
        XCTAssertEqual(TodoListKind.allCases, [.inbox, .archive])
    }

    // MARK: - Inbox の一覧

    func testInboxExcludesArchivedTodos() throws {
        try writeFile([
            Todo(title: "Inbox", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 10, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0)),
        ])

        let todos = TodoListKind.inbox.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["Inbox"])
    }

    func testInboxIsSortedByNewestCreatedAt() throws {
        // ファイルの順と作成日時の順を入れ替えておく
        try writeFile([
            Todo(title: "古い", createdAt: try date(2026, 11, 23, 9, 0, 0)),
            Todo(title: "新しい", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(title: "いちばん古い", createdAt: try date(2026, 11, 22, 9, 0, 0)),
        ])

        let todos = TodoListKind.inbox.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["新しい", "古い", "いちばん古い"])
    }

    func testInboxShowsInboxTodosNewestFirstWithoutArchivedOnes() throws {
        // アーカイブの Todo を、作成日時が Inbox の Todo の間に入るように混ぜる
        try writeFile([
            Todo(title: "古い", createdAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 23, 9, 0, 0),
                completedAt: try date(2026, 11, 25, 9, 0, 0)),
            Todo(title: "新しい", createdAt: try date(2026, 11, 24, 9, 0, 0)),
        ])

        let todos = TodoListKind.inbox.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["新しい", "古い"])
    }

    func testInboxMatchesStoreInboxTodos() throws {
        try writeFile([
            Todo(title: "Inbox 1", createdAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 23, 9, 0, 0),
                completedAt: try date(2026, 11, 25, 9, 0, 0)),
            Todo(title: "Inbox 2", createdAt: try date(2026, 11, 24, 9, 0, 0)),
        ])
        let store = makeStore()

        XCTAssertEqual(TodoListKind.inbox.todos(in: store), store.inboxTodos)
    }

    func testInboxIsEmptyWhenAllTodosAreArchived() throws {
        try writeFile([
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 23, 9, 0, 0),
                completedAt: try date(2026, 11, 25, 9, 0, 0))
        ])

        XCTAssertTrue(TodoListKind.inbox.todos(in: makeStore()).isEmpty)
    }

    func testInboxIsEmptyWhenStoreIsEmpty() {
        XCTAssertTrue(TodoListKind.inbox.todos(in: makeStore()).isEmpty)
    }

    func testInboxReflectsAddedTodo() throws {
        let store = makeStore()

        store.add(title: "買い物")

        XCTAssertEqual(TodoListKind.inbox.todos(in: store).map(\.title), ["買い物"])
    }

    // MARK: - アーカイブの一覧

    func testArchiveExcludesInboxTodos() throws {
        try writeFile([
            Todo(title: "Inbox", createdAt: try date(2026, 11, 24, 9, 0, 0)),
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 10, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0)),
        ])

        let todos = TodoListKind.archive.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["アーカイブ"])
    }

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

        let todos = TodoListKind.archive.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["あとで完了", "先に完了", "いちばん先に完了"])
    }

    func testArchiveShowsArchivedTodosNewestCompletedFirstWithoutInboxOnes() throws {
        try writeFile([
            Todo(
                title: "先に完了", createdAt: try date(2026, 11, 21, 9, 0, 0),
                completedAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(title: "Inbox", createdAt: try date(2026, 11, 25, 9, 0, 0)),
            Todo(
                title: "あとで完了", createdAt: try date(2026, 11, 20, 9, 0, 0),
                completedAt: try date(2026, 11, 23, 9, 0, 0)),
        ])

        let todos = TodoListKind.archive.todos(in: makeStore())

        XCTAssertEqual(todos.map(\.title), ["あとで完了", "先に完了"])
    }

    func testArchiveMatchesStoreArchivedTodos() throws {
        try writeFile([
            Todo(
                title: "アーカイブ 1", createdAt: try date(2026, 11, 21, 9, 0, 0),
                completedAt: try date(2026, 11, 22, 9, 0, 0)),
            Todo(title: "Inbox", createdAt: try date(2026, 11, 25, 9, 0, 0)),
            Todo(
                title: "アーカイブ 2", createdAt: try date(2026, 11, 20, 9, 0, 0),
                completedAt: try date(2026, 11, 23, 9, 0, 0)),
        ])
        let store = makeStore()

        XCTAssertEqual(TodoListKind.archive.todos(in: store), store.archivedTodos)
    }

    func testArchiveIsEmptyWhenNoTodoIsArchived() throws {
        try writeFile([Todo(title: "Inbox", createdAt: try date(2026, 11, 25, 9, 0, 0))])

        XCTAssertTrue(TodoListKind.archive.todos(in: makeStore()).isEmpty)
    }

    func testArchiveIsEmptyWhenStoreIsEmpty() {
        XCTAssertTrue(TodoListKind.archive.todos(in: makeStore()).isEmpty)
    }

    func testArchiveDoesNotShowAddedTodo() throws {
        let store = makeStore()

        store.add(title: "買い物")

        XCTAssertTrue(TodoListKind.archive.todos(in: store).isEmpty)
    }

    // MARK: - 入力欄

    func testInboxShowsNewTodoField() {
        XCTAssertTrue(TodoListKind.inbox.showsNewTodoField)
    }

    func testArchiveHidesNewTodoField() {
        XCTAssertFalse(TodoListKind.archive.showsNewTodoField)
    }

    // MARK: - ヘルパー

    private var fileURL: URL { directory.appendingPathComponent("todos.json") }

    private func makeStore() -> TodoStore {
        TodoStore(persistence: Persistence(directory: directory, saveDelay: 10))
    }

    private func writeFile(_ todos: [Todo]) throws {
        try Persistence.encode(todos).write(to: fileURL)
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
