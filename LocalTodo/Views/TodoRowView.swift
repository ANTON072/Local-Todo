import SwiftUI

struct TodoRowView: View {
    let todo: Todo
    /// 見た目の上で完了か（保留中は、持っている状態と逆）。
    let isChecked: Bool
    /// 期限日の強調。Inbox の、まだ完了にしていない行だけに付ける（アーカイブと保留中には付けない）。
    var dueEmphasis: DueEmphasis = .none
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

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
                let dueText = todo.dueDateRowText(now: .now, calendar: .current)
                if dueText != nil || !todo.tags.isEmpty {
                    // 期限日のあとに、タグのチップを続ける。1行に収まらない分は右端で切る
                    // （折り返さないので、行の高さは1行か2行のどちらかになる）。
                    HStack(spacing: 6) {
                        if let dueText {
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
                        ForEach(todo.tags, id: \.self) { tag in
                            tagChip(tag)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// タグのカプセル型のチップ。背景はアクセントの 12%（ダークは 20%）透過、文字はアクセント。
    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12), in: Capsule())
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
