import SwiftUI

struct SidebarView: View {
    @Binding var selection: TodoListKind

    var body: some View {
        List(selection: optionalSelection) {
            ForEach(TodoListKind.allCases, id: \.self) { kind in
                Label(kind.title, systemImage: kind.systemImage)
                    .tag(kind)
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    }

    /// List の選択は nil を取りうるが、どちらか一方を必ず選んでおくため、nil は受け付けない。
    private var optionalSelection: Binding<TodoListKind?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue { selection = newValue }
            }
        )
    }
}
