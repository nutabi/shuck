import Foundation

/// DEV-R06: the `node_modules` folders of stale projects in the user's project folders (SET-003, DEV-006). A package
/// manager installs them again, so each is deleted, and selected when the project's own files have not changed for 30
/// days.
extension DeveloperJunk {
    /// A project's root lies at most this many levels below a project folder, which is level 0 (DEV-006, D-153). So
    /// `node_modules` is at most this many levels plus one below it.
    static let projectDepth = 4

    public static var nodeProjects: ItemCategory {
        ItemCategory(id: "node-projects", name: LocalizedStringResource("Node.js projects", bundle: #bundle))
    }

    /// DEV-R06 for the project folder `projectFolder`: one item per `node_modules` folder in it, at the depths a project
    /// root can lie at. `RulePath` has no `**`, so there is one pattern per depth. A plan and a run check the pattern
    /// again, so a `node_modules` deeper than the limit is refused even if something lists it (D-141, D-153).
    ///
    /// The rule names no app: whether anything has a `node_modules` open is not something Shuck can see, so a running
    /// dev server is not detected (SAF-009, D-153).
    static func nodeModulesRule(projectFolder: URL) throws(RuleError) -> CleanupRule {
        guard let documentation = URL(string: "https://docs.npmjs.com/cli/commands/npm-install") else {
            throw .invalidDocumentation
        }
        var paths: [RulePath] = []
        for depth in 1...(projectDepth + 1) {
            let parents = Array(repeating: "*", count: depth - 1)
            paths.append(
                try RulePath(
                    root: projectFolder,
                    pattern: (parents + [OwnershipMap.dependenciesFolderName]).joined(separator: "/")))
        }
        return try CleanupRule(
            id: "DEV-R06", name: LocalizedStringResource("Stale node_modules", bundle: #bundle),
            description: LocalizedStringResource(
                "The packages a Node.js project installed, in projects you have not changed for a while.",
                bundle: #bundle),
            category: nodeProjects, detection: .folder(projectFolder), action: .paths(paths, method: .delete),
            tier: .rebuildable, selection: .modifiedAtLeast(days: staleDays), explanation: nodeModulesReason(nil),
            documentation: documentation)
    }

    /// What the row says. Every variant says that restoring needs an install and a connection, which Shuck does not
    /// have (DEV-R06); a warning adds what a reinstall does not restore (DEV-006).
    static func nodeModulesReason(_ warning: NodeProject.Warning?) -> LocalizedStringResource {
        switch warning {
        case nil:
            LocalizedStringResource(
                "To restore it, run npm install, or your project's package manager, which needs an internet connection.",
                bundle: #bundle)
        case .patchPackage?:
            LocalizedStringResource(
                "To restore it, run npm install, or your project's package manager, which needs an internet connection. This project patches packages with patch-package, which a reinstall may not redo.",
                bundle: #bundle)
        case .fileLinks?:
            LocalizedStringResource(
                "To restore it, run npm install, or your project's package manager, which needs an internet connection. This project depends on local folders (file:), which a reinstall copies again from where they are then.",
                bundle: #bundle)
        case .patchPackageAndFileLinks?:
            LocalizedStringResource(
                "To restore it, run npm install, or your project's package manager, which needs an internet connection. This project patches packages with patch-package and depends on local folders (file:), which a reinstall may not restore.",
                bundle: #bundle)
        case .unreadable?:
            LocalizedStringResource(
                "To restore it, run npm install, or your project's package manager, which needs an internet connection. Shuck could not read this project's package.json, so it cannot tell what a reinstall would lose.",
                bundle: #bundle)
        }
    }

    /// One item per project that has a `node_modules` and a lockfile next to it, in each project folder. The walk ends at
    /// a folder that holds a `node_modules`, so only a project's top-most one is found (DEV-006).
    func scanNodeModules(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard let volume = FileIdentity.read(context.home)?.volume else { return }
        let now = Date.now
        for folder in projects(home: context.home) {
            guard !Task.isCancelled else { return }
            guard Self.isRealFolder(folder), !Self.isInsideExclusion(folder, context),
                let rule = try? Self.nodeModulesRule(projectFolder: folder), rule.detection.isAvailable
            else { continue }
            findProjects(in: folder, level: 0, volume: volume, rule: rule, context: context, now: now, emit)
        }
    }

    /// Looks for projects in `folder`, `level` levels below a project folder. A folder with a real `node_modules` is a
    /// project root, and nothing below it is looked at. Otherwise it goes down into folders only: never a link, a package,
    /// `.git`, another volume or an excluded folder.
    private func findProjects(
        in folder: URL, level: Int, volume: Int32, rule: CleanupRule, context: ScanContext, now: Date,
        _ emit: (ScanEvent) -> Void
    ) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        } catch {
            let error = error as NSError
            Self.logger.error(
                "Cannot list a project folder: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            emit(error.code == NSFileReadNoPermissionError ? .notAccessible(folder) : .unreadable(folder))
            return
        }
        let folders = children.filter(Self.isRealFolder)
        if let modules = folders.first(where: {
            PathGuard.fold($0.lastPathComponent) == OwnershipMap.dependenciesFolderName
        }) {
            if let item = nodeModulesItem(modules, project: folder, rule: rule, context: context, now: now) {
                emit(.item(item))
            }
            return
        }
        guard level < Self.projectDepth else { return }
        for child in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard !Task.isCancelled else { return }
            let values = try? child.resourceValues(forKeys: [.isPackageKey])
            guard PathGuard.fold(child.lastPathComponent) != ".git", values?.isPackage != true,
                FileIdentity.read(child)?.volume == volume, !Self.isInsideExclusion(child, context)
            else { continue }
            findProjects(in: child, level: level + 1, volume: volume, rule: rule, context: context, now: now, emit)
        }
    }

    /// The item for `modules`, the `node_modules` of the project at `project`, or `nil` if it is not Developer Junk's to
    /// list: another sub-tool's, refused by the path guard, or with no lockfile next to it (DEV-006).
    private func nodeModulesItem(
        _ modules: URL, project: URL, rule: CleanupRule, context: ScanContext, now: Date
    ) -> ScanItem? {
        guard NodeProject.hasLockfile(in: project), context.ownership.owners(of: modules).contains(id),
            isAllowed(modules, context), let modified = RuleMatch.modificationDate(at: modules)
        else { return nil }
        let warning = NodeProject.warning(in: project)
        // The project's own files say when it was last worked on, not `node_modules` (DEV-006). If that cannot be read to
        // the end, or Shuck cannot tell what a reinstall would lose, the item is listed and never selected.
        let activity = NodeProject.newestActivity(
            in: project, isSkipped: { Self.isInsideExclusion($0, context) }, shouldContinue: { !Task.isCancelled })
        guard !Task.isCancelled, let snapshot = ItemSnapshot.read(modules, while: { !Task.isCancelled }) else {
            return nil
        }
        do {
            return try rule.scanItem(
                at: modules, snapshot: snapshot, modified: modified, source: id, runningApps: context.runningApps,
                now: now, reason: Self.nodeModulesReason(warning), lastActivity: activity,
                unselected: activity == nil || warning != nil, project: project)
        } catch {
            Self.logger.error("Skipped a node_modules folder: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Whether `url` is inside a folder the user excluded. A folder that only holds an exclusion is not: the walk goes
    /// into it, and the path guard refuses an item that holds one (SET-001, D-149).
    private static func isInsideExclusion(_ url: URL, _ context: ScanContext) -> Bool {
        let target = url.pathComponents.map(PathGuard.fold)
        return context.protection.userExclusions.contains { target.starts(with: $0.pathComponents.map(PathGuard.fold)) }
    }
}
