import SwiftUI

/// Stands in for a tool's page until its milestone builds it.
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: item.systemImage)
            }
        } description: {
            Text(item.summary)
        } actions: {
            Text("Planned for milestone \(item.milestone).")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(Text(item.title))
    }
}

#Preview {
    PlaceholderView(item: .largeFiles)
}
