import SwiftUI

struct TodoRowView: View {
    let todo: Todo
    /// 見た目の上で完了か（保留中は、持っている状態と逆）。
    let isChecked: Bool
    let onToggle: () -> Void

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
                    Text(dueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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
