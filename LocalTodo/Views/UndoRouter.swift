import AppKit
import SwiftUI

/// ⌘Z／⇧⌘Z を、入力欄に渡すか、`TodoStore` の取り消しに渡すかを決める。
///
/// 入力欄（文字を打っている NSTextView）にフォーカスがあるあいだは、入力欄の標準の取り消しに任せる。
/// 例外は新規入力欄で、欄が空のときは `TodoStore` に渡す（追加してすぐ ⌘Z で、いま追加した Todo を取り消せるように）。
@Observable
final class UndoRouter {
    /// 文字を打てる欄（NSTextView）にフォーカスがあるか。
    private(set) var isEditingText = false
    /// フォーカスのある欄が、取り消し・やり直しできるか。
    private(set) var textCanUndo = false
    private(set) var textCanRedo = false
    /// 新規入力欄にフォーカスがあり、かつ空か。`TodoListView` が更新する。
    var isNewTodoFieldEmptyAndFocused = false

    var routesToStore: Bool {
        !isEditingText || isNewTodoFieldEmptyAndFocused
    }

    /// フォーカスの場所を読み直す。変わったときだけ書く（画面の更新を無駄に起こさないため）。
    func refresh() {
        let textView = NSApp.keyWindow?.firstResponder as? NSTextView
        let editing = textView != nil
        let canUndo = textView?.undoManager?.canUndo ?? false
        let canRedo = textView?.undoManager?.canRedo ?? false
        if isEditingText != editing { isEditingText = editing }
        if textCanUndo != canUndo { textCanUndo = canUndo }
        if textCanRedo != canRedo { textCanRedo = canRedo }
    }

    /// 入力欄の取り消し・やり直しを、フォーカスのある欄に送る。
    func sendToTextField(undo: Bool) {
        NSApp.sendAction(Selector(undo ? "undo:" : "redo:"), to: nil, from: nil)
    }
}
