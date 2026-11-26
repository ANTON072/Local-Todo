import XCTest

@testable import LocalTodo

/// 完了とアーカイブの、約3秒の猶予（保留中）のテスト。時間は偽のタイマーを進めて作る。
@MainActor
final class TodoCompletionTests: XCTestCase {
    private var directory: URL!
    private var timer: FakeTimer!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoCompletionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        timer = FakeTimer(start: try date(2026, 11, 26, 12, 0, 0))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Inbox で完了にする（Issue のケース）

    func testCheckingShowsCompletedButKeepsCompletedAtNilAndStaysInInbox() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 2.9)

        XCTAssertTrue(store.isShownCompleted(id: a.id))
        XCTAssertNil(store.todos.first?.completedAt)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["A"])
        XCTAssertTrue(store.archivedTodos.isEmpty)
    }

    func testPendingTodoMovesToArchiveAfterGracePeriod() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        let checkedAt = timer.now
        timer.advance(by: 3)

        XCTAssertEqual(store.todos.first?.completedAt, checkedAt)
        XCTAssertTrue(store.inboxTodos.isEmpty)
        XCTAssertEqual(store.archivedTodos.map(\.title), ["A"])
        XCTAssertTrue(store.isShownCompleted(id: a.id))
    }

    func testConsecutiveChecksMoveTogetherWithEachCheckTime() throws {
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
        // 最後のチェックの直前までは、3件とも動かない
        timer.advance(by: 2.9)
        XCTAssertEqual(store.inboxTodos.count, 3)
        timer.advance(by: 0.1)

        XCTAssertTrue(store.inboxTodos.isEmpty)
        XCTAssertEqual(completedAt(store, a.id), checkedA)
        XCTAssertEqual(completedAt(store, b.id), checkedB)
        XCTAssertEqual(completedAt(store, c.id), checkedC)
        // チェックした順の新しい順
        XCTAssertEqual(store.archivedTodos.map(\.title), ["C", "B", "A"])
    }

    func testSecondCheckRestartsCountdownForFirst() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 2)
        store.toggleCompletion(id: b.id)
        // A のチェックから3秒たっても、数え直しているのでまだ動かない
        timer.advance(by: 2.9)
        XCTAssertNil(completedAt(store, a.id))
        XCTAssertNil(completedAt(store, b.id))
        timer.advance(by: 0.1)

        XCTAssertNotNil(completedAt(store, a.id))
        XCTAssertNotNil(completedAt(store, b.id))
    }

    func testUncheckingOneRestartsCountdownForRest() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: b.id)
        let checkedB = timer.now
        timer.advance(by: 2)
        store.toggleCompletion(id: a.id)

        XCTAssertFalse(store.isShownCompleted(id: a.id))
        XCTAssertTrue(store.isShownCompleted(id: b.id))
        // B の元の3秒（あと1秒）では動かない
        timer.advance(by: 2.9)
        XCTAssertNil(completedAt(store, b.id))
        timer.advance(by: 0.1)

        XCTAssertEqual(completedAt(store, b.id), checkedB)
        XCTAssertNil(completedAt(store, a.id))
        XCTAssertEqual(store.inboxTodos.map(\.title), ["A"])
        XCTAssertFalse(store.isShownCompleted(id: a.id))
    }

    func testTimerStopsAndNothingCommitsWhenAllPendingAreRemoved() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: a.id)

        XCTAssertEqual(timer.activeCount, 0)
        timer.advance(by: 10)
        XCTAssertNil(store.todos.first?.completedAt)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["A"])
        XCTAssertFalse(store.isShownCompleted(id: a.id))
    }

    func testTimerStopsAfterCommit() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 3)

        XCTAssertEqual(timer.activeCount, 0)
    }

    func testGracePeriodIsAboutThreeSeconds() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)

        let delay = try XCTUnwrap(timer.lastDelay)
        XCTAssertEqual(delay, 3, accuracy: 0.5)
    }

    // MARK: - アーカイブでチェックを外す（Issue のケース）

    func testUncheckingInArchiveShowsIncompleteButStaysInArchive() throws {
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([done])

        XCTAssertTrue(store.isShownCompleted(id: done.id))
        store.toggleCompletion(id: done.id)
        timer.advance(by: 2.9)

        XCTAssertFalse(store.isShownCompleted(id: done.id))
        XCTAssertNotNil(store.todos.first?.completedAt)
        XCTAssertEqual(store.archivedTodos.map(\.title), ["済み"])
    }

    func testUncheckedArchivedTodoReturnsToInboxAfterGracePeriod() throws {
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([done])

        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        XCTAssertNil(store.todos.first?.completedAt)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["済み"])
        XCTAssertTrue(store.archivedTodos.isEmpty)
        XCTAssertFalse(store.isShownCompleted(id: done.id))
    }

    func testClickingAgainDuringGraceKeepsTodoInArchive() throws {
        let completed = try date(2026, 11, 25, 10, 0, 0)
        let done = Todo(title: "済み", completedAt: completed)
        let store = try makeStore([done])

        store.toggleCompletion(id: done.id)
        timer.advance(by: 2)
        store.toggleCompletion(id: done.id)
        timer.advance(by: 10)

        XCTAssertEqual(store.todos.first?.completedAt, completed)
        XCTAssertEqual(store.archivedTodos.map(\.title), ["済み"])
        XCTAssertTrue(store.isShownCompleted(id: done.id))
    }

    // MARK: - saveNow・delete・update・存在しない ID（Issue のケース）

    func testSaveNowCommitsPendingBeforeWriting() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        let checkedAt = timer.now
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved.first?.completedAt, checkedAt)
        XCTAssertEqual(store.archivedTodos.map(\.title), ["A"])
    }

    func testDeletingPendingTodoRemovesItFromPendingAndCommitsNothing() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.toggleCompletion(id: a.id)
        store.delete(id: a.id)
        timer.advance(by: 10)

        XCTAssertEqual(store.todos.map(\.title), ["B"])
        XCTAssertNil(completedAt(store, b.id))
        XCTAssertTrue(store.archivedTodos.isEmpty)
        XCTAssertEqual(timer.activeCount, 0)
    }

    func testUpdatingTitleOfPendingTodoKeepsPendingAndCommitsLater() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        let checkedAt = timer.now
        var edited = a
        edited.title = "A 改"
        store.update(edited)

        XCTAssertTrue(store.isShownCompleted(id: a.id))
        XCTAssertNil(completedAt(store, a.id))
        timer.advance(by: 3)
        XCTAssertEqual(completedAt(store, a.id), checkedAt)
        XCTAssertEqual(store.archivedTodos.map(\.title), ["A 改"])
    }

    func testToggleWithUnknownIDChangesNothing() throws {
        // 保存で秒未満が落ちるので、読み戻した値と比べられるよう整数秒の作成日時にする
        let a = Todo(title: "A", createdAt: try date(2026, 11, 26, 9, 0, 0))
        let store = try makeStore([a])

        store.toggleCompletion(id: UUID())

        XCTAssertEqual(timer.activeCount, 0)
        timer.advance(by: 10)
        XCTAssertEqual(store.todos, [a])
        XCTAssertFalse(store.isShownCompleted(id: a.id))
    }

    // MARK: - 境目（追加）

    func testIsShownCompletedIsFalseForUnknownID() throws {
        let store = try makeStore([Todo(title: "A")])

        XCTAssertFalse(store.isShownCompleted(id: UUID()))
    }

    func testIsShownCompletedIsFalseForUntouchedInboxTodo() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        XCTAssertFalse(store.isShownCompleted(id: a.id))
    }

    func testSaveNowWithoutPendingChangesNothing() throws {
        // 保存で秒未満が落ちるので、読み戻した値と比べられるよう整数秒の作成日時にする
        let a = Todo(title: "A", createdAt: try date(2026, 11, 26, 9, 0, 0))
        let store = try makeStore([a])

        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertEqual(saved, [a])
    }

    func testSaveNowCommitsArchiveUncheckToo() throws {
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([done])

        store.toggleCompletion(id: done.id)
        store.saveNow()

        let saved = try Persistence.decode(Data(contentsOf: fileURL))
        XCTAssertNil(saved.first?.completedAt)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["済み"])
    }

    func testPendingInboxAndArchiveTodosCommitTogether() throws {
        let a = Todo(title: "A")
        let done = Todo(title: "済み", completedAt: try date(2026, 11, 25, 10, 0, 0))
        let store = try makeStore([a, done])

        store.toggleCompletion(id: a.id)
        store.toggleCompletion(id: done.id)
        timer.advance(by: 3)

        XCTAssertNotNil(completedAt(store, a.id))
        XCTAssertNil(completedAt(store, done.id))
    }

    func testCanCheckAgainAfterCommit() throws {
        let a = Todo(title: "A")
        let store = try makeStore([a])

        store.toggleCompletion(id: a.id)
        timer.advance(by: 3)
        store.toggleCompletion(id: a.id)
        timer.advance(by: 3)

        XCTAssertNil(store.todos.first?.completedAt)
        XCTAssertEqual(store.inboxTodos.map(\.title), ["A"])
    }

    func testDeletingNonPendingTodoDoesNotAffectPending() throws {
        let a = Todo(title: "A")
        let b = Todo(title: "B")
        let store = try makeStore([a, b])

        store.toggleCompletion(id: a.id)
        store.delete(id: b.id)
        timer.advance(by: 3)

        XCTAssertNotNil(completedAt(store, a.id))
    }

    // MARK: - ヘルパー

    private var fileURL: URL {
        directory.appendingPathComponent("todos.json")
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
private final class FakeTimer {
    private struct Entry {
        let id: Int
        let fireAt: TimeInterval
        let action: () -> Void
    }

    private let start: Date
    private var elapsed: TimeInterval = 0
    private var entries: [Entry] = []
    private var nextID = 0
    private(set) var lastDelay: TimeInterval?

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
        lastDelay = delay
        entries.append(Entry(id: id, fireAt: elapsed + delay, action: action))
        return { [weak self] in
            MainActor.assumeIsolated {
                self?.entries.removeAll { $0.id == id }
            }
        }
    }

    /// 時間を進め、期限が来たものを早い順に動かす。動かす間に増えたものも、期限が来ていれば動かす。
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
