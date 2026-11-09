import Foundation

/// Developer Junk's rules for tools that clean their own data: each is a command of the tool, never a deletion of the
/// tool's files (SAF-010, DEV-R03 and DEV-R07 onwards). The tool is found under the scan's tool root (D-124).
extension DeveloperJunk {
    /// The category the package managers' rules share in the confirmation's totals (SAF-003).
    static var packageManagers: ItemCategory {
        ItemCategory(id: "packages", name: LocalizedStringResource("Package managers", bundle: #bundle))
    }

    /// One item for a tool rule whose data is a cache folder the tool cleans, if the tool is found and the folder
    /// exists. The size is an estimate from measuring the folder, "up to" what the tool may remove: it is never read
    /// from the tool's output, which never chooses a target (DEV-003, R-07, D-125).
    func scanToolCache(_ rule: CleanupRule, folder: URL, _ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard !Task.isCancelled, rule.detection.isAvailable, CleanupRule.Detection.folder(folder).isAvailable,
            let snapshot = ItemSnapshot.read(folder, while: { !Task.isCancelled })
        else { return }
        do {
            emit(
                .item(
                    try rule.scanItem(
                        estimatedBytes: snapshot.allocatedSize, source: id, runningApps: context.runningApps)))
        } catch {
            Self.logger.error("Skipped \(rule.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// npm's cache, which `npm cache clean --force` empties. It is in `~/.npm` unless the user's npm settings say
    /// otherwise, which Shuck does not read; without this folder the rule is not listed.
    static func npmCache(home: URL) -> URL {
        home.appending(path: ".npm/_cacache", directoryHint: .isDirectory)
    }

    /// DEV-R07: `npm cache clean --force` (`--force` is what npm requires to clean its cache at all). npm downloads
    /// what it needs again, so the item is selected (D-125).
    static func npmCacheRule(_ tools: ToolLocations) throws(RuleError) -> CleanupRule {
        let npm = tools.executable("npm", in: ToolLocations.homebrewFolders)
        guard let documentation = URL(string: "https://docs.npmjs.com/cli/commands/npm-cache") else {
            throw .invalidDocumentation
        }
        return try CleanupRule(
            id: "DEV-R07", name: LocalizedStringResource("npm Cache", bundle: #bundle),
            description: LocalizedStringResource(
                "Packages npm has downloaded and keeps so it can install them again faster.", bundle: #bundle),
            category: packageManagers, detection: .executable(npm),
            action: .command(try tools.command(npm, ["cache", "clean", "--force"])), tier: .rebuildable,
            selection: .always,
            explanation: LocalizedStringResource(
                "npm's own command empties its cache. It downloads a package again the next time a project needs it.",
                bundle: #bundle),
            documentation: documentation)
    }

    func scanNpmCache(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard let tools = ToolLocations(context), let rule = try? Self.npmCacheRule(tools) else { return }
        scanToolCache(rule, folder: Self.npmCache(home: context.home), context, emit)
    }
}
