import SwiftUI

@main
struct LocalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: TodoStore
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
            ContentView(store: store)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button(showsDetailPane ? "詳細ペインを隠す" : "詳細ペインを表示") {
                    showsDetailPane.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
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

private struct ContentView: View {
    let store: TodoStore
    @State private var listKind = TodoListKind.inbox
    @State private var selection: Todo.ID?
    @AppStorage(DetailPane.storageKey) private var showsDetailPane = true

    var body: some View {
        // 詳細ペインは右だけを隠せるよう、3列目ではなく inspector にする（NavigationSplitView は右の列だけを隠せない）
        NavigationSplitView {
            SidebarView(selection: $listKind)
        } detail: {
            TodoListView(store: store, kind: listKind, selection: $selection)
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
    }
}
