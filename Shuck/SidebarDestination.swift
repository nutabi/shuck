import Foundation
import ShuckKit

/// A destination in the main window's sidebar (PRD section 9).
///
/// Overview and History belong to the app. The tools and sub-tools in between come from ``ToolRegistry/standard``,
/// so a new sub-tool appears without changes here (FCL-003). Plain data, so it opts out of the app target's default
/// main-actor isolation.
nonisolated enum SidebarDestination: Hashable {
    case overview
    /// A tool or a sub-tool from the registry.
    case tool(ToolID)
    case history

    /// What the sidebar and the destination's page show, or `nil` for a tool the registry does not list.
    func label(in registry: ToolRegistry) -> DestinationLabel? {
        switch self {
        case .overview:
            DestinationLabel(
                name: "Overview", summary: "Disk space at a glance, and what each sub-tool could reclaim.",
                symbolName: "internaldrive", availability: .planned(milestone: "M5"))
        case .history:
            DestinationLabel(
                name: "History", summary: "Every action Shuck has taken, and how to put things back.",
                symbolName: "clock.arrow.circlepath", availability: .planned(milestone: "M1"))
        case .tool(let id):
            registry.info(id).map(DestinationLabel.init)
        }
    }
}

/// A destination's name, one-line summary, SF Symbols name and availability.
nonisolated struct DestinationLabel {
    let name: LocalizedStringResource
    let summary: LocalizedStringResource
    let symbolName: String
    let availability: Availability

    init(
        name: LocalizedStringResource, summary: LocalizedStringResource, symbolName: String, availability: Availability
    ) {
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.availability = availability
    }

    init(_ info: ToolInfo) {
        self.init(name: info.name, summary: info.summary, symbolName: info.symbolName, availability: info.availability)
    }
}
