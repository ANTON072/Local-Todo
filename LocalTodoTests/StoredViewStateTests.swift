import XCTest

@testable import LocalTodo

/// `@AppStorage` に文字列で保存した、並び順と選んでいた画面を、起動時に戻せるか。
final class StoredViewStateTests: XCTestCase {
    // MARK: - 画面（Inbox／アーカイブ）

    func testListKindRestoresInbox() {
        XCTAssertEqual(TodoListKind(storedValue: TodoListKind.inbox.storedValue), .inbox)
    }

    func testListKindRestoresArchive() {
        XCTAssertEqual(TodoListKind(storedValue: TodoListKind.archive.storedValue), .archive)
    }

    func testListKindStoredValuesAreDifferent() {
        XCTAssertNotEqual(TodoListKind.inbox.storedValue, TodoListKind.archive.storedValue)
    }

    func testListKindFallsBackToInboxForEmptyString() {
        XCTAssertEqual(TodoListKind(storedValue: ""), .inbox)
    }

    func testListKindFallsBackToInboxForUnknownString() {
        XCTAssertEqual(TodoListKind(storedValue: "unknown"), .inbox)
    }

    func testListKindFallsBackToInboxForSurroundingSpaces() {
        // 保存するのはこのアプリだけなので、緩く読まない
        XCTAssertEqual(TodoListKind(storedValue: " \(TodoListKind.archive.storedValue) "), .inbox)
    }

    // MARK: - 並び順

    func testSortOrderRestoresDueDate() {
        XCTAssertEqual(InboxSortOrder(storedValue: InboxSortOrder.dueDate.storedValue), .dueDate)
    }

    func testSortOrderRestoresCreatedAt() {
        XCTAssertEqual(InboxSortOrder(storedValue: InboxSortOrder.createdAt.storedValue), .createdAt)
    }

    func testSortOrderStoredValuesAreDifferent() {
        XCTAssertNotEqual(InboxSortOrder.dueDate.storedValue, InboxSortOrder.createdAt.storedValue)
    }

    func testSortOrderFallsBackToDueDateForEmptyString() {
        XCTAssertEqual(InboxSortOrder(storedValue: ""), .dueDate)
    }

    func testSortOrderFallsBackToDueDateForUnknownString() {
        XCTAssertEqual(InboxSortOrder(storedValue: "unknown"), .dueDate)
    }

    func testSortOrderFallsBackToDueDateForListKindValue() {
        // 画面の保存値を並び順に渡しても、並び順としては読めない
        XCTAssertEqual(InboxSortOrder(storedValue: TodoListKind.archive.storedValue), .dueDate)
    }

    func testSortOrderFallsBackToDueDateForSurroundingSpaces() {
        XCTAssertEqual(InboxSortOrder(storedValue: " \(InboxSortOrder.createdAt.storedValue) "), .dueDate)
    }
}
