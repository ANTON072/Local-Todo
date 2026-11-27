import SwiftUI

struct TodoListView: View {
    let store: TodoStore
    let undoRouter: UndoRouter
    let kind: TodoListKind
    /// Inbox の並び順。アーカイブでは使わない。
    let sortOrder: InboxSortOrder

    @Binding var selection: Todo.ID?

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    /// 畳んでいる見出し。`DueHeading` の文字列をカンマでつないで保存し、次の起動でも保つ。
    @AppStorage("collapsedDueHeadings") private var collapsedRaw = ""

    var body: some View {
        VStack(spacing: 0) {
            if kind.showsNewTodoField {
                newTodoField
                    .padding(12)
            }
            List(selection: $selection) {
                if showsHeadings {
                    ForEach(store.inboxSections(now: .now)) { section in
                        Section {
                            if !collapsedHeadings.contains(section.heading) {
                                ForEach(section.todos) { todo in row(todo) }
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                } else {
                    ForEach(kind.todos(in: store, order: sortOrder)) { todo in row(todo) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Self.listBackground)
            // 入力欄にフォーカスがあるときは、入力欄の標準の ⌘⌫（行頭まで消す）のままにするため、一覧のキー入力で受ける
            .onKeyPress(.delete, phases: .down) { press in
                guard press.modifiers.contains(.command), kind == .inbox, let selection else { return .ignored }
                store.delete(id: selection)
                return .handled
            }
        }
        .navigationTitle(kind.title)
        .onChange(of: kind) {
            selection = nil
        }
        // 確定でこの一覧から消えた行を選んでいたら、選択を外す
        .onChange(of: kind.todos(in: store, order: sortOrder).map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        // 操作の結果で Todo が畳んだ見出しに入った（追加・期限日の変更・取り消し・やり直しなど）ときは、
        // その見出しを開いて、行が隠れないようにする。畳むのはユーザー自身の操作のときだけ。
        .onChange(of: headingSnapshot) { old, new in
            guard old.isInbox, new.isInbox else { return }
            var opened = collapsedHeadings
            for (id, heading) in new.headings where old.headings[id] != heading {
                opened.remove(heading)
            }
            collapsedHeadings = opened
        }
        // 作成日順で選んだ Todo が、期限日順に戻したとき畳んだ見出しに入ると、行が隠れたまま
        // 詳細ペインで編集できてしまう。畳んだとき（toggleCollapsed）と同じく、選択を外す。
        .onChange(of: sortOrder) {
            guard showsHeadings, let selection else { return }
            let hidden = store.inboxSections(now: .now).contains { section in
                collapsedHeadings.contains(section.heading) && section.todos.contains { $0.id == selection }
            }
            if hidden { self.selection = nil }
        }
        .onAppear {
            isInputFocused = kind.showsNewTodoField
        }
        // 新規入力欄が空でフォーカスされているあいだ、⌘Z は TodoStore の取り消しに渡す（UndoRouter）
        .onChange(of: isInputFocused) { updateRouter() }
        .onChange(of: inputText) { updateRouter() }
    }

    /// 見出しは、Inbox を期限日順で並べているときだけ出す。
    private var showsHeadings: Bool {
        kind == .inbox && sortOrder == .dueDate
    }

    private func row(_ todo: Todo) -> some View {
        let isChecked = store.isShownCompleted(id: todo.id)
        let emphasis = dueEmphasis(of: todo, isChecked: isChecked)
        return TodoRowView(
            todo: todo, isChecked: isChecked, dueEmphasis: emphasis,
            onToggle: { store.toggleCompletion(id: todo.id) }
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listRowBackground(card(isSelected: todo.id == selection, showsPastDueBar: emphasis == .pastDue))
        .background(SelectionHighlightRemover())
        // ダブルクリックでリンクを開く。単なるクリック（選択）の邪魔をしないよう、同時に受ける。
        // ⌘クリックは複数選択に使うので、リンクを開く操作には使わない
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if let url = todo.openableTitleURL { NSWorkspace.shared.open(url) }
            }
        )
        .contextMenu {
            // 右クリックした行だけを削除する（選択は変えない）
            if kind == .inbox {
                Button("削除", role: .destructive) { store.delete(id: todo.id) }
            }
        }
    }

    /// 期限の強調は Inbox の行だけ。完了にした行（保留中を含む）には付けない。
    private func dueEmphasis(of todo: Todo, isChecked: Bool) -> TodoRowView.DueEmphasis {
        guard kind == .inbox, !isChecked else { return .none }
        return TodoRowView.DueEmphasis(heading: todo.dueHeading(now: .now, calendar: store.calendar))
    }

    /// 見出し。左の矢印と見出しをクリックすると、畳む・開くを切り替える。横に、いま出ている行の数を出す。
    private func sectionHeader(_ section: DueSection) -> some View {
        let isCollapsed = collapsedHeadings.contains(section.heading)
        return Button {
            toggleCollapsed(section)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
                Text(section.heading.label)
                    .font(.subheadline.weight(.semibold))
                Text("\(section.todos.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.heading.label)、\(section.todos.count)件、\(isCollapsed ? "畳んでいる" : "開いている")")
    }

    /// 畳むとき、その見出しの中に選択中の Todo があれば選択を外す（隠れた行を詳細ペインで編集させないため）。
    private func toggleCollapsed(_ section: DueSection) {
        var collapsed = collapsedHeadings
        if collapsed.contains(section.heading) {
            collapsed.remove(section.heading)
        } else {
            collapsed.insert(section.heading)
            if let selection, section.todos.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        }
        collapsedHeadings = collapsed
    }

    private var collapsedHeadings: Set<DueHeading> {
        get { Set(collapsedRaw.split(separator: ",").compactMap { DueHeading(rawValue: String($0)) }) }
        nonmutating set {
            collapsedRaw = DueHeading.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: ",")
        }
    }

    /// どの Todo がどの見出しにいるか。見出しの移り変わりを見つけるために使う。
    private struct HeadingSnapshot: Equatable {
        let isInbox: Bool
        let headings: [Todo.ID: DueHeading]
    }

    private var headingSnapshot: HeadingSnapshot {
        guard showsHeadings else { return HeadingSnapshot(isInbox: false, headings: [:]) }
        var headings: [Todo.ID: DueHeading] = [:]
        for section in store.inboxSections(now: .now) {
            for todo in section.todos { headings[todo.id] = section.heading }
        }
        return HeadingSnapshot(isInbox: true, headings: headings)
    }

    /// 行を1件ずつ浮かせるカード。上下にすき間を空けて、隣の行と区切る。
    /// 選んだ行は、カードにアクセントカラーを薄く重ね、縁を細く引く。塗りつぶすと色が強すぎるため
    /// （macOS の選択の背景は SelectionHighlightRemover で消している）。
    /// 期限切れの行は、左端に赤い細いバーを付ける。
    private func card(isSelected: Bool, showsPastDueBar: Bool) -> some View {
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
            .overlay(alignment: .leading) {
                if showsPastDueBar {
                    Rectangle().fill(Color.red).frame(width: 3)
                }
            }
            // バーがカードの丸い角からはみ出さないよう、重ねたものまとめてカードの形で切る
            .clipShape(shape)
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

    private func updateRouter() {
        undoRouter.isNewTodoFieldEmptyAndFocused = isInputFocused && inputText.isEmpty
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
