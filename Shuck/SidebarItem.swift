import Foundation

/// A destination in the main window's sidebar (PRD section 9).
///
/// Placeholder until the tools registry in ShuckKit (M1-T06) drives the sidebar.
/// Plain data, so it opts out of the app target's default main-actor isolation.
nonisolated enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case fileCleanup
    case largeFiles
    case oldFiles
    case developerJunk
    case cachesAndLogs
    case applications
    case startupItems
    case history

    var id: Self { self }

    /// The items shown at the top level of the sidebar, in order.
    static let topLevel: [SidebarItem] = [.overview, .fileCleanup, .applications, .startupItems, .history]

    /// File Cleanup's sub-tools, shown nested under it (FCL-001).
    static let fileCleanupSubTools: [SidebarItem] = [.largeFiles, .oldFiles, .developerJunk, .cachesAndLogs]

    var title: LocalizedStringResource {
        switch self {
        case .overview: "Overview"
        case .fileCleanup: "File Cleanup"
        case .largeFiles: "Large Files"
        case .oldFiles: "Old Files"
        case .developerJunk: "Developer Junk"
        case .cachesAndLogs: "Caches & Logs"
        case .applications: "Applications"
        case .startupItems: "Startup Items"
        case .history: "History"
        }
    }

    /// The question or job the destination answers, shown on its page.
    var summary: LocalizedStringResource {
        switch self {
        case .overview: "Disk space at a glance, and what each sub-tool could reclaim."
        case .fileCleanup: "Reclaim space from files, one sub-tool at a time."
        case .largeFiles: "What is taking the most space?"
        case .oldFiles: "What haven't I opened in a long time?"
        case .developerJunk: "What can developer tools rebuild?"
        case .cachesAndLogs: "Which caches and logs can go?"
        case .applications: "Uninstall apps together with the files they leave behind."
        case .startupItems: "See what starts automatically and turn off what you don't want."
        case .history: "Every action Shuck has taken, and how to put things back."
        }
    }

    /// An SF Symbols name.
    var systemImage: String {
        switch self {
        case .overview: "internaldrive"
        case .fileCleanup: "folder"
        case .largeFiles: "scalemass"
        case .oldFiles: "calendar.badge.clock"
        case .developerJunk: "hammer"
        case .cachesAndLogs: "tray.full"
        case .applications: "square.grid.2x2"
        case .startupItems: "power"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// The roadmap milestone that builds this destination (PRD section 13).
    var milestone: String {
        switch self {
        case .fileCleanup, .largeFiles, .oldFiles, .history: "M1"
        case .developerJunk, .cachesAndLogs: "M2"
        case .applications: "M3"
        case .startupItems: "M4"
        case .overview: "M5"
        }
    }
}
