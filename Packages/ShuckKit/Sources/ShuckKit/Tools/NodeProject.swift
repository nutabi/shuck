import Darwin
import Foundation

/// What Developer Junk reads about one Node.js project to judge its `node_modules` (DEV-006, DEV-R06): which lockfile
/// sits next to it, whether a reinstall would restore it, and when the project's own files last changed. Only reads, and
/// what it reads decides selection and a warning, never a deletion target (R-07).
enum NodeProject {
    /// The files a package manager writes next to `node_modules` to install the same packages again (DEV-006).
    static let lockfiles = [
        "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb",
    ]

    /// Entries the walk for the newest file reads before it gives up (see ``newestActivity(in:isSkipped:shouldContinue:)``).
    static let activityLimit = 100_000

    /// A `package.json` larger than this is not read.
    static let manifestLimit = 2 << 20

    /// What a reinstall would not restore, or why Shuck cannot tell (DEV-006).
    enum Warning: Equatable {
        /// The project patches its packages with patch-package after each install, which only an install script redoes.
        case patchPackage
        /// A dependency is a local folder (`file:`), which a reinstall copies again from wherever it is now.
        case fileLinks
        case patchPackageAndFileLinks
        /// `package.json` exists but Shuck could not read it, so it cannot tell.
        case unreadable
    }

    /// Whether `folder` holds one of the ``lockfiles`` as a regular file, not a link.
    static func hasLockfile(in folder: URL) -> Bool {
        lockfiles.contains { name in
            ModificationDate.status(of: folder.appending(path: name)).map { $0.st_mode & S_IFMT == S_IFREG } ?? false
        }
    }

    /// The warning for the project at `folder`, or `nil` if nothing in `package.json` or `patches/` says a reinstall
    /// would lose something. A project without a `package.json` has none to read.
    static func warning(in folder: URL) -> Warning? {
        var patches = hasPatchFiles(in: folder.appending(path: "patches", directoryHint: .isDirectory))
        var links = false
        let manifest = folder.appending(path: "package.json")
        if let info = ModificationDate.status(of: manifest) {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_size <= manifestLimit,
                let data = try? Data(contentsOf: manifest),
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return .unreadable }
            let sections = ["dependencies", "devDependencies", "optionalDependencies"].compactMap {
                json[$0] as? [String: Any]
            }
            patches = patches || sections.contains { $0["patch-package"] != nil }
            links = sections.contains { section in
                section.values.contains { ($0 as? String)?.lowercased().hasPrefix("file:") == true }
            }
            patches =
                patches || (json["scripts"] as? [String: Any])?.values.contains(where: mentionsPatchPackage) == true
        }
        switch (patches, links) {
        case (true, true): return .patchPackageAndFileLinks
        case (true, false): return .patchPackage
        case (false, true): return .fileLinks
        case (false, false): return nil
        }
    }

    private static func mentionsPatchPackage(_ script: Any) -> Bool {
        (script as? String)?.contains("patch-package") == true
    }

    /// patch-package keeps one `name+version.patch` file per patched package in `patches/`.
    private static func hasPatchFiles(in folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.hasSuffix(".patch") && $0.contains("+") }
    }

    /// The newest modification date among the regular files of the project at `folder`, without `node_modules`, `.git`,
    /// `.DS_Store` (Finder touches it), links, other volumes and what `isSkipped` says (an excluded folder). A folder's
    /// own date is not a file's: it changes when something is added or removed (D-112). `nil` if the walk stops before
    /// the end, because it read more than ``activityLimit`` entries or `shouldContinue` said no: a date that may be
    /// too old must not make a project look stale.
    static func newestActivity(
        in folder: URL, limit: Int = activityLimit, isSkipped: (URL) -> Bool, shouldContinue: () -> Bool
    ) -> Date? {
        guard let start = ModificationDate.status(of: folder) else { return nil }
        let volume = start.st_dev
        var newest: Date?
        var pending = [folder]
        var read = 0
        while let directory = pending.popLast() {
            guard shouldContinue(),
                let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
            else { return nil }
            for name in names {
                read += 1
                guard read <= limit else { return nil }
                let folded = PathGuard.fold(name)
                guard folded != ".git", folded != ".ds_store", folded != OwnershipMap.dependenciesFolderName else {
                    continue
                }
                let url = directory.appending(path: name)
                guard let info = ModificationDate.status(of: url) else { continue }
                switch info.st_mode & S_IFMT {
                case S_IFREG: newest = max(newest ?? .distantPast, ModificationDate.date(info))
                case S_IFDIR where info.st_dev == volume && !isSkipped(url): pending.append(url)
                default: break
                }
            }
        }
        return newest
    }
}
