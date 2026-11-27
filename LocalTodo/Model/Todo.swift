import Foundation

struct Todo: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var titleURL: URL?
    var links: [TodoLink]
    var descriptionText: String
    /// 期限日。年月日だけで、時刻は持たない（docs/adr/0008-due-date-without-time.md）。
    var dueDate: CalendarDay?
    var tags: [String]
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        titleURL: URL? = nil,
        links: [TodoLink] = [],
        descriptionText: String = "",
        dueDate: CalendarDay? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.titleURL = titleURL
        self.links = links
        self.descriptionText = descriptionText
        self.dueDate = dueDate
        self.tags = tags
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    /// `base` から `target` で変わった項目だけを、この Todo に当てた Todo を返す。
    /// 取り消し・やり直しで、あとから別の項目を直していても、その直しを巻き込まないために使う。
    func applying(_ target: Todo, changedFrom base: Todo) -> Todo {
        var result = self
        if target.title != base.title { result.title = target.title }
        if target.titleURL != base.titleURL { result.titleURL = target.titleURL }
        if target.links != base.links { result.links = target.links }
        if target.descriptionText != base.descriptionText { result.descriptionText = target.descriptionText }
        if target.dueDate != base.dueDate { result.dueDate = target.dueDate }
        if target.tags != base.tags { result.tags = target.tags }
        if target.completedAt != base.completedAt { result.completedAt = target.completedAt }
        return result
    }

    /// タイトルのリンクのうち、ブラウザに渡してよいもの（`http`・`https`）。
    /// 保存されていた値が別のスキームでも、開かない。
    var openableTitleURL: URL? {
        titleURL.flatMap { LinkTitleFetcher.isOpenable($0) ? $0 : nil }
    }

    /// 完了日時があればアーカイブ、なければ Inbox。
    var isArchived: Bool {
        completedAt != nil
    }

    /// 期限切れ（期限日が昨日以前）か。期限なしは期限切れにならない。完了しているかは見ない。
    func isPastDue(now: Date, calendar: Calendar) -> Bool {
        dueDate?.isPastDue(now: now, calendar: calendar) ?? false
    }

    /// 一覧の行に出す期限日。期限なしなら nil。
    func dueDateRowText(now: Date, calendar: Calendar) -> String? {
        dueDate?.rowText(now: now, calendar: calendar)
    }

    func dueHeading(now: Date, calendar: Calendar) -> DueHeading {
        dueDate?.heading(now: now, calendar: calendar) ?? .noDueDate
    }
}

// 期限日は JSON では {"date": "2026-11-25"} の形にする（ADR-0002 で決めた形を保つ）。
// 時刻を持っていたころの {"dateTime": "2026-11-25T06:00:00.000Z"} も読み、その日の日付にする。
// 読み替えに使うタイムゾーンは `JSONDecoder.userInfo[.dueDateCalendar]`、なければこの Mac の設定。
extension Todo {
    private enum CodingKeys: String, CodingKey {
        case id, title, titleURL, links, descriptionText, dueDate, tags, createdAt, completedAt
    }

    private enum DueDateKeys: String, CodingKey {
        case date
        case dateTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        titleURL = try container.decodeIfPresent(URL.self, forKey: .titleURL)
        links = try container.decode([TodoLink].self, forKey: .links)
        descriptionText = try container.decode(String.self, forKey: .descriptionText)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        dueDate = try Self.decodeDueDate(from: container, decoder: decoder)
    }

    private static func decodeDueDate(
        from container: KeyedDecodingContainer<CodingKeys>, decoder: Decoder
    ) throws -> CalendarDay? {
        guard container.contains(.dueDate), try !container.decodeNil(forKey: .dueDate) else { return nil }
        let dueDate = try container.nestedContainer(keyedBy: DueDateKeys.self, forKey: .dueDate)
        guard dueDate.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: dueDate.codingPath, debugDescription: "date か dateTime のどちらか1つが必要"))
        }
        if let day = try dueDate.decodeIfPresent(CalendarDay.self, forKey: .date) {
            return day
        }
        let calendar = decoder.userInfo[.dueDateCalendar] as? Calendar ?? .current
        return CalendarDay(try dueDate.decode(Date.self, forKey: .dateTime), calendar: calendar)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(titleURL, forKey: .titleURL)
        try container.encode(links, forKey: .links)
        try container.encode(descriptionText, forKey: .descriptionText)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        if let dueDate {
            var nested = container.nestedContainer(keyedBy: DueDateKeys.self, forKey: .dueDate)
            try nested.encode(dueDate, forKey: .date)
        }
    }
}

extension CodingUserInfoKey {
    /// 古い `{"dateTime": …}` の期限日を、どのタイムゾーンの日付にするか（`Calendar`）。
    static let dueDateCalendar = CodingUserInfoKey(rawValue: "dueDateCalendar")!
}

struct TodoLink: Codable, Identifiable, Hashable {
    let id: UUID
    var url: URL
    var displayName: String

    init(id: UUID = UUID(), url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
    }
}

/// 年・月・日だけを持つ、暦の上の1日。
struct CalendarDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    /// アプリの中では Date からだけ作り、ありえない日付（2/30 など）が生まれないようにする。
    /// JSON からの読み込みでは検査しない。1件の不正な日付のためにファイル全体を読めなくするより、
    /// 比較が少しずれるだけで読めるほうがよいため。JSON が壊れるのは手で書き換えたときだけである。
    ///
    /// 年月日は常にグレゴリオ暦で取り出し、渡されたカレンダーからはタイムゾーンだけを使う。
    /// 和暦のカレンダーのまま取り出すと、元号が変わるところで年が1に戻り、順序が逆になるため。
    init(_ date: Date, calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        year = gregorian.component(.year, from: date)
        month = gregorian.component(.month, from: date)
        day = gregorian.component(.day, from: date)
    }

    private init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// この日の、`calendar` のタイムゾーンでの 0:00。
    func date(calendar: Calendar) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = DateComponents(year: year, month: month, day: day)
        return gregorian.date(from: components) ?? .distantPast
    }

    /// `2026/1/5` の形。ゼロ埋めしない。詳細ペインの日付ボタンに使う。
    var label: String {
        "\(year)/\(month)/\(day)"
    }

    /// 一覧の行に出す期限日の書き方。今年なら年を省く（`1/5`）。
    func rowText(now: Date, calendar: Calendar) -> String {
        year == CalendarDay(now, calendar: calendar).year ? "\(month)/\(day)" : label
    }

    /// 期限日として、期限切れ（昨日以前）か。期限日の翌日 0:00 ちょうどから期限切れになる。
    func isPastDue(now: Date, calendar: Calendar) -> Bool {
        self < CalendarDay(now, calendar: calendar)
    }

    /// 期限日としての見出し。
    func heading(now: Date, calendar: Calendar) -> DueHeading {
        let today = CalendarDay(now, calendar: calendar)
        if self < today {
            return .beforeToday
        } else if self == today {
            return .today
        } else {
            return .afterToday
        }
    }
}

// JSON では "2026-11-25" の形にする。タイムゾーンを持たない暦の上の日付であることが、書き方から分かる。
extension CalendarDay {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        // 数字として読めるかだけを見る。日付として正しいか（2/30 など）は検査しない（init(_:calendar:) のコメント参照）。
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "YYYY-MM-DD の形ではない: \(text)")
        }
        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }
}

/// 期限日順の一覧の見出し。
/// 文字列の値は、見出しの開閉を `@AppStorage` に保存するときに使う。変えると保存した開閉が外れる。
enum DueHeading: String, CaseIterable {
    case beforeToday
    case today
    case afterToday
    case noDueDate

    var label: String {
        switch self {
        case .beforeToday: "期限切れ"
        case .today: "今日"
        case .afterToday: "明日以降"
        case .noDueDate: "期限なし"
        }
    }
}
