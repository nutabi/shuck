import Foundation
import ShuckKitTestSupport
import Testing

@testable import ShuckKit

/// Developer Junk's device support rule: every version except the newest of each platform is selected (DEV-R02, D-118).
struct DeviceSupportTests {
    let root: FixtureRoot

    init() throws {
        root = try FixtureRoot()
    }

    private func items(running: Set<String> = [], ownership: OwnershipMap? = nil) async -> [String: ScanItem] {
        let context = ScanContext(
            home: root.url, ownership: ownership ?? OwnershipMap(home: root.url),
            protection: root.pathGuardConfiguration(), runningApps: StubRunningApps(running))
        var result: [String: ScanItem] = [:]
        for await event in DeveloperJunk().scan(context) {
            if case .item(let item) = event, let url = item.url {
                result[DeviceSupportVersion.name(ofFolder: url)] = item
            }
        }
        return result
    }

    @Test func everyVersionButTheNewestOfEachPlatformIsSelectedDEVR02() async throws {
        try root.deviceSupport("iOS", "16.4 (20E247)")
        try root.deviceSupport("iOS", "17.2 (21C62) arm64e")
        try root.deviceSupport("iOS", "17.10 (21E5) arm64e")
        try root.deviceSupport("watchOS", "10.0 (21R355)")
        try root.deviceSupport("macOS", "14.1 (23B74)")
        try root.deviceSupport("macOS", "13.6 (22G120)")
        // A link is not a version, so it cannot be the newest.
        try root.symlink("Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A1)", to: root.folder("Elsewhere"))

        let items = await items()

        #expect(items.count == 6)
        #expect(items["iOS 16.4 (20E247)"]?.selection == .selected)
        #expect(items["iOS 17.2 (21C62) arm64e"]?.selection == .selected)
        // 17.10 is newer than 17.2: the parts compare as numbers, not as text.
        #expect(items["iOS 17.10 (21E5) arm64e"]?.selection == .unselected)
        // A platform's only version is its newest.
        #expect(items["watchOS 10.0 (21R355)"]?.selection == .unselected)
        #expect(items["macOS 14.1 (23B74)"]?.selection == .unselected)
        #expect(items["macOS 13.6 (22G120)"]?.selection == .selected)
        #expect(items.values.allSatisfy { $0.tier == .rebuildable && $0.method == .delete })
    }

    @Test func buildsOfTheNewestVersionStayAndNamesWithoutAVersionAreNeverSelectedD118() async throws {
        try root.deviceSupport("iOS", "17.2 (21C62) arm64e")
        try root.deviceSupport("iOS", "17.2 (21C62)")
        try root.deviceSupport("iOS", "iPhone15,2 16.0 (20A362)")
        try root.deviceSupport("iOS", "Symbols")

        let items = await items()

        #expect(items["iOS 17.2 (21C62) arm64e"]?.selection == .unselected)
        #expect(items["iOS 17.2 (21C62)"]?.selection == .unselected)
        #expect(items["iOS iPhone15,2 16.0 (20A362)"]?.selection == .selected)
        #expect(items["iOS Symbols"]?.selection == .unselected)
        // A folder that is not a version folder keeps its own name.
        let other = try root.url("Library/Developer/Xcode/DerivedData/App-abc")
        #expect(DeviceSupportVersion.name(ofFolder: other) == "App-abc")
    }

    @Test(arguments: [
        ("17.2 (21C62) arm64e", [17, 2]), ("iPhone15,2 17.0 (21A329)", [17, 0]), ("16", [16]),
        ("Watch6,2 10.1.1 (21S5)", [10, 1, 1]), ("Symbols", nil), ("(21C62)", nil), ("17..2", nil),
    ])
    func aVersionIsTheFirstWordOfNumbersAndDotsD118(name: String, version: [Int]?) {
        #expect(DeviceSupportVersion.components(ofFolder: name) == version)
    }

    @Test func allowedRootsAreTheExistingDeviceSupportFoldersAndTheOtherRulesRootsOnlyD118() throws {
        try root.deviceSupport("iOS", "16.4 (20E247)")
        try root.deviceSupport("visionOS", "1.0 (21N1)")
        try root.file("Library/Developer/Xcode/UserData/Snippets/one.codesnippet", size: 10)

        let roots = DeveloperJunk().allowedRoots(home: root.url).map(\.lastPathComponent)

        // Archives is a root of its own rule (DEV-R05, D-145); the rest of Xcode's folders are not roots.
        #expect(roots == ["DerivedData", "iOS DeviceSupport", "visionOS DeviceSupport", "Caches", "Archives"])
    }
}
