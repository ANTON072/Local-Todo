import XCTest

@testable import LocalTodo

/// タグの抽出と、タグの同一判定のテスト。`names` / `title` / `ranges` を確かめる。
final class TagParserTests: XCTestCase {
    private func assertParse(
        _ input: String, names: [String], title: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = TagParser.parse(input)
        XCTAssertEqual(result.names, names, file: file, line: line)
        XCTAssertEqual(result.title, title, file: file, line: line)
    }

    // MARK: - 抽出（Issue のケース）

    func testTagAtEnd() {
        assertParse("企画書を送る #仕事", names: ["仕事"], title: "企画書を送る")
    }

    func testTagAtEndRanges() {
        let result = TagParser.parse("企画書を送る #仕事")

        XCTAssertEqual(result.ranges, [NSRange(location: 7, length: 3)])
    }

    func testTagAtStart() {
        assertParse("#仕事 企画書", names: ["仕事"], title: "企画書")
    }

    func testTagInMiddle() {
        assertParse("資料 #仕事 確認", names: ["仕事"], title: "資料 確認")
    }

    func testTagAfterNewline() {
        assertParse("資料\n#仕事", names: ["仕事"], title: "資料")
    }

    func testMultipleTags() {
        assertParse("資料 #仕事 #急ぎ 確認", names: ["仕事", "急ぎ"], title: "資料 確認")
    }

    func testFullWidthHash() {
        assertParse("買い物 ＃牛乳", names: ["牛乳"], title: "買い物")
    }

    func testFullWidthSpaces() {
        assertParse("資料　#仕事　確認", names: ["仕事"], title: "資料　確認")
    }

    func testHashAfterLetterIsNotTag() {
        assertParse("C# を勉強", names: [], title: "C# を勉強")
    }

    func testHashInsideURLIsNotTag() {
        assertParse(
            "https://example.com/#top を読む #仕事", names: ["仕事"],
            title: "https://example.com/#top を読む")
    }

    func testTagNameOverlappingURLIsTag() {
        assertParse("メモ #example.com", names: ["example.com"], title: "メモ")
    }

    func testPunctuationDoesNotEndTagName() {
        assertParse("明日 #仕事、急ぎ", names: ["仕事、急ぎ"], title: "明日")
    }

    func testHashFollowedBySpaceIsNotTag() {
        assertParse("買い物 # 牛乳", names: [], title: "買い物 # 牛乳")
    }

    func testTrailingHashIsNotTag() {
        assertParse("買い物 #", names: [], title: "買い物 #")
    }

    func testDoubleHashIsNotTag() {
        assertParse("買い物 ##牛乳", names: [], title: "買い物 ##牛乳")
    }

    func testDuplicateTagsAreKept() {
        assertParse("#Work #work", names: ["Work", "work"], title: "")
    }

    func testEmptyInput() {
        assertParse("", names: [], title: "")
    }

    // MARK: - isSameTag（Issue のケース）

    func testIsSameTagIgnoresAsciiCase() {
        XCTAssertTrue(TagParser.isSameTag("Work", "work"))
    }

    func testIsSameTagDistinguishesAccentedCase() {
        XCTAssertFalse(TagParser.isSameTag("CAFÉ", "café"))
    }

    func testIsSameTagDistinguishesFullWidthFromHalfWidth() {
        XCTAssertFalse(TagParser.isSameTag("ＡＢＣ", "ABC"))
    }

    func testIsSameTagDistinguishesFullWidthCase() {
        XCTAssertFalse(TagParser.isSameTag("ＡＢＣ", "ａｂｃ"))
    }

    func testIsSameTagDistinguishesHiraganaFromKatakana() {
        XCTAssertFalse(TagParser.isSameTag("ひらがな", "ヒラガナ"))
    }

    // MARK: - 追加のケース

    func testRangesOfMultipleTagsInOrder() {
        let result = TagParser.parse("資料 #仕事 #急ぎ 確認")

        XCTAssertEqual(
            result.ranges, [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
    }

    func testRangeOfFullWidthHashIncludesHash() {
        let result = TagParser.parse("買い物 ＃牛乳")

        XCTAssertEqual(result.ranges, [NSRange(location: 4, length: 3)])
    }

    func testRangesEmptyWhenNoTag() {
        XCTAssertEqual(TagParser.parse("買い物 #").ranges, [])
    }

    func testTagNamePreservesCase() {
        assertParse("メモ #WoRk", names: ["WoRk"], title: "メモ")
    }

    func testTagOnlyInputGivesEmptyTitle() {
        assertParse("#仕事", names: ["仕事"], title: "")
    }

    func testConsecutiveSpacesAfterTagAreAllRemoved() {
        assertParse("資料 #仕事    確認", names: ["仕事"], title: "資料 確認")
    }

    func testNewlinesAfterTagAreRemoved() {
        assertParse("#仕事\n\n確認", names: ["仕事"], title: "確認")
    }

    func testTagEndsAtNewline() {
        assertParse("#仕事\n確認", names: ["仕事"], title: "確認")
    }

    func testTagEndsAtFullWidthSpace() {
        assertParse("#仕事　確認", names: ["仕事"], title: "確認")
    }

    func testTitleIsTrimmedWhenTagExists() {
        assertParse("  資料 #仕事  ", names: ["仕事"], title: "資料")
    }

    func testTitleIsNotTrimmedWhenNoTag() {
        assertParse("  資料 C# \n", names: [], title: "  資料 C# \n")
    }

    func testPlainTextWithoutHashIsUnchanged() {
        assertParse(" 牛乳を買う ", names: [], title: " 牛乳を買う ")
    }

    func testHashInsideWordIsNotTag() {
        assertParse("abc#def", names: [], title: "abc#def")
    }

    func testHashInsideTagNameStaysInName() {
        assertParse("メモ #a#b", names: ["a#b"], title: "メモ")
    }

    func testFullWidthDoubleHashIsNotTag() {
        assertParse("買い物 ＃＃牛乳", names: [], title: "買い物 ＃＃牛乳")
    }

    func testMixedDoubleHashIsNotTag() {
        assertParse("買い物 #＃牛乳", names: [], title: "買い物 #＃牛乳")
    }

    func testFullWidthHashFollowedBySpaceIsNotTag() {
        assertParse("買い物 ＃ 牛乳", names: [], title: "買い物 ＃ 牛乳")
    }

    func testHashFollowedByNewlineIsNotTag() {
        assertParse("買い物 #\n牛乳", names: [], title: "買い物 #\n牛乳")
    }

    func testInvalidHashStaysInTitleWhenValidTagFollows() {
        assertParse("# 牛乳 #仕事", names: ["仕事"], title: "# 牛乳")
    }

    func testRangeOfTagAfterURLWithHash() {
        let result = TagParser.parse("https://example.com/#top #仕事")

        XCTAssertEqual(result.names, ["仕事"])
        XCTAssertEqual(result.ranges, [NSRange(location: 25, length: 3)])
    }

    func testIsSameTagIdenticalStrings() {
        XCTAssertTrue(TagParser.isSameTag("仕事", "仕事"))
    }

    func testIsSameTagDifferentStrings() {
        XCTAssertFalse(TagParser.isSameTag("仕事", "私用"))
    }

    func testIsSameTagIgnoresCaseWithinMixedString() {
        XCTAssertTrue(TagParser.isSameTag("仕事Work", "仕事WORK"))
    }

    func testIsSameTagBothEmpty() {
        XCTAssertTrue(TagParser.isSameTag("", ""))
    }
}
