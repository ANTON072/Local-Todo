import XCTest

@testable import LocalTodo

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 往復

    func testRoundTripKeepsAllFields() throws {
        let tokyo = makeTokyoCalendar()
        let todos = [
            Todo(
                title: "企画書を送る",
                titleURL: URL(string: "https://example.com/plan"),
                links: [TodoLink(url: try XCTUnwrap(URL(string: "https://example.com/a")), displayName: "資料 A")],
                descriptionText: "1行目\n2行目",
                dueDate: CalendarDay(try date(2026, 11, 25, calendar: tokyo), calendar: tokyo),
                tags: ["仕事", "急ぎ"],
                createdAt: Date(timeIntervalSince1970: 1_764_000_000.123),
                completedAt: Date(timeIntervalSince1970: 1_764_100_000.456)
            ),
            Todo(title: "本を読む"),
        ]

        let persistence = makePersistence()
        persistence.saveNow(todos)
        let result = makePersistence().load()

        XCTAssertEqual(result.source, .file)
        XCTAssertEqual(result.todos.count, todos.count)
        for (loaded, original) in zip(result.todos, todos) {
            assertSame(loaded, original)
        }
    }

    // MARK: - JSON の形

    func testFileHasVersionAndReadableDueDate() throws {
        let tokyo = makeTokyoCalendar()
        let todo = Todo(
            title: "企画書を送る",
            dueDate: CalendarDay(try date(2026, 11, 25, calendar: tokyo), calendar: tokyo))
        makePersistence().saveNow([todo])

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let first = try XCTUnwrap((json["todos"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["dueDate"] as? [String: String], ["date": "2026-11-25"])
    }

    func testDateIsWrittenAsISO8601WithMilliseconds() throws {
        let todo = Todo(title: "見積確認", createdAt: Date(timeIntervalSince1970: 1_764_050_000.5))
        makePersistence().saveNow([todo])

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains(#""createdAt" : "2025-11-25T05:53:20.500Z""#), text)
    }

    func testDueDateIsWrittenWithoutDateTimeKey() throws {
        let tokyo = makeTokyoCalendar()
        let json = fileJSON(dueDate: #"{"date": "2026-11-24"}"#)
        let todos = try Persistence.decode(json, calendar: tokyo)
        makePersistence().saveNow(todos)

        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let first = try XCTUnwrap((saved["todos"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["dueDate"] as? [String: String], ["date": "2026-11-24"])
    }

    // MARK: - 時刻を持っていたころの期限日

    func testOldDateTimeIsReadAsDayInGivenTimeZone() throws {
        // UTC の 11/24 15:30 は、東京では 11/25 0:30。東京の暦の日付にする
        let tokyo = makeTokyoCalendar()
        let json = fileJSON(dueDate: #"{"dateTime": "2026-11-24T15:30:00.000Z"}"#)

        let due = try XCTUnwrap(try Persistence.decode(json, calendar: tokyo).first?.dueDate)

        XCTAssertEqual([due.year, due.month, due.day], [2026, 11, 25])
    }

    func testOldDateTimeIsWrittenBackAsDate() throws {
        let tokyo = makeTokyoCalendar()
        let json = fileJSON(dueDate: #"{"dateTime": "2026-11-24T15:30:00.000Z"}"#)
        makePersistence().saveNow(try Persistence.decode(json, calendar: tokyo))

        let saved = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
        let first = try XCTUnwrap((saved["todos"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["dueDate"] as? [String: String], ["date": "2026-11-25"])
    }

    // MARK: - 初回起動

    func testLoadWithoutFilesStartsEmpty() {
        let result = makePersistence().load()
        XCTAssertEqual(result.source, .noFile)
        XCTAssertTrue(result.todos.isEmpty)
    }

    // MARK: - バックアップ

    func testBackupIsTakenOnlyOnFirstSaveAfterLaunch() throws {
        makePersistence().saveNow([Todo(title: "前回の起動")])

        // 次の起動
        let persistence = makePersistence()
        persistence.saveNow([Todo(title: "1回目")])
        XCTAssertEqual(try titles(at: backupURL), ["前回の起動"])
        XCTAssertEqual(try titles(at: fileURL), ["1回目"])

        persistence.saveNow([Todo(title: "2回目")])
        XCTAssertEqual(try titles(at: backupURL), ["前回の起動"])
        XCTAssertEqual(try titles(at: fileURL), ["2回目"])
    }

    // MARK: - 読めないファイル

    func testUnreadableFileIsMovedAsideAndBackupIsLoaded() throws {
        try Persistence.encode([Todo(title: "バックアップ")]).write(to: backupURL)
        try Data("壊れた中身".utf8).write(to: fileURL)

        let result = makePersistence().load()

        XCTAssertEqual(result.source, .backup)
        XCTAssertEqual(result.todos.map(\.title), ["バックアップ"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try corruptFiles().count, 1)
    }

    func testUnreadableFileAndBackupStartsEmpty() throws {
        try Data("壊れた中身".utf8).write(to: backupURL)
        try Data("壊れた中身".utf8).write(to: fileURL)

        let result = makePersistence().load()

        XCTAssertEqual(result.source, .unreadable)
        XCTAssertTrue(result.todos.isEmpty)
        XCTAssertEqual(try corruptFiles().count, 1)
    }

    func testUnreadableFileWithoutBackupStartsEmpty() throws {
        try Data("壊れた中身".utf8).write(to: fileURL)

        let result = makePersistence().load()

        XCTAssertEqual(result.source, .unreadable)
        XCTAssertEqual(try corruptFiles().count, 1)
    }

    func testMissingFileWithBackupLoadsBackup() throws {
        try Persistence.encode([Todo(title: "バックアップ")]).write(to: backupURL)

        let result = makePersistence().load()

        XCTAssertEqual(result.source, .backup)
        XCTAssertEqual(result.todos.map(\.title), ["バックアップ"])
    }

    func testBackupIsKeptWhenFirstSaveFollowsLoadingFromBackup() throws {
        try Persistence.encode([Todo(title: "バックアップ")]).write(to: backupURL)
        try Data("壊れた中身".utf8).write(to: fileURL)

        let persistence = makePersistence()
        _ = persistence.load()
        persistence.saveNow([Todo(title: "続き")])

        XCTAssertEqual(try titles(at: backupURL), ["バックアップ"])
    }

    // MARK: - 知らない版

    func testUnknownVersionIsTreatedAsUnreadable() throws {
        try Data(#"{"version": 2, "todos": []}"#.utf8).write(to: fileURL)

        let result = makePersistence().load()

        XCTAssertEqual(result.source, .unreadable)
        XCTAssertEqual(try corruptFiles().count, 1)
    }

    // MARK: - 期限日の読み込みの境目

    func testImpossibleDateIsReadWithoutValidation() throws {
        // 日付として正しいかは検査しない。手で書き換えた1件のためにファイル全体を読めなくしないため
        let todos = try Persistence.decode(fileJSON(dueDate: #"{"date": "2026-02-30"}"#))
        let due = try XCTUnwrap(todos.first?.dueDate)
        XCTAssertEqual([due.year, due.month, due.day], [2026, 2, 30])
    }

    func testMalformedCalendarDayIsDecodingError() {
        for text in ["2026-11", "2026-xx-25", "2026-11-25-01", "abc", ""] {
            XCTAssertThrowsError(
                try Persistence.decode(fileJSON(dueDate: #"{"date": "\#(text)"}"#)), "\(text) が読めてしまった")
        }
    }

    func testDueDateWithBothKeysIsDecodingError() {
        let json = fileJSON(dueDate: #"{"date": "2026-11-25", "dateTime": "2026-11-25T06:00:00.000Z"}"#)
        XCTAssertThrowsError(try Persistence.decode(json))
    }

    func testDueDateWithoutKeysIsDecodingError() {
        XCTAssertThrowsError(try Persistence.decode(fileJSON(dueDate: "{}")))
    }

    // MARK: - まとめ保存

    func testScheduledSavesAreCoalescedIntoLastOne() throws {
        let persistence = makePersistence(saveDelay: 0.3)
        persistence.scheduleSave([Todo(title: "1")])
        Thread.sleep(forTimeInterval: 0.1)
        persistence.scheduleSave([Todo(title: "2")])
        Thread.sleep(forTimeInterval: 0.1)
        persistence.scheduleSave([Todo(title: "3")])

        // 最初の予約が生きていれば書かれている時刻。取り消されていれば、まだ何も書かれていない
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try titles(at: fileURL), ["3"])
    }

    // MARK: - すぐ保存

    func testSaveNowWritesLatestAndCancelsScheduledSave() throws {
        let persistence = makePersistence(saveDelay: 0.1)
        persistence.scheduleSave([Todo(title: "予約")])
        persistence.saveNow([Todo(title: "すぐ")])
        XCTAssertEqual(try titles(at: fileURL), ["すぐ"])

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try titles(at: fileURL), ["すぐ"])
    }

    // MARK: - 保存の失敗

    func testSaveErrorIsReported() throws {
        // フォルダのはずの場所にファイルを置き、書き込めないようにする
        let notADirectory = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: notADirectory)
        let reported = expectation(description: "保存の失敗が知らされる")
        let persistence = Persistence(directory: notADirectory, saveDelay: 0) { _ in
            reported.fulfill()
        }

        persistence.saveNow([Todo(title: "保存できない")])

        wait(for: [reported], timeout: 1)
    }

    // MARK: - ヘルパー

    private var fileURL: URL { directory.appendingPathComponent("todos.json") }
    private var backupURL: URL { directory.appendingPathComponent("todos.backup.json") }

    private func makePersistence(saveDelay: TimeInterval = 0.05) -> Persistence {
        Persistence(directory: directory, saveDelay: saveDelay)
    }

    private func titles(at url: URL) throws -> [String] {
        try Persistence.decode(Data(contentsOf: url)).map(\.title)
    }

    /// 期限日の部分だけを差し替えた、Todo 1件のファイルの中身。
    private func fileJSON(dueDate: String) -> Data {
        Data(
            """
            {
              "version": 1,
              "todos": [
                {
                  "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
                  "title": "企画書を送る",
                  "links": [],
                  "descriptionText": "",
                  "tags": [],
                  "createdAt": "2026-11-25T02:00:00.000Z",
                  "dueDate": \(dueDate)
                }
              ]
            }
            """.utf8)
    }

    private func corruptFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("todos.corrupt-") && $0.hasSuffix(".json") }
    }

    private func makeTokyoCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// 日時はミリ秒の精度で比べる。
    private func assertSame(_ loaded: Todo, _ original: Todo, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(loaded.id, original.id, file: file, line: line)
        XCTAssertEqual(loaded.title, original.title, file: file, line: line)
        XCTAssertEqual(loaded.titleURL, original.titleURL, file: file, line: line)
        XCTAssertEqual(loaded.links, original.links, file: file, line: line)
        XCTAssertEqual(loaded.descriptionText, original.descriptionText, file: file, line: line)
        XCTAssertEqual(loaded.tags, original.tags, file: file, line: line)
        assertSameDate(loaded.createdAt, original.createdAt, file: file, line: line)
        assertSameDate(loaded.completedAt, original.completedAt, file: file, line: line)
        XCTAssertEqual(loaded.dueDate, original.dueDate, file: file, line: line)
    }

    private func assertSameDate(_ loaded: Date?, _ original: Date?, file: StaticString, line: UInt) {
        switch (loaded, original) {
        case (nil, nil):
            break
        case (let loaded?, let original?):
            XCTAssertEqual(
                loaded.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.001, file: file, line: line)
        default:
            XCTFail("片方だけ nil", file: file, line: line)
        }
    }
}
