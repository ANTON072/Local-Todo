import XCTest

@testable import LocalTodo

/// 取り消し（⌘Z）とやり直しのテスト。1つの操作が1つの取り消しになることを確かめる。
/// 時間は偽のタイマーを進めて作る。
@MainActor
final class TodoStoreUndoTests: XCTestCase {
    private var directory: URL!
    private var timer: FakeGraceTimer!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoStoreUndoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        timer = FakeGraceTimer(start: try date(2026, 11, 26, 12, 0, 0))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 追加（Issue のケース）

    func testUndoAddRemovesTodoFromInbox() throws {
        let store = try makeStore([])

        store.add(title: "A")
        store.undo()

        XCTAssertTrue(store.inboxTodos.isEmpty)
        XCTAssertTrue(store.todos.isEmpty)
    }

    func testRedoAddRestoresSameIDAndCreatedAt() throws {
        let store = try makeStore([])
        let added = try XCTUnwrap(store.add(title: "A"))

        store.undo()
        store.redo()

        XCTAssertEqual(store.todos, [added])
        XCTAssertEqual(store.todos.first?.id, added.id)
        XCTAssertEqual(store.todos.first?.createdAt, added.createdAt)
    }

    func testAddUndoNameIsAdd() throws {
        let store = try makeStore([])

        store.add(title: "A")

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.undoActionName, "追加")
    }

    // MARK: - 追加（境目）

    func testAddingEmptyTitleRegistersNothing() throws {
        let store = try makeStore([])

        store.add(title: "  \n ")

        XCTAssertFalse(store.canUndo)
    }

    func testRedoAddKeepsOriginalPosition() throws {
        let x = Todo(title: "X")
        let store = try makeStore([x])
        let a = try XCTUnwrap(store.add(title: "A"))
        let b = try XCTUnwrap(store.add(title: "B"))

        store.undo()
        store.undo()
        store.redo()
        store.redo()

        XCTAssertEqual(store.todos.map(\.id), [x.id, a.id, b.id])
    }

    func testEachAddIsOneUndo() throws {
        let store = try makeStore([])
        store.add(title: "A")
        store.add(title: "B")

        store.undo()

        XCTAssertEqual(store.todos.map(\.title), ["A"])
    }

    // MARK: - 削除（Issue のケース）

    func testUndoDeleteRestoresTodoAtOriginalPositionAndInboxOrder() throws {
        // 作成日時が同じなので、並びは配列の順で決まる
        let created = try date(2026, 11, 25, 9, 0, 0)
        let a = Todo(title: "A", createdAt: created)
        let b = Todo(title: "B", createdAt: created)
        let c = Todo(title: "C", createdAt: created)
        let store = try makeStore([a, b, c])
        let inboxBefore = store.inboxTodos.map(\.id)

        store.delete(id: b.id)
        store.undo()

        XCTAssertEqual(store.todos.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(store.inboxTodos.map(\.id), inboxBefore)
    }

    func testRedoDeleteRemovesTodoAgain() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let c = Todo(title: "C")
        let store = try makeStore([a, b, c])

        store.delete(id: b.id)
        store.undo()
        store.redo()

        XCTAssertEqual(store.todos.map(\.id), [a.id, c.id])
    }

    func testUndoDeleteOfArchivedTodoKeepsCompletedAt() throws {
        let completed = try date(2026, 11, 25, 10, 0, 0)
        // 保存でミリ秒より細かい桁が落ちるので、読み戻した値と比べられるよう整数秒の作成日時にする
        let done = Todo(title: "済み", createdAt: try date(2026, 11, 24, 9, 0, 0), completedAt: completed)
        let store = try makeStore([done])

        store.delete(id: done.id)
        store.undo()

        XCTAssertEqual(store.todos, [done])
        XCTAssertEqual(store.archivedTodos.first?.completedAt, completed)
    }

    func testDeleteUndoNameIsDelete() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.delete(id: a.id)

        XCTAssertEqual(store.undoActionName, "削除")
    }

    // MARK: - 削除（境目）

    func testUndoDeleteOfFirstTodoRestoresFirstPosition() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.delete(id: a.id)
        store.undo()

        XCTAssertEqual(store.todos.map(\.id), [a.id, b.id])
    }

    func testUndoDeleteOfLastTodoRestoresLastPosition() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.delete(id: b.id)
        store.undo()

        XCTAssertEqual(store.todos.map(\.id), [a.id, b.id])
    }

    func testDeletingUnknownIDRegistersNothing() throws {
        let store = try makeStore([Todo(title: "A")])

        store.delete(id: UUID())

        XCTAssertFalse(store.canUndo)
    }

    func testDeletingTwoTodosTakesTwoUndos() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.delete(id: a.id)
        store.delete(id: b.id)
        store.undo()

        XCTAssertEqual(store.todos.map(\.id), [b.id])
    }

    // MARK: - タイトルの確定（Issue のケース）

    func testUndoCommitTitleRestoresPreviousTitle() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "豆乳を買う")
        store.undo()

        XCTAssertEqual(store.todos.first?.title, "牛乳を買う")
    }

    func testRedoCommitTitleAppliesNewTitle() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "豆乳を買う")
        store.undo()
        store.redo()

        XCTAssertEqual(store.todos.first?.title, "豆乳を買う")
    }

    func testCommitTitleWithSameTitleRegistersNothing() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "牛乳を買う")

        XCTAssertFalse(store.canUndo)
    }

    func testCommitTitleWithEmptyTextRegistersNothing() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "")

        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.todos.first?.title, "牛乳を買う")
    }

    func testCommitTitleUndoNameIsTitleEdit() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "豆乳を買う")

        XCTAssertEqual(store.undoActionName, "タイトルの編集")
    }

    // MARK: - タイトルの確定（境目）

    func testCommitTitleWithWhitespaceOnlyRegistersNothing() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: " \n ")

        XCTAssertFalse(store.canUndo)
    }

    func testCommitTitleThatNormalizesToSameTitleRegistersNothing() throws {
        let a = Todo(title: "牛乳を買う")
        let store = try makeStore([a])

        store.commitTitle(id: a.id, text: "  牛乳を買う \n")

        XCTAssertFalse(store.canUndo)
    }

    func testCommitTitleWithUnknownIDRegistersNothing() throws {
        let store = try makeStore([Todo(title: "A")])

        store.commitTitle(id: UUID(), text: "B")

        XCTAssertFalse(store.canUndo)
    }

    func testUndoCommitTitleKeepsOtherTodosTitles() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.commitTitle(id: a.id, text: "A 改")
        store.undo()

        XCTAssertEqual(store.todos.map(\.title), ["A", "B"])
    }

    // MARK: - update（Issue のケース）

    func testUndoUpdateRestoresDueDate() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        var edited = a
        edited.dueDate = .dateTime(try date(2026, 12, 1, 9, 0, 0))

        store.update(edited)
        XCTAssertEqual(store.todos.first?.dueDate, edited.dueDate)
        store.undo()

        XCTAssertNil(store.todos.first?.dueDate)
    }

    func testRedoUpdateAppliesDueDateAgain() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        var edited = a
        edited.dueDate = .dateTime(try date(2026, 12, 1, 9, 0, 0))

        store.update(edited)
        store.undo()
        store.redo()

        XCTAssertEqual(store.todos.first?.dueDate, edited.dueDate)
    }

    func testUpdateWithoutRegisteringUndoLeavesNoHistory() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        var edited = a
        edited.descriptionText = "あ"

        store.update(edited, registersUndo: false)

        XCTAssertEqual(store.todos.first?.descriptionText, "あ")
        XCTAssertFalse(store.canUndo)
    }

    func testUpdateRegistersUndoByDefault() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        var edited = a
        edited.tags = ["仕事"]

        store.update(edited)

        XCTAssertTrue(store.canUndo)
    }

    // MARK: - update（境目）

    func testUpdateWithUnknownIDRegistersNothing() throws {
        let store = try makeStore([Todo(title: "A")])

        store.update(Todo(title: "他"))

        XCTAssertFalse(store.canUndo)
    }

    func testUnregisteredUpdateKeepsEarlierHistoryIntact() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        var edited = a
        edited.title = "A 改"
        edited.descriptionText = "あ"

        store.commitTitle(id: a.id, text: "A 改")
        store.update(edited, registersUndo: false)
        store.undo()

        XCTAssertEqual(store.todos.first?.title, "A")
    }

    // MARK: - 完了（Issue のケース）

    func testUndoCommittedCompletionReturnsAllThreeToInboxImmediately() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let c = Todo(title: "C")
        let store = try makeStore([a, b, c])
        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: b.id)
        store.toggleCompletion(id: c.id)
        timer.advance(by: 3)
        XCTAssertTrue(store.inboxTodos.isEmpty)

        store.undo()

        // 猶予なし。時間を進めなくてもすぐ Inbox に戻る
        XCTAssertEqual(Set(store.inboxTodos.map(\.id)), [a.id, b.id, c.id])
        XCTAssertTrue(store.todos.allSatisfy { $0.completedAt == nil })
        XCTAssertTrue(store.archivedTodos.isEmpty)
        XCTAssertFalse(store.isShownCompleted(id: a.id))
        XCTAssertTrue(store.pendingToggles.isEmpty)
        XCTAssertEqual(timer.activeCount, 0)
    }

    func testRedoCompletionUsesCheckedTimes() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let c = Todo(title: "C")
        let store = try makeStore([a, b, c])
        store.toggleCompletion(id: a.id)
        let checkedA = timer.now
        timer.advance(by: 1)
        store.toggleCompletion(id: b.id)
        let checkedB = timer.now
        timer.advance(by: 1)
        store.toggleCompletion(id: c.id)
        let checkedC = timer.now
        timer.advance(by: 3)

        store.undo()
        // やり直しの時点の時刻が、チェックの時刻と違うようにしておく
        timer.advance(by: 100)
        store.redo()

        XCTAssertEqual(completedAt(store, a.id), checkedA)
        XCTAssertEqual(completedAt(store, b.id), checkedB)
        XCTAssertEqual(completedAt(store, c.id), checkedC)
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testCompletionOfThreeIsOneUndoEntry() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let c = Todo(title: "C")
        let store = try makeStore([a, b, c])
        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: b.id)
        store.toggleCompletion(id: c.id)
        timer.advance(by: 3)

        store.undo()

        XCTAssertFalse(store.canUndo)
    }

    func testCompletionUndoNameIsComplete() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 3)

        XCTAssertEqual(store.undoActionName, "完了")
    }

    // MARK: - 戻す（Issue のケース）

    func testUndoUncheckRestoresArchiveWithOriginalCompletedAt() throws {
        let completed = try date(2026, 11, 25, 10, 0, 0)
        let done = Todo(title: "済み", completedAt: completed)
        let store = try makeStore([done])
        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)
        XCTAssertNil(completedAt(store, done.id))

        store.undo()

        XCTAssertEqual(completedAt(store, done.id), completed)
        XCTAssertEqual(store.archivedTodos.map(\.id), [done.id])
        XCTAssertTrue(store.inboxTodos.isEmpty)
    }

    func testRedoUncheckReturnsToInbox() throws {
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([done])
        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        store.undo()
        store.redo()

        XCTAssertNil(completedAt(store, done.id))
        XCTAssertEqual(store.inboxTodos.map(\.id), [done.id])
    }

    func testUncheckUndoNameIsRestore() throws {
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([done])

        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        XCTAssertEqual(store.undoActionName, "戻す")
    }

    func testMixedCommitUndoNameIsCompleteAndRestore() throws {
        let a = Todo(title: "A")
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([a, done])

        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        XCTAssertEqual(store.undoActionName, "完了と戻す")
    }

    func testUndoMixedCommitRestoresBothSides() throws {
        let completed = try date(2026, 11, 25, 10, 0, 0)
        let a = Todo(title: "A")
        let done = Todo(title: "済み", completedAt: completed)
        let store = try makeStore([a, done])
        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        store.undo()

        XCTAssertNil(completedAt(store, a.id))
        XCTAssertEqual(completedAt(store, done.id), completed)
    }

    // MARK: - 保留中（Issue のケース）

    func testUndoDuringPendingCommitsFirstThenUndoesAndKeepsInInbox() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.toggleCompletion(id: a.id)

        store.undo()

        XCTAssertNil(completedAt(store, a.id))
        XCTAssertEqual(store.inboxTodos.map(\.id), [a.id])
        XCTAssertFalse(store.isShownCompleted(id: a.id))
        XCTAssertTrue(store.pendingToggles.isEmpty)
        XCTAssertEqual(timer.activeCount, 0)
    }

    func testRedoAfterUndoDuringPendingCompletesTodo() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.toggleCompletion(id: a.id)
        let checkedAt = timer.now

        store.undo()
        store.redo()

        XCTAssertEqual(completedAt(store, a.id), checkedAt)
        XCTAssertEqual(store.archivedTodos.map(\.id), [a.id])
    }

    func testDeletingOtherTodoDuringPendingDoesNotCommitPending() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])
        store.toggleCompletion(id: a.id)

        store.delete(id: b.id)

        XCTAssertNil(completedAt(store, a.id))
        XCTAssertTrue(store.isShownCompleted(id: a.id))
        XCTAssertNotNil(store.pendingToggles[a.id])
        // 猶予が過ぎれば、いつもどおり確定する
        timer.advance(by: 3)
        XCTAssertNotNil(completedAt(store, a.id))
    }

    func testPendingRegistersNothingInHistory() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)

        XCTAssertFalse(store.canUndo)
    }

    func testCancelingPendingRegistersNothingInHistory() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: a.id)
        timer.advance(by: 10)

        XCTAssertFalse(store.canUndo)
    }

    func testCommitRegistersHistoryOnlyWhenGraceEnds() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 2.9)
        XCTAssertFalse(store.canUndo)
        timer.advance(by: 0.1)

        XCTAssertTrue(store.canUndo)
    }

    func testUndoWithNewPendingCommitsItAsSeparateEntryAndUndoesOnlyThat() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])
        store.toggleCompletion(id: a.id)
        timer.advance(by: 3)
        store.toggleCompletion(id: b.id)

        store.undo()

        // B は確定されてから取り消され、A の完了はそのまま
        XCTAssertNil(completedAt(store, b.id))
        XCTAssertNotNil(completedAt(store, a.id))
        XCTAssertTrue(store.canUndo)
    }

    func testUndoDeleteOfPendingTodoBringsItBackNotPending() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])
        store.toggleCompletion(id: a.id)
        store.delete(id: a.id)

        store.undo()

        // 保留中に削除した A を取り消しで戻す。A の保留は削除で外れているので、完了にはならない
        XCTAssertEqual(store.todos.map(\.id), [a.id, b.id])
        XCTAssertNil(completedAt(store, a.id))
        timer.advance(by: 10)
        XCTAssertNil(completedAt(store, a.id))
    }

    // MARK: - 履歴の決まり（Issue のケース）

    func testNewOperationClearsRedoHistory() throws {
        let store = try makeStore([])
        store.add(title: "A")
        store.undo()
        XCTAssertTrue(store.canRedo)

        store.add(title: "B")

        XCTAssertFalse(store.canRedo)
        store.redo()
        XCTAssertEqual(store.todos.map(\.title), ["B"])
    }

    func testUndoWithNothingToUndoDoesNothing() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 25, 9, 0, 0))
        let store = try makeStore([a])

        XCTAssertFalse(store.canUndo)
        store.undo()

        XCTAssertEqual(store.todos, [a])
        XCTAssertFalse(store.canRedo)
    }

    func testRedoWithNothingToRedoDoesNothing() throws {
        let store = try makeStore([])
        store.add(title: "A")

        XCTAssertFalse(store.canRedo)
        store.redo()

        XCTAssertEqual(store.todos.map(\.title), ["A"])
        XCTAssertTrue(store.canUndo)
    }

    // MARK: - 履歴の決まり（境目）

    func testRedoNameAvailableAfterUndo() throws {
        let store = try makeStore([])
        store.add(title: "A")

        store.undo()

        XCTAssertTrue(store.canRedo)
        XCTAssertEqual(store.redoActionName, "追加")
    }

    func testCanUndoBecomesFalseAfterUndoingEverything() throws {
        let store = try makeStore([])
        store.add(title: "A")

        store.undo()

        XCTAssertFalse(store.canUndo)
    }

    func testUndoAndRedoCanBeRepeated() throws {
        let store = try makeStore([])
        let a = try XCTUnwrap(store.add(title: "A"))

        store.undo()
        store.redo()
        store.undo()
        store.redo()

        XCTAssertEqual(store.todos, [a])
    }

    func testUndoOrderIsReverseOfOperations() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])
        store.commitTitle(id: a.id, text: "A2")
        store.commitTitle(id: a.id, text: "A3")

        store.undo()
        XCTAssertEqual(store.todos.first?.title, "A2")
        store.undo()
        XCTAssertEqual(store.todos.first?.title, "A")
    }

    func testUndoIsSavedToFile() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 25, 9, 0, 0))
        let store = try makeStore([a])
        store.delete(id: a.id)

        store.undo()
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved, [a])
    }

    // MARK: - ヘルパー

    private var fileURL: URL {
        directory.appendingPathComponent("todos.json")
    }

    func testRedoAddKeepsDescriptionTypedAfterAdding() throws {
        let store = try makeStore([])
        let added = try XCTUnwrap(store.add(title: "A"))
        var typed = added
        typed.descriptionText = "あとから打った説明"
        store.update(typed, registersUndo: false)

        store.undo()
        store.redo()

        XCTAssertEqual(store.todos.first?.descriptionText, "あとから打った説明")
    }

    func testUndoDeleteKeepsEditsMadeBetweenUndoAndRedo() throws {
        let a = Todo(title: "A", createdAt: try date(2026, 11, 24, 9, 0, 0))
        let store = try makeStore([a])
        store.delete(id: a.id)
        store.undo()
        var typed = a
        typed.descriptionText = "戻したあとに打った説明"
        store.update(typed, registersUndo: false)

        store.redo()
        store.undo()

        XCTAssertEqual(store.todos.first?.descriptionText, "戻したあとに打った説明")
    }

    func testPendingActionNameIsEmptyWithoutPending() throws {
        let store = try makeStore([Todo(title: "A")])

        XCTAssertEqual(store.pendingActionName, "")
    }

    func testPendingActionNameNamesWhatCommittingWouldDo() throws {
        let inbox = Todo(title: "A")
        let archived = Todo(title: "B", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([inbox, archived])

        store.toggleCompletion(id: inbox.id)
        XCTAssertEqual(store.pendingActionName, "完了")

        store.toggleCompletion(id: inbox.id)
        store.toggleCompletion(id: archived.id)
        XCTAssertEqual(store.pendingActionName, "戻す")

        store.toggleCompletion(id: inbox.id)
        XCTAssertEqual(store.pendingActionName, "完了と戻す")
    }

    private func makeStore(_ todos: [Todo]) throws -> TodoStore {
        try Persistence.encode(todos).write(to: fileURL)
        return TodoStore(
            persistence: Persistence(directory: directory, saveDelay: 10),
            now: { [timer] in timer?.now ?? .now },
            scheduleTimer: { [timer] delay, action in
                timer?.schedule(after: delay, action) ?? {}
            })
    }

    private func completedAt(_ store: TodoStore, _ id: Todo.ID) -> Date? {
        store.todos.first { $0.id == id }?.completedAt
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

/// 時間を進めたら動く偽のタイマー。`now` も同じ時間で進む。
@MainActor
private final class FakeGraceTimer {
    private struct Entry {
        let id: Int
        let fireAt: TimeInterval
        let action: () -> Void
    }

    private let start: Date
    private var elapsed: TimeInterval = 0
    private var entries: [Entry] = []
    private var nextID = 0

    init(start: Date) {
        self.start = start
    }

    var now: Date {
        start.addingTimeInterval(elapsed)
    }

    /// 予約されていて、まだ動いても取り消されてもいないものの数。
    var activeCount: Int {
        entries.count
    }

    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, fireAt: elapsed + delay, action: action))
        return { [weak self] in
            MainActor.assumeIsolated {
                self?.entries.removeAll { $0.id == id }
            }
        }
    }

    /// 時間を進め、期限が来たものを早い順に動かす。
    func advance(by seconds: TimeInterval) {
        let target = elapsed + seconds
        while let next = entries.filter({ $0.fireAt <= target + 1e-9 }).min(by: { $0.fireAt < $1.fireAt }) {
            elapsed = max(elapsed, next.fireAt)
            entries.removeAll { $0.id == next.id }
            next.action()
        }
        elapsed = target
    }
}
