import Foundation

/// Why an uninstall plan could not be built (APP-005).
public enum UninstallPlanError: Error, Equatable {
    /// The user cannot remove the bundle, so nothing is planned: leftovers are never removed on their own (APP-005).
    case appBlocked(AppRemovability.Reason)
    /// ``Plan`` refused an item, for example a leftover another tool found, or one the path guard rejects.
    case plan(PlanError)
}

extension Applications {
    /// The category of the app bundle's own item.
    private static let bundleCategory = ItemCategory(id: "app", name: LocalizedStringResource("App", bundle: #bundle))

    /// The plan that uninstalls `app` and the selected `leftovers` (APP-007): everything goes to the Trash, and an
    /// agent is unloaded with `launchctl bootout` before its property list is (APP-011). The path guard checks every
    /// item as ``Plan`` is created (SAF-007).
    ///
    /// The plan is one chain, with the bundle first. A ``PlannedItem`` has one dependency slot, and a property list
    /// needs two things done first: its `bootout` (APP-011) and the bundle gone (APP-005). So every leftover depends
    /// on the bundle's Trash item, and a plist's Trash item depends on its own `bootout`, which depends on the bundle.
    /// A bundle that is refused therefore leaves every leftover alone, and no agent is unloaded for an app that stays.
    ///
    /// Each item carries the app's bundle ID in `apps`, so the run skips it while the app runs (SAF-009).
    public func uninstallPlan(
        for app: InstalledApp, leftovers: [ScanItem], pathGuard: PathGuard, run: UUID = UUID()
    ) throws(UninstallPlanError) -> Plan {
        if case .blocked(let reason) = app.removability { throw .appBlocked(reason) }
        for item in leftovers where item.source != .applications {
            throw .plan(.otherSubTool(item.target.description, item.source))
        }
        let home = pathGuard.configuration.home
        let agents = home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory).standardizedFileURL
        let appIDs: Set<String> = app.bundleID.map { [$0] } ?? []

        let bundle = PlannedItem(
            url: app.url, tier: .yourData, method: .trash, snapshot: app.snapshot, modified: app.modified,
            category: Self.bundleCategory, selection: .selected, apps: appIDs)
        let afterBundle = ItemDependency(bundle)
        var items = [bundle]
        for leftover in leftovers {
            let isAgent = leftover.url?.deletingLastPathComponent().standardizedFileURL == agents
            var trashAfter = afterBundle
            if isAgent {
                let bootout = try Self.planned(leftover, .launchctl, appIDs, after: afterBundle)
                items.append(bootout)
                trashAfter = ItemDependency(bootout)
            }
            items.append(try Self.planned(leftover, .trash, appIDs, after: trashAfter))
        }
        do {
            return try Plan(
                tool: .applications, allowedRoots: allowedRoots(home: home), items: items, pathGuard: pathGuard,
                run: run)
        } catch {
            throw .plan(error)
        }
    }

    /// The item for a leftover found by the scan, acting by `method` after `dependency`. A leftover is a file the scan
    /// measured, so one without a path or a snapshot, such as a command, is refused.
    private static func planned(
        _ leftover: ScanItem, _ method: ActionMethod, _ apps: Set<String>, after dependency: ItemDependency
    ) throws(UninstallPlanError) -> PlannedItem {
        guard let url = leftover.url, let snapshot = leftover.snapshot else {
            throw .plan(.commandRequired(leftover.target.description))
        }
        return PlannedItem(
            url: url, tier: leftover.tier, method: method, snapshot: snapshot, modified: leftover.modified,
            scope: leftover.scope, identity: leftover.identity, category: leftover.category,
            selection: leftover.selection, ruleMatch: leftover.ruleMatch, apps: leftover.apps.union(apps),
            dependency: dependency)
    }
}
