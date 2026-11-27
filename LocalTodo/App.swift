import SwiftUI

@main
struct LocalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: TodoStore
    @State private var undoRouter = UndoRouter()
    @AppStorage(DetailPane.storageKey) private var showsDetailPane = true

    init() {
        let directory: URL
        do {
            directory = try Persistence.applicationSupportDirectory()
        } catch {
            // 保存先がなければ、何を追加しても残らない。黙って動き続けるより、理由を残して落とす
            fatalError("保存先のフォルダ（Application Support）を用意できない: \(error)")
        }
        let store = TodoStore(persistence: Persistence(directory: directory))
        _store = State(initialValue: store)
        // 予約中の保存（0.5 秒待ち）を待たずに、終了前に書き切る。
        // ウィンドウを閉じると終了するので、ビューではなくここで受ける（ビューは先に消えている）
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            store.saveNow()
        }
    }

    var body: some Scene {
        // WindowGroup ではなく Window にして、ウィンドウを1つに限る（「新規ウィンドウ」も出ない）
        Window("LocalTodo", id: "main") {
            ContentView(store: store, undoRouter: undoRouter)
        }
        .commands {
            // 入力欄にフォーカスがあるあいだは入力欄の取り消しに任せ、それ以外は TodoStore の取り消しにつなぐ
            CommandGroup(replacing: .undoRedo) {
                Button(undoTitle) {
                    if undoRouter.routesToStore { store.undo() } else { undoRouter.sendToTextField(undo: true) }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canUndo)
                Button(redoTitle) {
                    if undoRouter.routesToStore { store.redo() } else { undoRouter.sendToTextField(undo: false) }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canRedo)
            }
            CommandGroup(after: .sidebar) {
                Button(showsDetailPane ? "詳細ペインを隠す" : "詳細ペインを表示") {
                    showsDetailPane.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

extension LocalTodoApp {
    // 保留中のものは、取り消し・やり直しの前に確定されて取り消せるので、履歴が空でも取り消せる
    private var canUndo: Bool {
        undoRouter.routesToStore
            ? store.canUndo || !store.pendingToggles.isEmpty : undoRouter.textCanUndo
    }

    // 保留中にやり直すと、先に確定した完了が新しい操作になり、やり直しの履歴が消えるので、やり直せない
    private var canRedo: Bool {
        undoRouter.routesToStore ? store.canRedo && store.pendingToggles.isEmpty : undoRouter.textCanRedo
    }

    /// 保留中は、取り消すと先に確定されるので、その名前を出す（履歴の先頭の操作ではない）。
    private var undoTitle: String {
        guard undoRouter.routesToStore else { return "取り消す" }
        let name = store.pendingToggles.isEmpty ? store.undoActionName : store.pendingActionName
        return name.isEmpty ? "取り消す" : "\(name)を取り消す"
    }

    private var redoTitle: String {
        guard undoRouter.routesToStore, store.canRedo, store.pendingToggles.isEmpty, !store.redoActionName.isEmpty
        else { return "やり直す" }
        return "\(store.redoActionName)をやり直す"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ウィンドウが1つだけなので、閉じたらアプリも終了する
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum DetailPane {
    /// 詳細ペインの表示／非表示を `@AppStorage` で保つキー。初めて起動したときは表示する。
    static let storageKey = "showsDetailPane"
}

enum ViewState {
    /// 選んでいた画面（`TodoListKind.storedValue`）を `@AppStorage` で保つキー。
    static let listKindKey = "listKind"
    /// Inbox の並び順（`InboxSortOrder.storedValue`）を `@AppStorage` で保つキー。
    static let sortOrderKey = "inboxSortOrder"
}

private struct ContentView: View {
    let store: TodoStore
    let undoRouter: UndoRouter
    /// 選んでいた画面と Inbox の並び順。文字列で保存し、読めない値は既定値（Inbox・期限日順）にする。
    @AppStorage(ViewState.listKindKey) private var storedListKind = ""
    @AppStorage(ViewState.sortOrderKey) private var storedSortOrder = ""
    @State private var selection: Todo.ID?
    @AppStorage(DetailPane.storageKey) private var showsDetailPane = true

    private var listKind: Binding<TodoListKind> {
        Binding(
            get: { TodoListKind(storedValue: storedListKind) },
            set: { storedListKind = $0.storedValue }
        )
    }

    private var sortOrder: Binding<InboxSortOrder> {
        Binding(
            get: { InboxSortOrder(storedValue: storedSortOrder) },
            set: { storedSortOrder = $0.storedValue }
        )
    }

    var body: some View {
        // 詳細ペインは右だけを隠せるよう、3列目ではなく inspector にする（NavigationSplitView は右の列だけを隠せない）
        NavigationSplitView {
            SidebarView(selection: listKind)
        } detail: {
            TodoListView(
                store: store, undoRouter: undoRouter, kind: listKind.wrappedValue,
                sortOrder: sortOrder.wrappedValue, selection: $selection
            )
            .inspector(isPresented: $showsDetailPane) {
                Group {
                    if let selection {
                        // 選択が変わるたびに作り直し、打ちかけのタイトルを元の Todo に確定させる
                        TodoDetailView(store: store, todoID: selection)
                            .id(selection)
                    } else {
                        DetailPlaceholder()
                    }
                }
                .inspectorColumnWidth(min: 260, ideal: 300, max: 500)
            }
        }
        .toolbar {
            // アーカイブは完了日時の新しい順で固定なので、並び順の切り替えは Inbox のときだけ出す
            if listKind.wrappedValue == .inbox {
                ToolbarItem {
                    Picker("並び順", selection: sortOrder) {
                        ForEach(InboxSortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Inbox の並び順を切り替える")
                }
            }
            ToolbarItem {
                Button {
                    showsDetailPane.toggle()
                } label: {
                    Label("詳細ペイン", systemImage: "sidebar.right")
                }
                .help("詳細ペインを表示／隠す（⌥⌘I）")
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        // フォーカスの場所が変わったことを、⌘Z をどこへ渡すかの判断に反映する
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didUpdateNotification)) { _ in
            undoRouter.refresh()
        }
    }
}
