import SwiftUI

/// 選んだ Todo を編集するフォーム。保存ボタンはなく、変更は自動で保存する。
///
/// 選んだ Todo が変わるたびに作り直す（呼ぶ側で `.id(todoID)` を付ける）。
/// 作り直すとき、古い側の `onDisappear` で打ちかけのタイトルを確定するので、
/// 確定した変更は元の Todo に入り、新しく選んだ Todo には入らない。
struct TodoDetailView: View {
    let store: TodoStore
    let todoID: Todo.ID

    var body: some View {
        if let todo = store.todos.first(where: { $0.id == todoID }) {
            TodoForm(store: store, todo: todo)
        } else {
            DetailPlaceholder()
        }
    }
}

/// 何も選んでいないとき（と、選択中の Todo が消えたとき）の表示。
struct DetailPlaceholder: View {
    var body: some View {
        Text("Todo を選択してください")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TodoForm: View {
    let store: TodoStore
    let todo: Todo

    @State private var titleDraft: String
    @FocusState private var isTitleFocused: Bool

    init(store: TodoStore, todo: Todo) {
        self.store = store
        self.todo = todo
        _titleDraft = State(initialValue: todo.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("タイトル") { titleField }
            field("期限日") { DueDateField(store: store, todo: todo) }
            field("ディスクリプション", fillsHeight: true) { descriptionField }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 取り消し・やり直しでタイトルが変わったとき、打っていなければ欄の表示も合わせる
        .onChange(of: todo.title) {
            if !isTitleFocused { titleDraft = todo.title }
        }
        // 一覧で別の Todo を選んだとき、詳細ペインを隠したときも、フォーカスが外れたとみなして確定する
        .onDisappear { commitTitle() }
        // ⌘Q で終了するときは onDisappear もフォーカスの変化も確実には起きない。
        // App 側の終了時の保存（saveNow）と通知を受ける順が決まっていないので、確定したあと自分でも書き切る
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            commitTitle()
            store.saveNow()
        }
    }

    private func field<Content: View>(
        _ label: String, fillsHeight: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
    }

    // 長いタイトルは折り返して全体を見せる（一覧の行は「…」で切っている）。
    // #19 で TaggedTextField に置き換えるまでのつなぎ。
    private var titleField: some View {
        TextField("", text: $titleDraft, axis: .vertical)
            .textFieldStyle(.plain)
            .focused($isTitleFocused)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isTitleFocused ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .onChange(of: isTitleFocused) {
                if !isTitleFocused { commitTitle() }
            }
            // Enter だけでは何もしない（改行も入れない）。日本語入力の変換確定と区別するため。
            // 変換中は、確定の Enter を入力欄に渡す
            .onKeyPress(.return, phases: .down) { press in
                guard !isComposingText else { return .ignored }
                if press.modifiers.contains(.command) { commitTitle() }
                return .handled
            }
            .onKeyPress(.escape, phases: .down) { _ in
                guard !isComposingText else { return .ignored }
                titleDraft = todo.title
                return .handled
            }
    }

    private var descriptionField: some View {
        TextEditor(text: descriptionBinding)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if todo.descriptionText.isEmpty {
                    Text("ディスクリプションを追加")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
            }
    }

    /// 1文字打つたびに store へ入れる。手は加えない。ファイルへの書き込みは store が待ってまとめる。
    private var descriptionBinding: Binding<String> {
        Binding(
            get: { todo.descriptionText },
            set: { newValue in
                var updated = todo
                updated.descriptionText = newValue
                // 打鍵は入力欄の標準の取り消しに任せ、取り消しの履歴には載せない
                store.update(updated, registersUndo: false)
            }
        )
    }

    /// 確定した結果（整えたあとの文字列）を欄に戻す。空で確定できなかったときは元のタイトルに戻る。
    private func commitTitle() {
        titleDraft = store.commitTitle(id: todo.id, text: titleDraft)
    }

    /// 日本語入力で変換中（未確定の文字がある）か。変換中の Enter・Esc は、入力欄に任せる。
    private var isComposingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

/// 期限日の欄。期限なしなら「期限日を追加」だけ、期限があれば日付ボタンと × を並べる。
/// 「今日」ボタンは置かない。カレンダーは今日を選んだ状態で開くので、今日はそのままクリックすればよい。
private struct DueDateField: View {
    let store: TodoStore
    let todo: Todo

    @State private var isCalendarShown = false

    var body: some View {
        HStack(spacing: 8) {
            if let dueDate = todo.dueDate {
                Button(dueDate.label) { isCalendarShown = true }
                    .popover(isPresented: $isCalendarShown, arrowEdge: .bottom) { calendarPopover }
                Spacer(minLength: 0)
                Button {
                    store.removeDueDate(id: todo.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("期限日を外す")
                .accessibilityLabel("期限日を外す")
            } else {
                Button("期限日を追加") { isCalendarShown = true }
                    .popover(isPresented: $isCalendarShown, arrowEdge: .bottom) { calendarPopover }
                Spacer(minLength: 0)
            }
        }
    }

    /// 開くたびに作り直されるので、選ばれた日は、期限があればその日、なければ今日になる。
    private var calendarPopover: some View {
        let today = CalendarDay(.now, calendar: store.calendar)
        return MonthCalendar(selected: todo.dueDate ?? today, today: today, calendar: store.calendar) { day in
            store.setDueDay(id: todo.id, day: day)
            isCalendarShown = false
        }
        .padding(12)
    }
}
