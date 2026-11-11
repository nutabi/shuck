import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Developer Junk's simulator caches rule, and the simulators' devices it never touches (DEV-R04, DEV-007, D-119).
struct SimulatorCachesTests {
    let root: FixtureRoot
    let caches = "Library/Developer/CoreSimulator/Caches"
    let devices = "Library/Developer/CoreSimulator/Devices"

    init() throws {
        root = try FixtureRoot()
    }

    private func items(running: Set<String> = [], ownership: OwnershipMap? = nil) async -> [String: ScanItem] {
        let context = ScanContext(
            home: root.url, ownership: ownership ?? OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        var result: [String: ScanItem] = [:]
        for await event in DeveloperJunk().scan(context) {
            if case .item(let item) = event { result[item.url?.lastPathComponent ?? ""] = item }
        }
        return result
    }

    @Test func eachEntryOfTheCachesFolderIsOneSelectedItemDEVR04() async throws {
        try root.file("\(caches)/dyld/21C62/arm64e/cache", size: 8192)
        try root.file("\(caches)/com.apple.CoreSimulator.SimRuntime.iOS-17-2.plist", size: 100)

        let items = await items()

        #expect(Set(items.keys) == ["dyld", "com.apple.CoreSimulator.SimRuntime.iOS-17-2.plist"])
        #expect(
            items.values.allSatisfy { $0.selection == .selected && $0.tier == .rebuildable && $0.method == .delete })
        #expect(items["dyld"]?.allocatedSize ?? 0 >= 8192)
    }

    @Test func aRunningXcodeOrSimulatorDisablesTheItemsSAF009() async throws {
        try root.file("\(caches)/dyld/cache", size: 10)

        for app in ["com.apple.dt.Xcode", "com.apple.iphonesimulator"] {
            let items = await items(running: [app])
            #expect(items.values.map(\.selection) == [.appIsRunning(nil)], "\(app)")
        }
        #expect(DeveloperJunk.simulatorBundleID == "com.apple.iphonesimulator")
    }

    @Test func linksAreNotListedAndNothingShowsWithoutTheFolderDEV002() async throws {
        #expect(await items().isEmpty)
        try root.file("\(caches)/real/file", size: 10)
        try root.symlink("\(caches)/link", to: root.folder("Elsewhere"))

        #expect(Set(await items().keys) == ["real"])
    }

    @Test func theDevicesAreNeverListedOrOwnedDEV007() async throws {
        try root.file("\(devices)/ABCD-1234/data/Library/Preferences/app.plist", size: 10)
        try root.file("\(caches)/dyld/cache", size: 10)

        let items = await items()

        #expect(Set(items.keys) == ["dyld"])
        let map = OwnershipMap(home: root.url)
        let device = try root.url("\(devices)/ABCD-1234")
        #expect(map.owners(of: device).isEmpty)
        #expect(map.owners(of: try root.url("Library/Developer/CoreSimulator/Devices")).isEmpty)
        #expect(map.owners(of: try root.url("\(caches)/dyld")) == [.developerJunk])
    }

    @Test func theRuleAcceptsOnlyEntriesOfTheCachesFolderDEV007() throws {
        let rule = try DeveloperJunk.simulatorCachesRule(home: root.url)

        func accepts(_ path: String) throws -> Bool {
            rule.accepts(.path(try root.url(path)), tier: .rebuildable, method: .delete, scope: .item)
        }

        #expect(try accepts("\(caches)/dyld"))
        #expect(try !accepts(caches))
        #expect(try !accepts("\(caches)/dyld/cache"))
        #expect(try !accepts("\(devices)/ABCD-1234"))
        #expect(try !accepts(devices))
        #expect(try !accepts("Library/Developer/CoreSimulator/Volumes/iOS_21C62"))
        #expect(rule.apps == ["com.apple.dt.Xcode", "com.apple.iphonesimulator"])
    }

    @Test func theSubToolsRootsLeaveOutTheDevicesDEV007() throws {
        try root.file("\(devices)/ABCD-1234/device.plist", size: 10)
        try root.file("\(caches)/dyld/cache", size: 10)

        let roots = DeveloperJunk().allowedRoots(home: root.url)
        let guardConfiguration = PathGuard(configuration: root.pathGuardConfiguration())
        let device = try root.url("\(devices)/ABCD-1234")
        let cache = try root.url("\(caches)/dyld")

        #expect(try guardConfiguration.validate(cache, allowedRoots: roots) == cache)
        #expect(throws: PathGuardError.self) { try guardConfiguration.validate(device, allowedRoots: roots) }
    }

    @Test func aScanLeavesOutCachesTheMapGivesAnotherSubToolFCL005() async throws {
        try root.file("\(caches)/dyld/cache", size: 10)

        #expect(await items(ownership: OwnershipMap(home: root.url, entries: [])).isEmpty)
    }
}
