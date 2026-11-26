import SwiftUI

struct TodoRowView: View {
    let todo: Todo

    var body: some View {
        Text(todo.title)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 2)
    }
}
