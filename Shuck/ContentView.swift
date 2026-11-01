import SwiftUI

/// The main window: a sidebar of tools and the selected tool's page.
struct ContentView: View {
    @State private var selection: SidebarItem? = .overview
    @State private var isFileCleanupExpanded = true

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.topLevel) { item in
                    if item == .fileCleanup {
                        DisclosureGroup(isExpanded: $isFileCleanupExpanded) {
                            ForEach(SidebarItem.fileCleanupSubTools) { subTool in
                                SidebarRow(item: subTool)
                            }
                        } label: {
                            SidebarRow(item: item)
                        }
                    } else {
                        SidebarRow(item: item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let selection {
                PlaceholderView(item: selection)
            } else {
                ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }
}

#Preview {
    ContentView()
}
