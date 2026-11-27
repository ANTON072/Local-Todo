import Foundation

/// `TagParser.parse` の結果。
struct ParsedTags: Equatable {
    /// 出てきた順のタグ名。`#` は含まない。書いたとおりの大文字・小文字で、重複も残す。
    /// 重複を消す・既存の書き方にそろえるのは、既存のタグを持つ側（`TodoStore`）の仕事。
    let names: [String]
    /// タグと、その直後の空白を取り除き、前後の空白を取ったタイトル。
    /// タグが1つもないときは、入力そのまま（前後の空白も取らない）。
    let title: String
    /// 入力の中の各タグの範囲（`#` を含む。`names` と同じ順）。
    /// `NSTextView` の入力中の強調で使うので、`NSRange`（UTF-16）で持つ。
    let ranges: [NSRange]
}

/// タイトル欄・タグ欄の両方で同じ規則でタグを読み取る、状態を持たない関数。
enum TagParser {
    /// `text` から `#タグ` を抜き出す。
    ///
    /// 規則：
    /// - `#` か `＃` で始まり、直前が文頭か空白（半角・全角・改行）のものをタグとする。
    ///   `C#` のように語の途中にある `#` はタグにしない。
    /// - タグ名は、空白・改行・文末までとする。句読点や括弧では終わらせない。
    ///   自分で打つタグは入力中の強調（`TaggedTextField`）で範囲が見えるので、「空白で区切る」
    ///   という単純な規則にした。`#C++` や `#2026-11` のような、記号を含むタグも作れる。
    /// - タグ名が空のもの（`# 牛乳`、文末の `#`）と、先頭が `#`／`＃` のもの（`##牛乳`）はタグにせず、
    ///   タイトルに残す。タグは `#` を付けずに保存して表示で `#` を付けるので、`#` を含む名前は
    ///   保存した名前と見た目が食い違うため。
    /// - URL の範囲（`NSDataDetector` で見つける）の中にある `#` は対象にしない（`https://example.com/#top`）。
    ///   `#` が範囲の外なら、タグ名が URL に重なってもタグにする。
    static func parse(_ text: String) -> ParsedTags {
        let source = text as NSString
        let urlRanges = urlRanges(in: text)

        var names: [String] = []
        var ranges: [NSRange] = []
        // タイトルから取り除く範囲。タグと、その直後の空白
        var removals: [NSRange] = []

        var index = 0
        while index < source.length {
            guard isTagMark(source.character(at: index)),
                !urlRanges.contains(where: { NSLocationInRange(index, $0) }),
                index == 0 || isWhitespace(source.character(at: index - 1))
            else {
                index += 1
                continue
            }
            var end = index + 1
            while end < source.length, !isWhitespace(source.character(at: end)) { end += 1 }
            let nameRange = NSRange(location: index + 1, length: end - index - 1)
            if nameRange.length == 0 || isTagMark(source.character(at: nameRange.location)) {
                index += 1
                continue
            }
            var removalEnd = end
            while removalEnd < source.length, isWhitespace(source.character(at: removalEnd)) { removalEnd += 1 }
            names.append(source.substring(with: nameRange))
            ranges.append(NSRange(location: index, length: end - index))
            removals.append(NSRange(location: index, length: removalEnd - index))
            index = end
        }

        guard !names.isEmpty else { return ParsedTags(names: [], title: text, ranges: []) }

        let rest = NSMutableString(string: text)
        for removal in removals.reversed() { rest.deleteCharacters(in: removal) }
        let title = (rest as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTags(names: names, title: title, ranges: ranges)
    }

    /// 2つのタグが同じか。半角の `A–Z`／`a–z` の大文字・小文字だけを区別しない。
    /// 全角の英字・アクセント付きの文字・ひらがなとカタカナは、別のものとして扱う。
    static func isSameTag(_ lhs: String, _ rhs: String) -> Bool {
        foldASCIICase(lhs) == foldASCIICase(rhs)
    }

    private static func foldASCIICase(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        // 合成済み（É）と分解済み（E + U+0301）で同じ文字でも、スカラーの並びが違う。
        // 先に NFC にそろえないと、分解済みの `E` だけが小文字になり、アクセント付きの大文字・小文字が
        // 別という規則や、Swift の文字列比較（正規等価なら等しい）と食い違う。
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value >= 0x41, scalar.value <= 0x5A, let lower = Unicode.Scalar(scalar.value + 0x20) {
                scalars.append(lower)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func urlRanges(in text: String) -> [NSRange] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        return detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
    }

    /// `#`（U+0023）か `＃`（U+FF03）。
    private static func isTagMark(_ character: unichar) -> Bool {
        character == 0x23 || character == 0xFF03
    }

    /// 半角・全角の空白と改行。
    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
