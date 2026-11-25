import XCTest
@testable import LocalTodo

// テストターゲットの置き場所。実際のテストは各機能の実装と一緒に追加する
final class LocalTodoTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(AppDelegate())
    }
}
