import XCTest

@testable import LocalTodo

/// 詳細ペインの編集に使う `TodoStore` の操作（タイトルの確定と、ディスクリプションの更新）のテスト。
@MainActor
final class TodoDetailEditingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoDetailEditingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - タイトルの確定（Issue のケース）

    func testCommitTitleChangesTitleAndReturnsIt() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        let shown = store.commitTitle(id: todo.id, text: "豆乳を買う")

        XCTAssertEqual(store.todos.first?.title, "豆乳を買う")
        XCTAssertEqual(shown, "豆乳を買う")
    }

    func testCommitTitleTrimsSurroundingSpacesAndNewline() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        let shown = store.commitTitle(id: todo.id, text: "  豆乳を買う\n")

        XCTAssertEqual(store.todos.first?.title, "豆乳を買う")
        XCTAssertEqual(shown, "豆乳を買う")
    }

    func testCommitTitleJoinsInnerNewlinesIntoOneSpace() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        let shown = store.commitTitle(id: todo.id, text: "豆乳を\n\n買う")

        XCTAssertEqual(store.todos.first?.title, "豆乳を 買う")
        XCTAssertEqual(shown, "豆乳を 買う")
    }

    func testCommitEmptyTitleKeepsOriginalAndReturnsIt() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        let shown = store.commitTitle(id: todo.id, text: "")

        XCTAssertEqual(store.todos.first?.title, "牛乳を買う")
        XCTAssertEqual(shown, "牛乳を買う")
    }

    func testCommitWhitespaceOnlyTitleKeepsOriginalAndReturnsIt() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        let shown = store.commitTitle(id: todo.id, text: " \n \n")

        XCTAssertEqual(store.todos.first?.title, "牛乳を買う")
        XCTAssertEqual(shown, "牛乳を買う")
    }

    func testCommitSameTitleDoesNotReplaceTodos() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        let before = store.todos

        let shown = store.commitTitle(id: todo.id, text: "牛乳を買う")

        XCTAssertEqual(store.todos, before)
        XCTAssertEqual(shown, "牛乳を買う")
    }

    func testCommitSameTitleDoesNotScheduleSave() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        waitForScheduledSave()
        try FileManager.default.removeItem(at: fileURL)

        _ = store.commitTitle(id: todo.id, text: "牛乳を買う")

        // 保存が予約されていれば、待つ間にファイルが書き直される
        waitForScheduledSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCommitSameTitleWithSurroundingSpacesDoesNotScheduleSave() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        waitForScheduledSave()
        try FileManager.default.removeItem(at: fileURL)

        let shown = store.commitTitle(id: todo.id, text: " 牛乳を買う ")

        waitForScheduledSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(shown, "牛乳を買う")
    }

    func testCommitEmptyTitleDoesNotScheduleSave() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        waitForScheduledSave()
        try FileManager.default.removeItem(at: fileURL)

        _ = store.commitTitle(id: todo.id, text: "  ")

        waitForScheduledSave()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCommitChangedTitleIsSaved() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        waitForScheduledSave()

        _ = store.commitTitle(id: todo.id, text: "豆乳を買う")

        waitForScheduledSave()
        XCTAssertEqual(try titlesInFile(), ["豆乳を買う"])
    }

    func testCommitTitleOfOneTodoLeavesTheOtherAlone() throws {
        // A を編集中に B を選んだとき、A の ID を渡して確定する
        let store = makeStore()
        let todoA = try XCTUnwrap(store.add(title: "A の元タイトル"))
        let todoB = try XCTUnwrap(store.add(title: "B の元タイトル"))

        _ = store.commitTitle(id: todoA.id, text: "A の新タイトル")

        XCTAssertEqual(store.todos.first { $0.id == todoA.id }?.title, "A の新タイトル")
        XCTAssertEqual(store.todos.first { $0.id == todoB.id }?.title, "B の元タイトル")
    }

    func testCommitTitleOfArchivedTodoKeepsCompletedAtAndArchive() throws {
        let completedAt = try date(2026, 11, 24, 18, 0, 0)
        let archived = Todo(
            title: "済んだ Todo", createdAt: try date(2026, 11, 24, 10, 0, 0), completedAt: completedAt)
        try writeFile([archived])
        let store = makeStore()

        let shown = store.commitTitle(id: archived.id, text: "済んだ Todo（直した）")

        XCTAssertEqual(shown, "済んだ Todo（直した）")
        XCTAssertEqual(store.archivedTodos.map(\.title), ["済んだ Todo（直した）"])
        XCTAssertEqual(store.archivedTodos.first?.completedAt, completedAt)
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testCommitTitleWithUnknownIDChangesNothing() throws {
        let store = makeStore()
        _ = try XCTUnwrap(store.add(title: "牛乳を買う"))
        let before = store.todos

        _ = store.commitTitle(id: UUID(), text: "豆乳を買う")

        XCTAssertEqual(store.todos, before)
    }

    // MARK: - タイトルの確定（自分で足したケース）

    func testCommitTitleKeepsOtherFieldsOfTodo() throws {
        let original = Todo(
            title: "牛乳を買う", descriptionText: "2本", tags: ["買い物"],
            createdAt: try date(2026, 11, 24, 10, 0, 0))
        try writeFile([original])
        let store = makeStore()

        _ = store.commitTitle(id: original.id, text: "豆乳を買う")

        var expected = original
        expected.title = "豆乳を買う"
        XCTAssertEqual(store.todos, [expected])
    }

    func testCommitTitleTreatsCRLFAsOneSpace() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        _ = store.commitTitle(id: todo.id, text: "豆乳を\r\n買う")

        XCTAssertEqual(store.todos.first?.title, "豆乳を 買う")
    }

    func testCommitTitleTrimsFullWidthSpaces() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        _ = store.commitTitle(id: todo.id, text: "\u{3000}豆乳を買う\u{3000}")

        XCTAssertEqual(store.todos.first?.title, "豆乳を買う")
    }

    func testCommitTitleKeepsSpacesInsideTitle() throws {
        let store = makeStore()
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        _ = store.commitTitle(id: todo.id, text: "豆乳を  買う")

        XCTAssertEqual(store.todos.first?.title, "豆乳を  買う")
    }

    func testCommitTitleWithUnknownIDReturnsTrimmedText() {
        // 存在しない ID のときの戻り値は決めごとにない。欄に出す文字列として整えた文字列を返すと解釈する
        let store = makeStore()

        let shown = store.commitTitle(id: UUID(), text: " 豆乳を買う ")

        XCTAssertEqual(shown, "豆乳を買う")
    }

    func testCommitTitleNormalizesSameAsAdd() throws {
        // add(title:) と同じ整え方になること
        let store = makeStore()
        let added = try XCTUnwrap(store.add(title: "\n 豆乳を\n\n買う \r\n"))
        let todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        _ = store.commitTitle(id: todo.id, text: "\n 豆乳を\n\n買う \r\n")

        XCTAssertEqual(store.todos.first { $0.id == todo.id }?.title, added.title)
    }

    // MARK: - ディスクリプション

    func testUpdateKeepsDescriptionTextAsIs() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        todo.descriptionText = "1行目\n\n  3行目  "
        store.update(todo)

        XCTAssertEqual(store.todos.first?.descriptionText, "1行目\n\n  3行目  ")
    }

    func testUpdateKeepsOnlyWhitespaceDescription() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "牛乳を買う"))

        todo.descriptionText = " \n "
        store.update(todo)

        XCTAssertEqual(store.todos.first?.descriptionText, " \n ")
    }

    func testUpdateCanClearDescription() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        todo.descriptionText = "メモ"
        store.update(todo)

        todo.descriptionText = ""
        store.update(todo)

        XCTAssertEqual(store.todos.first?.descriptionText, "")
    }

    func testUpdateDescriptionOfArchivedTodoKeepsCompletedAt() throws {
        let completedAt = try date(2026, 11, 24, 18, 0, 0)
        var archived = Todo(
            title: "済んだ Todo", createdAt: try date(2026, 11, 24, 10, 0, 0), completedAt: completedAt)
        try writeFile([archived])
        let store = makeStore()

        archived.descriptionText = "あとから足した説明"
        store.update(archived)

        XCTAssertEqual(store.archivedTodos.first?.descriptionText, "あとから足した説明")
        XCTAssertEqual(store.archivedTodos.first?.completedAt, completedAt)
    }

    func testUpdatedDescriptionIsSavedWithLineBreaks() throws {
        let store = makeStore()
        var todo = try XCTUnwrap(store.add(title: "牛乳を買う"))
        waitForScheduledSave()

        todo.descriptionText = "1行目\n\n  3行目  "
        store.update(todo)

        waitForScheduledSave()
        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.descriptionText, "1行目\n\n  3行目  ")
    }

    // MARK: - ヘルパー

    private var fileURL: URL { directory.appendingPathComponent("todos.json") }

    private nonisolated static let saveDelay: TimeInterval = 0.05

    private func makeStore() -> TodoStore {
        TodoStore(persistence: Persistence(directory: directory, saveDelay: Self.saveDelay))
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
