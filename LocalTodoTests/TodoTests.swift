import XCTest

@testable import LocalTodo

final class TodoTests: XCTestCase {
    private let tokyo = TodoTests.makeCalendar("Asia/Tokyo")

    // MARK: - 期限切れ

    func testIsNotPastDueAtEndOfDueDay() throws {
        let due = try dueDay(2026, 11, 25)
        XCTAssertFalse(due.isPastDue(now: try date(2026, 11, 25, 23, 59, 59), calendar: tokyo))
    }

    func testIsPastDueAtMidnightOfNextDay() throws {
        let due = try dueDay(2026, 11, 25)
        XCTAssertTrue(due.isPastDue(now: try date(2026, 11, 26, 0, 0, 0), calendar: tokyo))
    }

    func testIsPastDueOneSecondAfterMidnightOfNextDay() throws {
        let due = try dueDay(2026, 11, 25)
        XCTAssertTrue(due.isPastDue(now: try date(2026, 11, 26, 0, 0, 1), calendar: tokyo))
    }

    // MARK: - 見出し・日付だけ

    func testDateHeadingFollowsDueDay() throws {
        let now = try date(2026, 11, 25, 12, 0, 0)
        XCTAssertEqual(try dueDay(2026, 11, 24).heading(now: now, calendar: tokyo), .beforeToday)
        XCTAssertEqual(try dueDay(2026, 11, 25).heading(now: now, calendar: tokyo), .today)
        XCTAssertEqual(try dueDay(2026, 11, 26).heading(now: now, calendar: tokyo), .afterToday)
    }

    // MARK: - 見出し・期限なし

    func testTodoWithoutDueDateHasNoDueDateHeadingAndIsNotPastDue() throws {
        let todo = Todo(title: "本を読む")
        let now = try date(2026, 11, 25, 12, 0, 0)
        XCTAssertEqual(todo.dueHeading(now: now, calendar: tokyo), .noDueDate)
        XCTAssertFalse(todo.isPastDue(now: now, calendar: tokyo))
    }

    func testTodoForwardsDueDateJudgement() throws {
        let todo = Todo(title: "企画書を送る", dueDate: try dueDay(2026, 11, 24))
        let now = try date(2026, 11, 25, 12, 0, 0)
        XCTAssertEqual(todo.dueHeading(now: now, calendar: tokyo), .beforeToday)
        XCTAssertTrue(todo.isPastDue(now: now, calendar: tokyo))
    }

    // MARK: - 見出しの 0:00 の境目

    func testHeadingChangesFromTodayToBeforeTodayAtMidnight() throws {
        let due = try dueDay(2026, 11, 25)
        XCTAssertEqual(due.heading(now: try date(2026, 11, 25, 23, 59, 59), calendar: tokyo), .today)
        XCTAssertEqual(due.heading(now: try date(2026, 11, 26, 0, 0, 0), calendar: tokyo), .beforeToday)
    }

    // MARK: - タイムゾーンをまたぐ

    func testDateKeepsItsDayInAnotherTimeZone() throws {
        // 東京の 11/25 0:00 はニューヨークでは 11/24 10:00。日付だけの期限は 11/25 のまま扱う。
        let due = try dueDay(2026, 11, 25)
        let newYork = Self.makeCalendar("America/New_York")
        let now = try XCTUnwrap(
            newYork.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 23, minute: 59)))
        XCTAssertEqual(due.heading(now: now, calendar: newYork), .today)
        XCTAssertFalse(due.isPastDue(now: now, calendar: newYork))
    }

    // MARK: - 和暦

    func testJapaneseCalendarKeepsOrderAcrossEraChange() throws {
        // 和暦では 2019/4/30 は平成31年、5/1 は令和元年。年だけ見ると順序が逆になる。
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = tokyo.timeZone
        let due = (CalendarDay(try date(2019, 4, 30), calendar: japanese))
        let now = try date(2019, 5, 1, 12, 0, 0)
        XCTAssertEqual(due.heading(now: now, calendar: japanese), .beforeToday)
        XCTAssertTrue(due.isPastDue(now: now, calendar: japanese))
    }

    // MARK: - Inbox／アーカイブ

    func testTodoIsArchivedOnlyWhenCompleted() throws {
        var todo = Todo(title: "見積確認")
        XCTAssertFalse(todo.isArchived)
        todo.completedAt = try date(2026, 11, 25, 12, 0, 0)
        XCTAssertTrue(todo.isArchived)
    }

    // MARK: - CalendarDay

    func testCalendarDayComparesAcrossMonthAndYearEnds() throws {
        let nov30 = CalendarDay(try date(2026, 11, 30), calendar: tokyo)
        let dec1 = CalendarDay(try date(2026, 12, 1), calendar: tokyo)
        let dec31 = CalendarDay(try date(2026, 12, 31), calendar: tokyo)
        let jan1 = CalendarDay(try date(2027, 1, 1), calendar: tokyo)
        XCTAssertLessThan(nov30, dec1)
        XCTAssertLessThan(dec31, jan1)
        XCTAssertLessThan(nov30, jan1)
        XCTAssertEqual(dec1, CalendarDay(try date(2026, 12, 1, 23, 59, 59), calendar: tokyo))
    }

    // MARK: - ヘルパー

    private static func makeCalendar(_ timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    /// 東京の日時を作る。
    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) throws -> Date {
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return try XCTUnwrap(tokyo.date(from: components))
    }

    /// 東京で作った日付だけの期限日。
    private func dueDay(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDay {
        CalendarDay(try date(year, month, day), calendar: tokyo)
    }
}
