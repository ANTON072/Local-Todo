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
            }
            .listStyle(.inset)
        }
        .navigationTitle(kind.title)
        .onChange(of: kind) {
            selection = nil
        }
        .onAppear {
            isInputFocused = kind.showsNewTodoField
        }
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
