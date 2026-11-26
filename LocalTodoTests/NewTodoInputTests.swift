import XCTest

@testable import LocalTodo

/// 入力欄で ⌘Enter を押したときに、Todo を追加し、入力欄に何を残すか。
@MainActor
final class NewTodoInputTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewTodoInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 追加できたとき

    func testSubmittingTitleAddsOneTodo() {
        let store = makeStore()

        _ = NewTodoInput.submit("買い物", to: store)

        XCTAssertEqual(store.inboxTodos.map(\.title), ["買い物"])
    }

    func testSubmittingTitleClearsField() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("買い物", to: store)

        XCTAssertEqual(remaining, "")
    }

    func testSubmittingAddsToExistingTodos() throws {
        try writeFile([Todo(title: "前回の分", createdAt: try date(2026, 11, 24, 9, 0, 0))])
        let store = makeStore()

        _ = NewTodoInput.submit("買い物", to: store)

        XCTAssertEqual(store.inboxTodos.count, 2)
    }

    func testSubmittingPutsTodoInInboxNotArchive() throws {
        try writeFile([
            Todo(
                title: "アーカイブ", createdAt: try date(2026, 11, 24, 9, 0, 0),
                completedAt: try date(2026, 11, 24, 18, 0, 0))
        ])
        let store = makeStore()

        _ = NewTodoInput.submit("買い物", to: store)

        XCTAssertEqual(store.inboxTodos.map(\.title), ["買い物"])
        XCTAssertEqual(store.archivedTodos.map(\.title), ["アーカイブ"])
    }

    func testSubmittingTitleWithSurroundingSpacesClearsField() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("  買い物  ", to: store)

        XCTAssertEqual(remaining, "")
        XCTAssertEqual(store.inboxTodos.map(\.title), ["買い物"])
    }

    func testSubmittingTitleWithInnerNewlineClearsField() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("牛乳\n卵", to: store)

        XCTAssertEqual(remaining, "")
        XCTAssertEqual(store.inboxTodos.map(\.title), ["牛乳 卵"])
    }

    func testSubmittingSingleCharacterClearsField() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("a", to: store)

        XCTAssertEqual(remaining, "")
        XCTAssertEqual(store.inboxTodos.count, 1)
    }

    func testSubmittingTwiceAddsTwoTodos() {
        let store = makeStore()

        _ = NewTodoInput.submit("買い物", to: store)
        _ = NewTodoInput.submit("買い物", to: store)

        XCTAssertEqual(store.inboxTodos.count, 2)
    }

    // MARK: - 追加できなかったとき

    func testSubmittingOnlySpacesAddsNothing() {
        let store = makeStore()

        _ = NewTodoInput.submit("\u{3000} ", to: store)

        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testSubmittingOnlySpacesKeepsTypedText() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("\u{3000} ", to: store)

        // 打った文字は、空白も含めてそのまま残す
        XCTAssertEqual(remaining, "\u{3000} ")
    }

    func testSubmittingEmptyTextAddsNothing() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("", to: store)

        XCTAssertEqual(remaining, "")
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testSubmittingOnlyNewlinesKeepsTypedText() {
        let store = makeStore()

        let remaining = NewTodoInput.submit("\n\r\n", to: store)

        XCTAssertEqual(remaining, "\n\r\n")
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testSubmittingOnlySpacesKeepsExistingTodos() throws {
        try writeFile([Todo(title: "前回の分", createdAt: try date(2026, 11, 24, 9, 0, 0))])
        let store = makeStore()

        _ = NewTodoInput.submit("\u{3000} ", to: store)

        XCTAssertEqual(store.inboxTodos.map(\.title), ["前回の分"])
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
