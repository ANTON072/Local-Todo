import XCTest

@testable import LocalTodo

/// 期限日の書き方のテスト。一覧の行（`TodoRowView` の2行目）と、詳細ペインの日付ボタン。
/// カレンダーはグレゴリオ暦・Asia/Tokyo に固定し、今を 2026/11/26 10:00 とする。
final class DueDateTextTests: XCTestCase {
    private var tokyo: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        tokyo = calendar
        now = try date(2026, 11, 26, 10, 0)
    }

    // MARK: - 一覧の行の書き方（Issue のケース）

    func testRowTextForDateOnlyThisYear() throws {
        let due = try day(2026, 11, 24)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "11/24")
    }

    func testRowTextDoesNotZeroPadMonthAndDay() throws {
        let due = try day(2026, 1, 5)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "1/5")
    }

    func testRowTextForNextYearIncludesYear() throws {
        let due = try day(2027, 1, 5)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "2027/1/5")
    }

    func testRowTextForPreviousYearIncludesYear() throws {
        let due = try day(2025, 12, 31)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "2025/12/31")
    }

    func testRowTextForTodoWithoutDueDateIsNil() {
        let todo = Todo(title: "A")

        XCTAssertNil(todo.dueDateRowText(now: now, calendar: tokyo))
    }

    // MARK: - 一覧の行の書き方（境目）

    func testRowTextForLastDayOfThisYearHasNoYear() throws {
        let due = try day(2026, 12, 31)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "12/31")
    }

    func testRowTextForFirstDayOfThisYearHasNoYear() throws {
        let due = try day(2026, 1, 1)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "1/1")
    }

    func testRowTextForFirstDayOfNextYearIncludesYear() throws {
        let due = try day(2027, 1, 1)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "2027/1/1")
    }

    func testRowTextForTwoDigitMonthAndDay() throws {
        let due = try day(2026, 10, 10)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "10/10")
    }

    func testRowTextForTodayIsDateNotWord() throws {
        // 「今日」「明日」と言い換えない
        let due = try day(2026, 11, 26)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "11/26")
    }

    func testRowTextForTomorrowIsDateNotWord() throws {
        let due = try day(2026, 11, 27)

        XCTAssertEqual(due.rowText(now: now, calendar: tokyo), "11/27")
    }

    func testRowTextUsesCalendarTimeZoneForThisYear() throws {
        // 今が東京の 2027/1/1 0:30（UTC ではまだ 2026 年）なら、今年は 2027 年
        let newYear = try date(2027, 1, 1, 0, 30)
        let due = try day(2027, 1, 5)

        XCTAssertEqual(due.rowText(now: newYear, calendar: tokyo), "1/5")
    }

    func testRowTextForTodoWithDueDateMatchesDueDateRowText() throws {
        let due = try day(2026, 11, 24)
        let todo = Todo(title: "A", dueDate: due)

        XCTAssertEqual(todo.dueDateRowText(now: now, calendar: tokyo), "11/24")
    }

    func testRowTextForArchivedTodoStillShowsDueDate() throws {
        // アーカイブの行にも出す
        let todo = Todo(
            title: "A", dueDate: try day(2026, 11, 24), completedAt: try date(2026, 11, 25, 9, 0))

        XCTAssertEqual(todo.dueDateRowText(now: now, calendar: tokyo), "11/24")
    }

    // MARK: - 詳細ペインの日付ボタンの書き方（Issue のケース）

    func testButtonTextAlwaysIncludesYear() throws {
        let due = try day(2026, 11, 26)

        XCTAssertEqual(due.label, "2026/11/26")
    }

    func testButtonTextDoesNotZeroPad() throws {
        let due = try day(2026, 1, 5)

        XCTAssertEqual(due.label, "2026/1/5")
    }

    // MARK: - 詳細ペインの日付ボタンの書き方（境目）

    func testButtonTextForNextYear() throws {
        let due = try day(2027, 12, 31)

        XCTAssertEqual(due.label, "2027/12/31")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try XCTUnwrap(
            tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0)))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        CalendarDay(try date(year, month, day, 0, 0), calendar: tokyo)
    }
}
