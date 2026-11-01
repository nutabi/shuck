import AppKit
import Testing

@testable import Shuck

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
