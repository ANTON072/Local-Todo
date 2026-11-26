import SwiftUI

/// 期限日を選ぶ、月表示のカレンダー。日をクリックしたときだけ `onPick` を呼ぶ。
///
/// 標準の `DatePicker`（`.graphical`）は、すでに選ばれている日をクリックしても値が変わらないので知らせが来ず、
/// 月を送る矢印でも値が変わってしまう。「開いたときに選ばれている今日をクリックして期限にする」ができないため、自前で作る。
struct MonthCalendar: View {
    /// 開いたときに選ばれている日。期限があればその日、なければ今日。
    let selected: CalendarDay
    let today: CalendarDay
    let calendar: Calendar
    let onPick: (CalendarDay) -> Void

    /// 表示している月の1日。
    @State private var month: Date

    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    init(selected: CalendarDay, today: CalendarDay, calendar: Calendar, onPick: @escaping (CalendarDay) -> Void) {
        self.selected = selected
        self.today = today
        self.calendar = calendar
        self.onPick = onPick
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let first = gregorian.date(from: DateComponents(year: selected.year, month: selected.month, day: 1))
        _month = State(initialValue: first ?? selected.date(calendar: calendar))
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                    }
                }
                ForEach(weeks.indices, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            if let day = weeks[week][weekday] {
                                dayButton(day)
                            } else {
                                Color.clear.frame(width: 28, height: 28)
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(verbatim: "\(gregorian.component(.year, from: month))年\(gregorian.component(.month, from: month))月")
                .font(.headline)
            Spacer()
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("前の月")
            .accessibilityLabel("前の月")
            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("次の月")
            .accessibilityLabel("次の月")
        }
        .buttonStyle(.borderless)
    }

    /// 選ばれている日は紫の丸に白い文字、今日は紫の文字にする。
    private func dayButton(_ day: CalendarDay) -> some View {
        let isSelected = day == selected
        return Button {
            onPick(day)
        } label: {
            Text(verbatim: "\(day.day)")
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? Color.white : day == today ? Color.accentColor : Color.primary)
                .background {
                    if isSelected { Circle().fill(Color.accentColor) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.label)
    }

    /// 表示している月を、週ごとに7日ずつ並べる。月の外の日は nil。週は日曜から始める。
    private var weeks: [[CalendarDay?]] {
        let firstWeekday = gregorian.component(.weekday, from: month)  // 1 が日曜
        let dayCount = gregorian.range(of: .day, in: .month, for: month)?.count ?? 0
        var cells: [CalendarDay?] = Array(repeating: nil, count: firstWeekday - 1)
        for offset in 0..<dayCount {
            let date = gregorian.date(byAdding: .day, value: offset, to: month) ?? month
            cells.append(CalendarDay(date, calendar: calendar))
        }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private func moveMonth(by value: Int) {
        let first = gregorian.date(from: gregorian.dateComponents([.year, .month], from: month)) ?? month
        month = gregorian.date(byAdding: .month, value: value, to: first) ?? month
    }

    /// 年月日は CalendarDay と同じく、グレゴリオ暦で渡されたカレンダーのタイムゾーンで数える。
    private var gregorian: Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}
