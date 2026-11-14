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
    public static let standard = standard()

    /// The standard registry with the user's settings, such as Large Files' minimum size and Old Files' period
    /// (SET-002).
    public static func standard(
        largeFiles: LargeFiles = LargeFiles(), oldFiles: OldFiles = OldFiles(),
        developerJunk: DeveloperJunk = DeveloperJunk(), cachesAndLogs: CachesAndLogs = CachesAndLogs()
    ) -> ToolRegistry {
        ToolRegistry(tools: [
            Tool(
                info: ToolInfo(
                    id: .fileCleanup, name: LocalizedStringResource("File Cleanup", bundle: #bundle),
                    summary: LocalizedStringResource(
                        "Reclaim space from files, one sub-tool at a time.", bundle: #bundle),
                    symbolName: "folder", availability: .available),
                subTools: [
                    largeFiles,
                    oldFiles,
                    developerJunk,
                    cachesAndLogs,
                ]),
            Tool(
                info: ToolInfo(
                    id: .applications, name: LocalizedStringResource("Applications", bundle: #bundle),
                    summary: LocalizedStringResource(
                        "Uninstall apps together with the files they leave behind.", bundle: #bundle),
                    symbolName: "square.grid.2x2", availability: .available)),
            Tool(
                info: ToolInfo(
                    id: .startupItems, name: LocalizedStringResource("Startup Items", bundle: #bundle),
                    summary: LocalizedStringResource(
                        "See what starts automatically and turn off what you don't want.", bundle: #bundle),
                    symbolName: "power", availability: .planned(milestone: "M4"))),
        ])
    }
}
