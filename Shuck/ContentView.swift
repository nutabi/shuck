import ShuckKit
import SwiftUI

/// The main window: a sidebar of tools and the selected tool's page.
///
/// The sidebar is built from `registry` (FCL-001, FCL-003): Overview, every tool with its sub-tools nested under it,
/// then History.
struct ContentView: View {
    let registry: ToolRegistry
    let fileCleanup: FileCleanupModel

    @State private var selection: SidebarDestination? = .overview
    @State private var collapsedTools: Set<ToolID> = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SidebarRow(destination: .overview, registry: registry)
                ForEach(registry.tools, id: \.info.id) { tool in
                    if tool.subTools.isEmpty {
                        SidebarRow(destination: .tool(tool.info.id), registry: registry)
                    } else {
                        DisclosureGroup(isExpanded: isExpanded(tool.info.id)) {
                            ForEach(tool.subTools, id: \.id) { subTool in
                                SidebarRow(destination: .tool(subTool.id), registry: registry)
                            }
                        } label: {
                            SidebarRow(destination: .tool(tool.info.id), registry: registry)
                        }
                    }
                }
                SidebarRow(destination: .history, registry: registry)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .tool(.fileCleanup)?:
            if let info = registry.info(.fileCleanup) {
                FileCleanupView(info: info, model: fileCleanup)
            }
        case let destination?:
            if let label = destination.label(in: registry) {
                PlaceholderView(label: label)
            }
        case nil:
            ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
        }
    }

    /// Tools with sub-tools start expanded; the set remembers the ones the user collapsed.
    private func isExpanded(_ id: ToolID) -> Binding<Bool> {
        Binding {
            !collapsedTools.contains(id)
        } set: { expanded in
            if expanded { collapsedTools.remove(id) } else { collapsedTools.insert(id) }
        }
    }
}

private struct SidebarRow: View {
    let destination: SidebarDestination
    let registry: ToolRegistry

    var body: some View {
        if let label = destination.label(in: registry) {
            Label {
                Text(label.name)
            } icon: {
                Image(systemName: label.symbolName)
            }
            .tag(destination)
        }
    }
}

#Preview {
    ContentView(
        registry: .standard,
        fileCleanup: FileCleanupModel(subTools: [], context: ScanContext(home: .temporaryDirectory)))
}
