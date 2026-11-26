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

    /// 完了日時があればアーカイブ、なければ Inbox。
    var isArchived: Bool {
        completedAt != nil
    }

    /// 期限なしは期限超過にならない。完了しているかは見ない。
    func isOverdue(now: Date, calendar: Calendar) -> Bool {
        dueDate?.isOverdue(now: now, calendar: calendar) ?? false
    }

    /// 一覧の行に出す期限日。期限なしなら nil。
    func dueDateRowText(now: Date, calendar: Calendar) -> String? {
        dueDate?.rowText(now: now, calendar: calendar)
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

    func day(calendar: Calendar) -> CalendarDay {
        switch self {
        case .date(let day):
            day
        case .dateTime(let date):
            CalendarDay(date, calendar: calendar)
        }
    }

    var hasTime: Bool {
        if case .dateTime = self { true } else { false }
    }

    /// 時刻を付けるときに入れる時刻。
    static let defaultTime = (hour: 9, minute: 0)

    /// カレンダーで `day` を選んだときの期限日。時刻つきなら時・分はそのままにして、日付だけを変える。
    /// 期限なし（`current` が nil）なら日付だけの期限にする。
    static func selecting(_ day: CalendarDay, keeping current: DueDate?, calendar: Calendar) -> DueDate {
        guard case .dateTime(let time) = current else { return .date(day) }
        let parts = gregorian(calendar).dateComponents([.hour, .minute], from: time)
        return .dateTime(day.date(hour: parts.hour ?? 0, minute: parts.minute ?? 0, calendar: calendar))
    }

    /// 時刻を付けた期限日。前に付けていた時刻は覚えず、いつも `defaultTime` にする。時刻つきならそのまま。
    func withTime(calendar: Calendar) -> DueDate {
        guard case .date = self else { return self }
        return changingTime(hour: Self.defaultTime.hour, minute: Self.defaultTime.minute, calendar: calendar)
    }

    /// 時刻を外した、その日の日付だけの期限日。
    func withoutTime(calendar: Calendar) -> DueDate {
        .date(day(calendar: calendar))
    }

    /// 時刻を `hour`:`minute` に変えた期限日。日付は変えない。日付だけの期限なら時刻つきにする。
    func changingTime(hour: Int, minute: Int, calendar: Calendar) -> DueDate {
        .dateTime(day(calendar: calendar).date(hour: hour, minute: minute, calendar: calendar))
    }

    /// 一覧の行に出す書き方。今年なら年を省く。月・日・時はゼロ埋めしない（`1/5 9:05`）。
    func rowText(now: Date, calendar: Calendar) -> String {
        let dueDay = day(calendar: calendar)
        let thisYear = CalendarDay(now, calendar: calendar).year
        let dayText = dueDay.year == thisYear ? "\(dueDay.month)/\(dueDay.day)" : dueDay.label
        return timeLabel(calendar: calendar).map { "\(dayText) \($0)" } ?? dayText
    }

    /// 詳細ペインの日付ボタンに出す書き方。いつも年を付け、時刻は書かない（`2026/1/5`）。
    func buttonText(calendar: Calendar) -> String {
        day(calendar: calendar).label
    }

    private func timeLabel(calendar: Calendar) -> String? {
        guard case .dateTime(let date) = self else { return nil }
        let parts = Self.gregorian(calendar).dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 時・分も、CalendarDay と同じくグレゴリオ暦で、渡されたカレンダーのタイムゾーンで取り出す。
    private static func gregorian(_ calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
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

    /// この日の、`calendar` のタイムゾーンでの `hour`:`minute`。
    func date(hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return gregorian.date(from: components) ?? .distantPast
    }

    /// `2026/1/5` の形。ゼロ埋めしない。
    var label: String {
        "\(year)/\(month)/\(day)"
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
