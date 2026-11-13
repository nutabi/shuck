import Foundation

/// Developer Junk's rules for tools that clean their own data: each is a command of the tool, never a deletion of the
/// tool's files (SAF-010, DEV-R03 and DEV-R07 onwards). The tool is found under the scan's tool root (D-124).
extension DeveloperJunk {
    /// The category the package managers' rules share in the confirmation's totals (SAF-003).
    static var packageManagers: ItemCategory {
        ItemCategory(id: "packages", name: LocalizedStringResource("Package managers", bundle: #bundle))
    }

    /// The folder a tool rule's scan sizes its item from, which a run measures before and after the command to report
    /// what it removed (DEV-003, R-07, D-184): the cache of npm, pip and Homebrew. `nil` for any other rule, whose
    /// size is not a folder.
    public static func measuredFolder(ruleID: String, home: URL) -> URL? {
        switch ruleID {
        case "DEV-R07": npmCache(home: home)
        case "DEV-R08": pipCache(home: home)
        case "DEV-R09": homebrewCache(home: home)
        default: nil
        }
    }

    /// The folders an item of the tool rule `ruleID` is sized from or changes, which an exclusion can cover: the rule's
    /// cache folder, for unavailable simulators the folder that holds the simulators, and for Homebrew's cleanup every
    /// folder `brew cleanup` prunes (D-149, D-183). An exclusion on, inside or holding any of them hides the item.
    /// Empty for any other rule. `executable` is the path of the rule's tool, from which Homebrew's prefix is taken.
    static func toolFolders(ruleID: String, home: URL, executable: String?) -> [URL] {
        switch ruleID {
        case "DEV-R03": [simulatorDevices(home: home).deletingLastPathComponent()]
        case "DEV-R07": [npmCache(home: home)]
        case "DEV-R08": [pipCache(home: home)]
        case "DEV-R09": homebrewCleanedFolders(home: home, executable: executable)
        default: []
        }
    }

    /// One item for a tool rule whose data is a cache folder the tool cleans, if the tool is found and the folder
    /// exists. The size is an estimate from measuring the folder, "up to" what the tool may remove: it is never read
    /// from the tool's output, which never chooses a target (DEV-003, R-07, D-125). With `estimates` false the item has
    /// no size, "Size not known" in the app, and the folder is not read: Homebrew's command also removes old versions
    /// outside the cache, so the cache's size would say little (D-NEXT-brew-size).
    func scanToolCache(
        _ rule: CleanupRule, folder: URL, estimates: Bool = true, _ context: ScanContext,
        _ emit: (ScanEvent) -> Void
    ) {
        // A cache folder that is, or holds, an excluded folder is hidden, although the tool, not Shuck, cleans it
        // (SET-001, D-149).
        var executable: String?
        if case .executable(let path) = rule.detection { executable = path }
        let hidden = Self.toolFolders(ruleID: rule.id, home: context.home, executable: executable)
        guard !Task.isCancelled, !hidden.contains(where: { context.protection.overlapsUserExclusion($0) }),
            rule.detection.isAvailable,
            CleanupRule.Detection.folder(folder).isAvailable
        else { return }
        var estimate: Int64 = 0
        if estimates {
            guard let snapshot = ItemSnapshot.read(folder, while: { !Task.isCancelled }) else { return }
            estimate = snapshot.allocatedSize
        }
        do {
            emit(
                .item(
                    try rule.scanItem(
                        estimatedBytes: estimate, source: id, runningApps: context.runningApps)))
        } catch {
            Self.logger.error("Skipped \(rule.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// npm's cache, which `npm cache clean --force` empties. It is in `~/.npm` unless the user's npm settings say
    /// otherwise, which Shuck does not read; without this folder the rule is not listed.
    static func npmCache(home: URL) -> URL {
        home.appending(path: ".npm/_cacache", directoryHint: .isDirectory)
    }

    /// What npm's command runs with besides `PATH` and `HOME`: no check for a newer npm, and offline mode, so the
    /// command makes no network connection (DEV-004, NFR-SEC-001). Emptying the cache needs none.
    static let npmEnvironment = ["NPM_CONFIG_UPDATE_NOTIFIER": "false", "NPM_CONFIG_OFFLINE": "true"]

    /// What pip's command runs with besides `PATH` and `HOME`: no check for a newer pip, which is a network request,
    /// and no question asked, since the command has no input (DEV-004, NFR-SEC-001).
    static let pipEnvironment = ["PIP_DISABLE_PIP_VERSION_CHECK": "1", "PIP_NO_INPUT": "1"]

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
            action: .command(try tools.command(npm, ["cache", "clean", "--force"], extra: npmEnvironment)),
            tier: .rebuildable,
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

    /// pip's cache on macOS, which `pip cache purge` empties. The folder is where pip puts it unless the user's pip
    /// settings say otherwise, which Shuck does not read (D-126, D-127).
    static func pipCache(home: URL) -> URL {
        home.appending(path: "Library/Caches/pip", directoryHint: .isDirectory)
    }

    /// DEV-R08: `pip cache purge`, with the first of `pip` and `pip3` that Homebrew's folders hold. Homebrew's Python
    /// installs `pip3`, and a `pip` link where the user made one. Apple's own `/usr/bin/pip3` is not used: without the
    /// command line tools it is a stub that asks to install them, which a scan must never trigger (D-127).
    static func pipCacheRule(_ tools: ToolLocations) throws(RuleError) -> CleanupRule {
        let pip = tools.executable(["pip", "pip3"], in: ToolLocations.homebrewFolders)
        guard let documentation = URL(string: "https://pip.pypa.io/en/stable/cli/pip_cache/") else {
            throw .invalidDocumentation
        }
        return try CleanupRule(
            id: "DEV-R08", name: LocalizedStringResource("pip Cache", bundle: #bundle),
            description: LocalizedStringResource(
                "Packages and wheels pip has downloaded or built and keeps for the next install.", bundle: #bundle),
            category: packageManagers, detection: .executable(pip),
            action: .command(try tools.command(pip, ["cache", "purge"], extra: pipEnvironment)), tier: .rebuildable,
            selection: .always,
            explanation: LocalizedStringResource(
                "pip's own command empties its cache. It downloads or builds a package again the next time it needs it.",
                bundle: #bundle),
            documentation: documentation)
    }

    func scanPipCache(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard let tools = ToolLocations(context), let rule = try? Self.pipCacheRule(tools) else { return }
        scanToolCache(rule, folder: Self.pipCache(home: context.home), context, emit)
    }

    /// Homebrew's download cache, which `brew cleanup` prunes. The folder is where Homebrew puts it unless
    /// `HOMEBREW_CACHE` says otherwise, which Shuck does not read (D-128).
    static func homebrewCache(home: URL) -> URL {
        home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
    }

    /// Every folder `brew cleanup` changes, which a user exclusion on, inside or holding any of them hides (SET-001,
    /// SAF-010): the download cache, its logs, and Homebrew's prefix as a whole, since the command removes old versions
    /// from the Cellar and Caskroom and also prunes broken links and stale lock files elsewhere in it (the `cleanup`
    /// entry of Homebrew's manual). The prefix is the folder above the `bin` that holds the `brew` the rule runs,
    /// taken from its path without resolving links, so the scan, the model and a run's re-validation agree. Without
    /// the executable only the folders in `home` are returned.
    static func homebrewCleanedFolders(home: URL, executable: String?) -> [URL] {
        var folders = [
            homebrewCache(home: home), home.appending(path: "Library/Logs/Homebrew", directoryHint: .isDirectory),
        ]
        if let executable, !executable.isEmpty {
            folders.append(URL(filePath: executable).deletingLastPathComponent().deletingLastPathComponent())
        }
        return folders
    }

    /// What Homebrew's command runs with besides `PATH` and `HOME`: no analytics and no automatic update, so the command
    /// makes no network connection of its own accord, and no hints in its output (DEV-004, D-128).
    static let homebrewEnvironment = [
        "HOMEBREW_NO_ANALYTICS": "1", "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1",
    ]

    /// DEV-R09: `brew cleanup`, which removes old versions of packages and old downloads, and keeps the current ones.
    /// Shuck never touches the Cellar itself: it is Homebrew's, and `/opt` is protected (DEV-007, section 8.4).
    static func homebrewRule(_ tools: ToolLocations) throws(RuleError) -> CleanupRule {
        let brew = tools.executable("brew", in: ToolLocations.homebrewFolders)
        guard let documentation = URL(string: "https://docs.brew.sh/Manpage") else { throw .invalidDocumentation }
        return try CleanupRule(
            id: "DEV-R09", name: LocalizedStringResource("Homebrew Cleanup", bundle: #bundle),
            description: LocalizedStringResource(
                "Old versions of packages and old downloads that Homebrew keeps.", bundle: #bundle),
            category: packageManagers, detection: .executable(brew),
            action: .command(try tools.command(brew, ["cleanup"], extra: homebrewEnvironment)), tier: .rebuildable,
            selection: .always,
            explanation: LocalizedStringResource(
                "Homebrew's own command removes old versions and old downloads and keeps the current ones. Shuck can't tell beforehand how much that is, so no size is shown. The summary after the run states what was removed.",
                bundle: #bundle),
            documentation: documentation)
    }

    func scanHomebrew(_ context: ScanContext, _ emit: (ScanEvent) -> Void) {
        guard let tools = ToolLocations(context), let rule = try? Self.homebrewRule(tools) else { return }
        // No size before the run (D-NEXT-brew-size); the run measures what it removed (D-184).
        scanToolCache(rule, folder: Self.homebrewCache(home: context.home), estimates: false, context, emit)
    }
}
