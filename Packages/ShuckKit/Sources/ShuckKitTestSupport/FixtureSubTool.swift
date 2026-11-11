import Foundation
import ShuckKit

/// A test-only sub-tool that lists every file it owns in the home folder, so tests can drive the sub-tool interface
/// end to end (FCL-003). Give its scan an ownership map that assigns it locations with its ID.
public struct FixtureSubTool: SubTool {
    public static let id = ToolID(rawValue: "TST")

    public let info: ToolInfo
    public let tiers: Set<Tier>
    let tier: Tier
    let method: ActionMethod

    /// Its items have `tier` and `method`. A tier outside ``tiers`` lets a test check that plans reject it. Give each
    /// sub-tool its own `id` when a test needs several (FCL-002).
    public init(id: ToolID = Self.id, tier: Tier = .yourData, method: ActionMethod = .trash, tiers: Set<Tier>? = nil) {
        info = ToolInfo(
            id: id, name: "Fixture", summary: "Lists every file it owns.", symbolName: "testtube.2",
            availability: .available)
        self.tier = tier
        self.method = method
        self.tiers = tiers ?? [tier]
    }

    public func allowedRoots(home: URL) -> [URL] { [home] }

    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        AsyncStream { continuation in
            let files = FileManager.default.enumerator(
                at: context.home, includingPropertiesForKeys: [.isRegularFileKey])
            while let url = files?.nextObject() as? URL {
                guard context.ownership.owners(of: url).contains(id),
                    (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                    let snapshot = ItemSnapshot.read(url)
                else { continue }
                let item = ScanItem(
                    url: url, snapshot: snapshot, tier: tier, method: method, reason: "Fixture file", source: id,
                    modified: ModificationDate.read(at: url))
                continuation.yield(.item(item))
            }
            continuation.finish()
        }
    }
}
