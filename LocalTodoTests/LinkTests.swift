import XCTest

@testable import LocalTodo

/// タイトルからの URL の判定と抜き出し（`LinkTitleFetcher.extract`）のテスト。
final class LinkTests: XCTestCase {
    private func assertExtract(
        _ input: String, url: String?, title: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = LinkTitleFetcher.extract(from: input)
        XCTAssertEqual(result.url, url.flatMap { URL(string: $0) }, file: file, line: line)
        XCTAssertEqual(result.title, title, file: file, line: line)
    }

    // MARK: - 判定（Issue のケース）

    func testHttpsURLWithQueryAndFragmentIsURL() {
        let result = LinkTitleFetcher.extract(from: "https://example.com/a?b=c#top")

        XCTAssertEqual(result.url, URL(string: "https://example.com/a?b=c#top"))
    }

    func testDomainOnlyIsNotURL() {
        assertExtract("example.com", url: nil, title: "example.com")
    }

    func testEmailIsNotURL() {
        assertExtract("a@b.com", url: nil, title: "a@b.com")
    }

    func testFtpIsNotURL() {
        assertExtract("ftp://example.com/x", url: nil, title: "ftp://example.com/x")
    }

    func testFileSchemeIsNotURL() {
        assertExtract("file:///etc/hosts", url: nil, title: "file:///etc/hosts")
    }

    func testTelIsNotURL() {
        assertExtract("tel:0312345678", url: nil, title: "tel:0312345678")
    }

    func testFullWidthPeriodIsNotPartOfURL() {
        let result = LinkTitleFetcher.extract(from: "https://example.com。次へ")

        XCTAssertEqual(result.url, URL(string: "https://example.com"))
    }

    func testSurroundingParenthesesAreNotPartOfURL() {
        let result = LinkTitleFetcher.extract(from: "(https://example.com/a)")

        XCTAssertEqual(result.url, URL(string: "https://example.com/a"))
    }

    // MARK: - タイトル全体が URL（Issue のケース）

    func testWholeTitleURLKeepsTitleAsURL() {
        assertExtract("https://example.com/a", url: "https://example.com/a", title: "https://example.com/a")
    }

    // MARK: - 一部が URL（Issue のケース）

    func testURLInMiddleIsRemovedWithFollowingSpace() {
        assertExtract("資料 https://a.com 確認", url: "https://a.com", title: "資料 確認")
    }

    func testURLAtStartIsRemoved() {
        assertExtract("https://a.com 資料", url: "https://a.com", title: "資料")
    }

    func testURLAtEndIsRemoved() {
        assertExtract("資料 https://a.com", url: "https://a.com", title: "資料")
    }

    // MARK: - 2つ以上（Issue のケース）

    func testOnlyFirstURLIsExtractedAndSecondStaysInTitle() {
        assertExtract(
            "資料 https://a.com と https://b.com を見る",
            url: "https://a.com", title: "資料 と https://b.com を見る")
    }

    // MARK: - URL でないもの（Issue のケース）

    func testDomainInsideSentenceIsLeftAlone() {
        assertExtract("メモ example.com を読む", url: nil, title: "メモ example.com を読む")
    }

    // MARK: - 境目

    func testEmptyInputHasNoURL() {
        assertExtract("", url: nil, title: "")
    }

    func testPlainTextHasNoURLAndIsUnchanged() {
        assertExtract("企画書を送る", url: nil, title: "企画書を送る")
    }

    func testHttpSchemeIsURL() {
        assertExtract("http://a.com 資料", url: "http://a.com", title: "資料")
    }

    func testMultipleSpacesAfterURLAreAllRemoved() {
        assertExtract("資料 https://a.com    確認", url: "https://a.com", title: "資料 確認")
    }

    func testNewlinesAfterURLAreAllRemoved() {
        assertExtract("資料 https://a.com\n\n確認", url: "https://a.com", title: "資料 確認")
    }

    func testFullWidthSpaceAfterURLIsRemoved() {
        assertExtract("資料 https://a.com\u{3000}確認", url: "https://a.com", title: "資料 確認")
    }

    func testSpacesAroundURLAreTrimmedFromTitle() {
        assertExtract("  https://a.com  資料  ", url: "https://a.com", title: "資料")
    }

    func testNonHttpSchemeBeforeHttpURLIsSkipped() {
        // ftp は URL とみなさず、あとの https を最初の URL とする
        assertExtract("ftp://x.com と https://a.com", url: "https://a.com", title: "ftp://x.com と")
    }

    func testDomainBeforeHttpURLIsSkipped() {
        assertExtract("example.com https://a.com", url: "https://a.com", title: "example.com")
    }

    func testURLWithPathAndQueryInMiddleIsRemovedWhole() {
        assertExtract(
            "見る https://example.com/a?b=c#top 後で",
            url: "https://example.com/a?b=c#top", title: "見る 後で")
    }
}
