import XCTest

@testable import LocalTodo

/// 詳細ペインでの期限日の操作（日を選ぶ・時刻トグル・時刻フィールド・×）と、その取り消しのテスト。
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

    func testSelectingDayWithoutDueDateSetsDateOnly() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 30)))
    }

    func testSelectingDayOnDateOnlyKeepsDateOnly() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 30)))
    }

    func testSelectingDayOnDateTimeKeepsTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 15, 0)))
    }

    // MARK: - 日を選ぶ（境目）

    func testSelectingDayOnDateTimeKeepsMinutes() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 5)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 9, 5)))
    }

    func testSelectingDayOnDateTimeAcrossMonthKeepsTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 12, 1))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 12, 1, 15, 0)))
    }

    func testSelectingDayOnDateTimeAcrossYearKeepsTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2027, 1, 5))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2027, 1, 5, 15, 0)))
    }

    func testSelectingEarlierDayOnDateTimeKeepsTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 20))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 20, 15, 0)))
    }

    func testSelectingDayOnLateNightDateTimeUsesCalendarTimeZone() throws {
        // 東京の 23:30 は UTC では同じ日の 14:30。東京の暦で日だけを変え、時刻は 23:30 のまま
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 23, 30)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 23, 30)))
    }

    func testSelectingDayOnEarlyMorningDateTimeUsesCalendarTimeZone() throws {
        // 東京の 0:30 は UTC では前の日。東京の暦で日だけを変える
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 0, 30)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 0, 30)))
    }

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
        let b = Todo(title: "B", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a, b])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertEqual(dueDate(store, b.id), .date(try day(2026, 11, 24)))
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

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 30)))
        XCTAssertEqual(store.todos.first?.completedAt, a.completedAt)
    }

    func testSelectedDayIsSavedToFile() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.dueDate, .date(try day(2026, 11, 30)))
    }

    // MARK: - 時刻トグル（Issue のケース）

    func testTurningTimeOnSetsNineOClock() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: true)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    func testTurningTimeOffKeepsDayAsDateOnly() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: false)

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
    }

    func testTurningTimeOnAgainAfterOffSetsNineOClockNotPreviousTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: false)
        store.setDueTimeEnabled(id: a.id, enabled: true)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    // MARK: - 時刻トグル（境目）

    func testTurningTimeOnUsesNineOClockInCalendarTimeZone() throws {
        // 9:00 は東京の 9:00（UTC の 0:00）。年をまたぐ日でも同じ日の 9:00
        let a = Todo(title: "A", dueDate: .date(try day(2027, 1, 1)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: true)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2027, 1, 1, 9, 0)))
    }

    func testTurningTimeOffOnLateNightDateTimeKeepsCalendarDay() throws {
        // 東京の 11/24 0:30 は UTC では 11/23。東京の暦の 11/24 にする
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 0, 30)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: false)

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
    }

    func testTurningTimeOnAfterSelectingNewDayUsesNewDay() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.setDueTimeEnabled(id: a.id, enabled: true)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 9, 0)))
    }

    // MARK: - × で外す（Issue のケース）

    func testRemovingDueDateClearsIt() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)

        XCTAssertNil(dueDate(store, a.id))
    }

    // MARK: - × で外す（境目）

    func testRemovingDateTimeDueDateClearsIt() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)

        XCTAssertNil(dueDate(store, a.id))
    }

    func testRemovedDueDateIsSavedToFile() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)), createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertNil(saved.first?.dueDate)
    }

    // MARK: - 時刻フィールド（境目）

    func testUpdatingTimeChangesTimeOnSameDay() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])

        store.updateDueTime(id: a.id, hour: 15, minute: 30)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 15, 30)))
    }

    func testUpdatingTimeToMidnightStaysOnSameDay() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])

        store.updateDueTime(id: a.id, hour: 0, minute: 0)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 0, 0)))
    }

    func testUpdatingTimeToLastMinuteStaysOnSameDay() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])

        store.updateDueTime(id: a.id, hour: 23, minute: 59)

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 23, 59)))
    }

    // MARK: - 取り消し：日を選ぶ・時刻トグル・×（Issue のケース）

    func testSelectingDayRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])

        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoSelectingDayRestoresPreviousDueDate() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoSelectingDayRestoresSelectedDueDate() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 30)))
    }

    func testTurningTimeOnRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: true)

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoTurningTimeOnRestoresDateOnly() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: true)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoTurningTimeOnRestoresNineOClock() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: true)

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    func testTurningTimeOffRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.setDueTimeEnabled(id: a.id, enabled: false)

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoTurningTimeOffRestoresPreviousTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: false)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 15, 0)))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoTurningTimeOffRestoresDateOnly() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: false)

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
    }

    func testRemovingDueDateRegistersUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])

        store.removeDueDate(id: a.id)

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoRemovingDueDateRestoresPreviousDueDate() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 15, 0)))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoRemovingDueDateClearsItAgain() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()
        store.redo()

        XCTAssertNil(dueDate(store, a.id))
    }

    // MARK: - 取り消し：日を選ぶ・時刻トグル・×（境目）

    func testUndoSelectingFirstDayRestoresNoDueDate() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))

        store.undo()

        XCTAssertNil(dueDate(store, a.id))
    }

    func testRedoNameIsDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
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
        store.setDueTimeEnabled(id: a.id, enabled: true)
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.removeDueDate(id: a.id)

        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 30, 9, 0)))
        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        store.undo()
        XCTAssertNil(dueDate(store, a.id))
        XCTAssertFalse(store.canUndo)
    }

    func testUndoTimeToggleOffThenOnRestoresOriginalTimeInTwoSteps() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 15, 0)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: false)
        store.setDueTimeEnabled(id: a.id, enabled: true)

        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 15, 0)))
    }

    func testUndoDueDateEditKeepsTitleEditedAfterwards() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        store.commitTitle(id: a.id, text: "B")

        store.undo()  // タイトルの編集
        store.undo()  // 期限日の編集

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        XCTAssertEqual(store.todos.first?.title, "A")
    }

    func testUndoDueDateEditDoesNotRevertDescriptionTypedAfterwards() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueDay(id: a.id, day: try day(2026, 11, 30))
        var typed = try XCTUnwrap(store.todos.first)
        typed.descriptionText = "あとから打った説明"
        store.update(typed, registersUndo: false)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        XCTAssertEqual(store.todos.first?.descriptionText, "あとから打った説明")
    }

    func testUndoDueDateEditIsSavedToFile() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)), createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])
        store.removeDueDate(id: a.id)

        store.undo()
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.dueDate, .date(try day(2026, 11, 24)))
    }

    // MARK: - 取り消し：時刻フィールド（Issue のケース）

    func testUpdatingTimeBeforeCommitChangesDueDateWithoutUndo() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])

        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 10, 0)))
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 11, 0)))

        XCTAssertFalse(store.canUndo)
    }

    func testCommittingTimeRegistersOneUndoNamedDueDateEdit() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.commitDueTime(id: a.id)

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoCommittedTimeRestoresTimeBeforeEditing() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        store.commitDueTime(id: a.id)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
        XCTAssertFalse(store.canUndo)
    }

    func testRedoCommittedTimeRestoresLastTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        store.commitDueTime(id: a.id)

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 11, 0)))
    }

    func testCommittingTimeChangedBackToOriginalRegistersNothing() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        store.updateDueTime(id: a.id, hour: 9, minute: 0)

        store.commitDueTime(id: a.id)

        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    func testUndoBeforeCommitCommitsTimeThenUndoesIt() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    func testRedoAfterUndoBeforeCommitRestoresLastTime() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.undo()
        store.redo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 11, 0)))
    }

    // MARK: - 取り消し：時刻フィールド（境目）

    func testCommittingTimeWithoutChangesRegistersNothing() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])

        store.commitDueTime(id: a.id)

        XCTAssertFalse(store.canUndo)
    }

    func testUpdatingTimeToSameValueThenCommittingRegistersNothing() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 9, minute: 0)

        store.commitDueTime(id: a.id)

        XCTAssertFalse(store.canUndo)
    }

    func testCommittingTimeTwiceRegistersOnlyOnce() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        store.commitDueTime(id: a.id)

        store.commitDueTime(id: a.id)
        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
        XCTAssertFalse(store.canUndo)
    }

    func testChangingOnlyMinuteThenCommittingRegistersUndo() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 9, minute: 1)

        store.commitDueTime(id: a.id)
        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
    }

    func testTwoCommittedTimeEditsAreTwoUndos() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 10, minute: 0)
        store.commitDueTime(id: a.id)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        store.commitDueTime(id: a.id)

        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 10, 0)))
        store.undo()
        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
        XCTAssertFalse(store.canUndo)
    }

    func testUndoBeforeCommitUndoesOnlyTimeEditNotEarlierOperation() throws {
        // 時刻トグルで 9:00 にしてから時刻を変え、確定前に取り消すと、時刻の変更だけが戻る
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: true)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .dateTime(try date(2026, 11, 24, 9, 0)))
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "期限日の編集")
    }

    func testUndoAfterCommitThenUndoAgainUndoesEarlierOperation() throws {
        let a = Todo(title: "A", dueDate: .date(try day(2026, 11, 24)))
        let store = try makeStore([a])
        store.setDueTimeEnabled(id: a.id, enabled: true)
        store.updateDueTime(id: a.id, hour: 11, minute: 0)
        store.commitDueTime(id: a.id)

        store.undo()
        store.undo()

        XCTAssertEqual(dueDate(store, a.id), .date(try day(2026, 11, 24)))
        XCTAssertFalse(store.canUndo)
    }

    func testCommittingTimeForOneTodoDoesNotAffectAnother() throws {
        let a = Todo(title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)))
        let b = Todo(title: "B", dueDate: .dateTime(try date(2026, 11, 25, 9, 0)))
        let store = try makeStore([a, b])
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.commitDueTime(id: a.id)

        XCTAssertEqual(dueDate(store, b.id), .dateTime(try date(2026, 11, 25, 9, 0)))
    }

    func testCommittedTimeIsSavedToFile() throws {
        let a = Todo(
            title: "A", dueDate: .dateTime(try date(2026, 11, 24, 9, 0)), createdAt: try date(2026, 11, 25, 9, 0))
        let store = try makeStore([a])
        store.updateDueTime(id: a.id, hour: 11, minute: 0)

        store.commitDueTime(id: a.id)
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.dueDate, .dateTime(try date(2026, 11, 24, 11, 0)))
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

    private func dueDate(_ store: TodoStore, _ id: Todo.ID) -> DueDate? {
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
