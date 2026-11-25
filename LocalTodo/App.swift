import SwiftUI

@main
struct LocalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: TodoStore

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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ウィンドウが1つだけなので、閉じたらアプリも終了する
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct ContentView: View {
    let store: TodoStore

    var body: some View {
        Color.clear
            .frame(minWidth: 800, minHeight: 500)
    }
}
