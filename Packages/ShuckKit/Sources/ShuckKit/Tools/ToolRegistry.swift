import Foundation

/// A top-level tool in the sidebar and its sub-tools (PRD section 8.1).
public struct Tool: Sendable {
    public let info: ToolInfo
    /// Listed in sidebar order. Only File Cleanup has sub-tools.
    public let subTools: [any SubTool]

    public init(info: ToolInfo, subTools: [any SubTool] = []) {
        self.info = info
        self.subTools = subTools
    }
}

/// The tools and sub-tools Shuck offers, in sidebar order. The sidebar and the File Cleanup landing page are built
/// from it (PRD section 11.1).
public struct ToolRegistry: Sendable {
    public let tools: [Tool]

    public init(tools: [Tool]) {
        self.tools = tools
    }

    /// Every sub-tool of every tool.
    public var subTools: [any SubTool] { tools.flatMap(\.subTools) }

    public func subTool(_ id: ToolID) -> (any SubTool)? {
        subTools.first { $0.id == id }
    }

    /// What the sidebar shows for the tool or sub-tool with `id`.
    public func info(_ id: ToolID) -> ToolInfo? {
        tools.first { $0.info.id == id }?.info ?? subTool(id)?.info
    }
}

extension ToolRegistry {
    /// The registry the app uses: File Cleanup with its four sub-tools (FCL-001), Applications and Startup Items.
    public static let standard = ToolRegistry(tools: [
        Tool(
            info: ToolInfo(
                id: .fileCleanup, name: LocalizedStringResource("File Cleanup", bundle: #bundle),
                summary: LocalizedStringResource("Reclaim space from files, one sub-tool at a time.", bundle: #bundle),
                symbolName: "folder", availability: .available),
            subTools: [
                PlannedSubTool(
                    info: ToolInfo(
                        id: .largeFiles, name: LocalizedStringResource("Large Files", bundle: #bundle),
                        summary: LocalizedStringResource("What is taking the most space?", bundle: #bundle),
                        symbolName: "scalemass", availability: .planned(milestone: "M1")),
                    tiers: [.yourData]),
                PlannedSubTool(
                    info: ToolInfo(
                        id: .oldFiles, name: LocalizedStringResource("Old Files", bundle: #bundle),
                        summary: LocalizedStringResource("What haven't I opened in a long time?", bundle: #bundle),
                        symbolName: "calendar.badge.clock", availability: .planned(milestone: "M1")),
                    tiers: [.yourData]),
                // Two rules, Xcode Archives and Docker, are "Your data" (section 8.2).
                PlannedSubTool(
                    info: ToolInfo(
                        id: .developerJunk, name: LocalizedStringResource("Developer Junk", bundle: #bundle),
                        summary: LocalizedStringResource("What can developer tools rebuild?", bundle: #bundle),
                        symbolName: "hammer", availability: .planned(milestone: "M2")),
                    tiers: [.rebuildable, .yourData]),
                PlannedSubTool(
                    info: ToolInfo(
                        id: .cachesAndLogs, name: LocalizedStringResource("Caches & Logs", bundle: #bundle),
                        summary: LocalizedStringResource("Which caches and logs can go?", bundle: #bundle),
                        symbolName: "tray.full", availability: .planned(milestone: "M2")),
                    tiers: [.rebuildable]),
            ]),
        Tool(
            info: ToolInfo(
                id: .applications, name: LocalizedStringResource("Applications", bundle: #bundle),
                summary: LocalizedStringResource(
                    "Uninstall apps together with the files they leave behind.", bundle: #bundle),
                symbolName: "square.grid.2x2", availability: .planned(milestone: "M3"))),
        Tool(
            info: ToolInfo(
                id: .startupItems, name: LocalizedStringResource("Startup Items", bundle: #bundle),
                summary: LocalizedStringResource(
                    "See what starts automatically and turn off what you don't want.", bundle: #bundle),
                symbolName: "power", availability: .planned(milestone: "M4"))),
    ])
}
