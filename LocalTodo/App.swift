import SwiftUI

@main
struct LocalTodoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // WindowGroup ではなく Window にして、ウィンドウを1つに限る（「新規ウィンドウ」も出ない）
        Window("LocalTodo", id: "main") {
            ContentView()
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
    var body: some View {
        Color.clear
            .frame(minWidth: 800, minHeight: 500)
    }
}
