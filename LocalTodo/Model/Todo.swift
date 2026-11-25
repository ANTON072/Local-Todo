import Foundation

struct Todo: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var titleURL: URL?
    var links: [TodoLink]
    var descriptionText: String
    var dueDate: DueDate?
    var tags: [String]
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        titleURL: URL? = nil,
        links: [TodoLink] = [],
        descriptionText: String = "",
        dueDate: DueDate? = nil,
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

    /// 完了日時があればアーカイブ、なければ Inbox。
    var isArchived: Bool {
        completedAt != nil
    }

    /// 期限なしは期限超過にならない。完了しているかは見ない。
    func isOverdue(now: Date, calendar: Calendar) -> Bool {
        dueDate?.isOverdue(now: now, calendar: calendar) ?? false
    }

    func dueHeading(now: Date, calendar: Calendar) -> DueHeading {
        dueDate?.heading(now: now, calendar: calendar) ?? .noDueDate
    }
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

/// 期限日。日付だけの期限は暦の上の1日として持つ（理由は docs/adr/0002-due-date-as-enum.md）。
enum DueDate: Codable, Hashable {
    /// 日付だけ。その日が終わったら期限超過になる。
    case date(CalendarDay)
    /// 時刻つき。時刻を過ぎたら期限超過になる。
    case dateTime(Date)

    func isOverdue(now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .date(let day):
            // 翌日 0:00 ちょうどから期限超過
            CalendarDay(now, calendar: calendar) > day
        case .dateTime(let date):
            // 時刻ちょうどはまだ期限内
            now > date
        }
    }

    /// 時刻つきでも見出しは期限日で決める。今日が期限で時刻を過ぎたものは「今日」に残る。
    func heading(now: Date, calendar: Calendar) -> DueHeading {
        let today = CalendarDay(now, calendar: calendar)
        let dueDay = day(calendar: calendar)
        if dueDay < today {
            return .beforeToday
        } else if dueDay == today {
            return .today
        } else {
            return .afterToday
        }
    }

    private func day(calendar: Calendar) -> CalendarDay {
        switch self {
        case .date(let day):
            day
        case .dateTime(let date):
            CalendarDay(date, calendar: calendar)
        }
    }
}

// JSON では {"date": "2026-11-25"} か {"dateTime": "2026-11-25T06:00:00.000Z"} の形にする。
// 自動のエンコードだと {"date": {"_0": {...}}} のように読みにくくなるため。
extension DueDate {
    private enum CodingKeys: String, CodingKey {
        case date
        case dateTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: "date か dateTime のどちらか1つが必要"))
        }
        if let day = try container.decodeIfPresent(CalendarDay.self, forKey: .date) {
            self = .date(day)
        } else {
            self = .dateTime(try container.decode(Date.self, forKey: .dateTime))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .date(let day):
            try container.encode(day, forKey: .date)
        case .dateTime(let date):
            try container.encode(date, forKey: .dateTime)
        }
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
enum DueHeading: CaseIterable {
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
