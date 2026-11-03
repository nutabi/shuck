import ShuckKit
import SwiftUI

/// The main window: a sidebar of tools and the selected tool's page.
///
/// The sidebar is built from `registry` (FCL-001, FCL-003): Overview, every tool with its sub-tools nested under it,
/// then History. A sub-tool's page comes from `pages`, by tool ID.
struct ContentView: View {
    let registry: ToolRegistry
    let pages: SubToolPages
    let fileCleanup: FileCleanupModel
    let history: HistoryModel

    @Environment(AppNavigation.self) private var navigation
    @State private var collapsedTools: Set<ToolID> = []

    var body: some View {
        @Bindable var navigation = navigation
        NavigationSplitView {
            List(selection: $navigation.selection) {
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
        switch navigation.selection {
        case .tool(.fileCleanup)?:
            if let info = registry.info(.fileCleanup) {
                FileCleanupView(info: info, model: fileCleanup)
            }
        case .tool(let id)?:
            if let page = pages.page(id, model: fileCleanup, registry: registry) {
                // Each sub-tool's page has its own identity, so two pages of the same type never share state, such as
                // an open review.
                page.id(id)
            } else if let label = SidebarDestination.tool(id).label(in: registry) {
                PlaceholderView(label: label)
            }
        case .history?:
            HistoryView(model: history, registry: registry)
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
        registry: .standard, pages: SubToolPages(largeFiles: LargeFiles(), oldFiles: OldFiles()),
        fileCleanup: FileCleanupModel(subTools: [], context: ScanContext(home: .temporaryDirectory)),
        history: HistoryModel(home: .temporaryDirectory) { .init(runs: [], unreadableLineCount: 0) }
    )
    .environment(AppNavigation())
}
