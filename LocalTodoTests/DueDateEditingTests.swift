import XCTest

@testable import LocalTodo

/// 詳細ペインでの期限日の操作（日を選ぶ・×）と、その取り消しのテスト。
/// カレンダーはグレゴリオ暦・Asia/Tokyo に固定し、今を 2026/11/26 10:00 とする。
@MainActor
final class DueDateEditingTests: XCTestCase {
    private var directory: URL!
    private var tokyo: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DueDateEditingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        tokyo = calendar
        now = try date(2026, 11, 26, 10, 0)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 日を選ぶ（Issue のケース）

    func testSelectingDayWithoutDueDateSetsIt() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 30))
    }

    func testSelectingDayReplacesDueDate() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 30))
    }

    // MARK: - 日を選ぶ（境目）

    func testSelectingDayDoesNotChangeOtherFields() throws {
        let a = Todo(title: "A", descriptionText: "説明", tags: ["仕事"], createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        let updated = try XCTUnwrap(store.todos.first)
        XCTAssertEqual(updated.title, "A")
        XCTAssertEqual(updated.descriptionText, "説明")
        XCTAssertEqual(updated.tags, ["仕事"])
        XCTAssertEqual(updated.createdAt, a.createdAt)
    }

    func testSelectingDayChangesOnlyThatTodo() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a, b])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, b.id), try day(2026, 11, 24))
    }

    func testSelectingDayForUnknownIDChangesNothing() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.setDueDay(id: UUID(), day: try day(2026, 11, 30))

        XCTAssertEqual(store.todos, [a])
        XCTAssertFalse(store.canUndo)
    }

    func testSelectingDayOnArchivedTodoKeepsItArchived() throws {
        let a = Todo(title: "A", completedAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 30))
        XCTAssertEqual(store.todos.first?.completedAt, a.completedAt)
    }

    func testSelectedDayIsSavedToFile() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.dueDate, try day(2026, 11, 30))
    }

    // MARK: - × で外す（Issue のケース）

    func testRemovingDueDateClearsIt() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)

        XCTAssertNil(dueDate(store, a.id))
    }

    // MARK: - × で外す（境目）

    func testRemovedDueDateIsSavedToFile() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24), createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertNil(saved.first?.dueDate)
    }

    // MARK: - 取り消し：日を選ぶ・×（Issue のケース）

    func testSelectingDayRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoSelectingDayRestoresPreviousDueDate() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoSelectingDayRestoresSelectedDueDate() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 30))
    }

    func testRemovingDueDateRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoRemovingDueDateRestoresPreviousDueDate() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoRemovingDueDateClearsItAgain() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()
        store.redo()

        XCTAssertNil(dueDate(store, a.id))
    }

    // MARK: - 取り消し：日を選ぶ・×（境目）

    func testSelectingSameDayRegistersNothing() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 24))

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        XCTAssertFalse(store.canUndo)
    }

    func testUndoSelectingFirstDayRestoresNoDueDate() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()

        XCTAssertNil(dueDate(store, a.id))
    }

    func testRedoNameIsDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()

        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(store.redoActionName, "期限日の編集")
    }

    func testEachDueDateOperationIsOneUndo() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 24))
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.removeDueDate(id: a.id)

        store.undo()
        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 30))
        store.undo()
        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        store.undo()
        XCTAssertNil(dueDate(store, a.id))
        XCTAssertFalse(store.canUndo)
    }

    func testUndoDueDateEditKeepsTitleEditedAfterwards() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.commitTitle(id: a.id, text: "B")

        store.undo()  // タイトルの編集
        store.undo()  // 期限日の編集

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        XCTAssertEqual(store.todos.first?.title, "A")
    }

    func testUndoDueDateEditDoesNotRevertDescriptionTypedAfterwards() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        var typed = try XCTUnwrap(store.todos.first)
        typed.descriptionText = "あとから打った説明"
        store.update(typed, registersUndo: false)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), try day(2026, 11, 24))
        XCTAssertEqual(store.todos.first?.descriptionText, "あとから打った説明")
    }

    func testUndoDueDateEditIsSavedToFile() throws {
        let a = Todo(title: "A", dueDate: try day(2026, 11, 24), createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.dueDate, try day(2026, 11, 24))
    }

    // MARK: - ヘルパー

    private var fileURL: URL {
        directory.appendingPathComponent("todos.json")
    }

    private func makeStore(_ todos: [Todo]) throws -> TodoStore {
        try Persistence.encode(todos).write(to: fileURL)
        return TodoStore(
            persistence: Persistence(directory: directory, saveDelay: 10),
            now: { [now] in now ?? .now },
            calendar: tokyo)
    }

    private func dueDate(_ store: TodoStore, _ id: Todo.ID) -> CalendarDay? {
        store.todos.first { $0.id == id }?.dueDate
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try XCTUnwrap(
            tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0)))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        CalendarDay(try date(year, month, day, 0, 0), calendar: tokyo)
    }
}
