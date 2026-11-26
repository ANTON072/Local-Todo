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
            Text(todo.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? .secondary : .primary)
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
