import Foundation

/// タイトルの URL の判定と抜き出し（状態を持たない関数）。ページタイトルの取得は #23 で足す。
enum LinkTitleFetcher {
    /// タイトルから抜き出した URL と、そのあとのタイトル。
    struct ExtractedLink: Equatable {
        /// 抜き出した URL。URL がなければ nil。
        let url: URL?
        let title: String
    }

    /// タイトルの中の最初の URL を抜き出す。URL がなければ、`url` は nil で、`title` は入力そのまま。
    ///
    /// - タイトル全体が URL のときは、`title` も URL のまま（#23 でページのタイトルに置き換える）。
    /// - 一部が URL のときは、その URL と直後の空白（連続する分すべて。改行も含む）を取り除き、
    ///   前後の空白を取ったものを `title` にする。2つ目以降の URL は文字として残す
    ///   （タイトルのリンクは1件に1つまで。残しておけば、あとから追加リンクに写せる）。
    static func extract(from text: String) -> ExtractedLink {
        let source = text as NSString
        guard let match = webLinks(in: text).first else { return ExtractedLink(url: nil, title: text) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (source.substring(with: match.range)) == trimmed {
            return ExtractedLink(url: match.url, title: trimmed)
        }

        var end = match.range.location + match.range.length
        while end < source.length, isWhitespace(source.character(at: end)) { end += 1 }
        let rest = NSMutableString(string: text)
        rest.deleteCharacters(in: NSRange(location: match.range.location, length: end - match.range.location))
        return ExtractedLink(url: match.url, title: (rest as String).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 詳細ペインのリンク欄に書かれた文字列を URL にする。
    /// 前後の空白を除いた全体が1つの `http(s)://` の URL のときだけ URL を返し、
    /// それ以外（スキームなし・`ftp`・文字が混ざる）は nil。
    static func parseLinkField(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = webLinks(in: trimmed).first,
            (trimmed as NSString).substring(with: match.range) == trimmed
        else { return nil }
        return match.url
    }

    /// ブラウザに渡してよい URL か。`file:` や `mailto:` を開くと、ファイルやメールアプリが起動してしまうので、
    /// 保存されていた値が別のスキームでも開かないように、開く直前にも確かめる。
    static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// URL とみなすのは、書かれた文字が `http://` か `https://` で始まるものだけ。
    /// `NSDataDetector` は `example.com` のようなドメインだけの文字、メール、`ftp`・`file`・`tel` も
    /// 検出するが、`main.rs` のようなファイル名らしい文字列をリンクにしたり、`file:` を開いたりしないため、
    /// スキームを書いたものに限る。
    private static func webLinks(in text: String) -> [(range: NSRange, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let source = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard let url = match.url, isOpenable(url) else { return nil }
            let written = source.substring(with: match.range).lowercased()
            guard written.hasPrefix("http://") || written.hasPrefix("https://") else { return nil }
            return (match.range, url)
        }
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
