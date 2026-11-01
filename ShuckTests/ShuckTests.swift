import AppKit
import ShuckKit
import Testing

@testable import Shuck

struct EngineLinkTests {
    /// The app links ShuckKit, and the engine's logger subsystem is the app's bundle ID (D-21).
    @Test func loggerSubsystemIsTheAppBundleID() {
        #expect(Bundle.main.bundleIdentifier == ShuckKit.loggerSubsystem)
    }
}

struct SidebarItemTests {
    @Test func topLevelOrderMatchesPRD() {
        #expect(SidebarItem.topLevel == [.overview, .fileCleanup, .applications, .startupItems, .history])
    }

    @Test func fileCleanupHasFourSubToolsFCL001() {
        #expect(SidebarItem.fileCleanupSubTools == [.largeFiles, .oldFiles, .developerJunk, .cachesAndLogs])
    }

    @Test func everyItemAppearsExactlyOnce() {
        let shown = SidebarItem.topLevel + SidebarItem.fileCleanupSubTools
        #expect(shown.count == SidebarItem.allCases.count)
        #expect(Set(shown) == Set(SidebarItem.allCases))
    }

    @Test(arguments: SidebarItem.allCases)
    func symbolExists(item: SidebarItem) {
        #expect(NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil) != nil)
    }
}
