import SwiftUI

struct TodoListView: View {
    let store: TodoStore
    let kind: TodoListKind

    @State private var inputText = ""
    @State private var selection: Todo.ID?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if kind.showsNewTodoField {
                newTodoField
                    .padding(12)
            }
            List(kind.todos(in: store), selection: $selection) { todo in
                TodoRowView(todo: todo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(card(isSelected: todo.id == selection))
                    .background(SelectionHighlightRemover())
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Self.listBackground)
        }
        .navigationTitle(kind.title)
        .onChange(of: kind) {
            selection = nil
        }
        .onAppear {
            isInputFocused = kind.showsNewTodoField
        }
    }

    /// 行を1件ずつ浮かせるカード。上下にすき間を空けて、隣の行と区切る。
    /// 選んだ行は、カードにアクセントカラーを薄く重ね、縁を細く引く。塗りつぶすと色が強すぎるため
    /// （macOS の選択の背景は SelectionHighlightRemover で消している）。
    private func card(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return
            shape
            .fill(Self.cardBackground)
            .overlay {
                if isSelected {
                    shape.fill(Color.accentColor.opacity(0.12))
                    shape.strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
            .padding(.vertical, 3)
            .padding(.horizontal, 10)
    }

    /// カードの後ろのブルーグレー。カードより暗くして、カードを浮かせる。
    private static let listBackground = dynamicColor(
        light: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.97, alpha: 1),
        dark: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1))

    /// カードの色。ダークでは、システムのコントロールの背景色だと背景とほぼ同じ明るさになり
    /// カードが溶けるので、背景より一段明るいブルーグレーにする。
    private static let cardBackground = dynamicColor(
        light: .white,
        dark: NSColor(srgbRed: 0.17, green: 0.18, blue: 0.21, alpha: 1))

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }

    private var newTodoField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("新しい Todo（⌘Enter で追加）", text: $inputText)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                // Enter だけでは追加しない（日本語入力の変換確定で誤って登録しないため）
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command), !isComposingText else { return .ignored }
                    inputText = NewTodoInput.submit(inputText, to: store)
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isInputFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    /// 日本語入力で変換中（未確定の文字がある）か。変換中に追加すると、確定済みの部分だけが
    /// Todo になり、入力欄には未確定の文字が残ってしまうため、⌘Enter を受け付けない。
    private var isComposingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

/// List の土台の NSTableView を探し、macOS が描く選択の背景を消す。
/// 選択の背景がカードの外にはみ出し、白いカードの上で選択中の白い文字が見えなくなるため、
/// 選択はカードの色で表す。選択そのもの（クリック・↑↓）は List のまま使う。
private struct SelectionHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            var current = view.superview
            while let candidate = current {
                if let tableView = candidate as? NSTableView {
                    tableView.selectionHighlightStyle = .none
                    return
                }
                current = candidate.superview
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
