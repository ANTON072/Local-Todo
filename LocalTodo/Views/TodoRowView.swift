import SwiftUI

struct TodoRowView: View {
    let todo: Todo
    /// 見た目の上で完了か（保留中は、持っている状態と逆）。
    let isChecked: Bool
    /// 期限日の強調。Inbox の、まだ完了にしていない行だけに付ける（アーカイブと保留中には付けない）。
    var dueEmphasis: DueEmphasis = .none
    let onToggle: () -> Void

    /// 期限日の強調の種類。見出しの「期限切れ」「今日」に対応する。
    enum DueEmphasis {
        case none
        case pastDue
        case today

        init(heading: DueHeading) {
            switch heading {
            case .beforeToday: self = .pastDue
            case .today: self = .today
            case .afterToday, .noDueDate: self = .none
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                checkbox
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isChecked ? "未完了に戻す" : "完了にする")
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(isChecked)
                    .foregroundStyle(isChecked ? .secondary : .primary)
                if let dueText = todo.dueDateRowText(now: .now, calendar: .current) {
                    // 年をまたいだら書き方が変わるが、一覧は日付が変わるたびに描き直さないので、
                    // 年越しの瞬間だけ古い書き方が残る。次に描き直されたときに直る
                    HStack(spacing: 3) {
                        if dueEmphasis == .pastDue {
                            Image(systemName: "exclamationmark.circle.fill")
                        }
                        Text(dueText)
                    }
                    .font(.caption)
                    .foregroundStyle(dueStyle)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dueStyle: Color {
        switch dueEmphasis {
        case .none: .secondary
        case .pastDue: .red
        case .today: .orange
        }
    }

    /// 完了は紫の塗りつぶし丸に白いチェック、未完了は空の丸。
    private var checkbox: some View {
        ZStack {
            if isChecked {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
    }
}
