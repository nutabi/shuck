import Foundation
import ShuckKit

extension FixtureRoot {
    /// A planned item for the existing item at `url`, as a scan would plan it: measured now, with the modification date
    /// re-validation compares (SAF-008, D-132). A Delete item that its tier allows also gets a fixture cleanup rule that
    /// matches exactly this path, since a plan refuses a Delete without one (D-132).
    ///
    /// Tests that check what a run does with a changed item change it after calling this.
    public func planned(
        _ url: URL, tier: Tier = .rebuildable, method: ActionMethod = .delete, scope: ItemScope = .item,
        identity: FileIdentity? = nil
    ) throws(FixtureError) -> PlannedItem {
        let target = try requireInside(url)
        guard let snapshot = ItemSnapshot.read(target), let own = ModificationDate.read(at: target) else {
            throw .fileSystem("Cannot read \(target.path)")
        }
        let rule = method == .delete && tier.allows(.delete) ? try fixtureRule(for: target, scope: scope) : nil
        return PlannedItem(
            url: target, tier: tier, method: method, snapshot: snapshot,
            modified: ModificationDate.compared(at: target, scope: scope, own: own), scope: scope, identity: identity,
            ruleMatch: rule.map { RuleMatch(rule: $0, modified: own) })
    }

    /// A rebuildable Delete rule for `url`, detected by the fixture root itself. It matches every item in `url`'s
    /// folder, since a rule matches the path a symlink resolves to and a test may delete a link.
    public func fixtureRule(for url: URL, scope: ItemScope = .item) throws(FixtureError) -> CleanupRule {
        do {
            return try CleanupRule(
                id: "fixture", name: "Fixture", description: "Fixture item",
                category: ItemCategory(id: "fixture", name: "Fixture"), detection: .folder(self.url),
                action: .paths(
                    [RulePath(root: url.deletingLastPathComponent(), pattern: "*")], method: .delete,
                    scope: scope),
                tier: .rebuildable, selection: .always, explanation: "Fixture item",
                documentation: Self.fixtureDocumentation)
        } catch {
            throw .fileSystem("Cannot make a rule for \(url.path): \(error)")
        }
    }

    /// A documentation link that is never opened.
    private static let fixtureDocumentation = URL(string: "https://example.test/fixture") ?? URL(filePath: "/")
}
