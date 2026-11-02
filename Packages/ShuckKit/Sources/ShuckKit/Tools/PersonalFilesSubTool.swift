import Foundation

/// A sub-tool that lists personal files: Large Files or Old Files (FCL-008).
///
/// Both share one personal-files scan and its item state (FCL-006). The app runs ``PersonalFilesScanner`` once and asks
/// each sub-tool which files it lists with ``includes(_:)``. The sub-tool's own ``SubTool/scan(_:)`` runs a scan of its
/// own, for callers that need one sub-tool only, such as the safety pipeline's tests (FCL-003).
public protocol PersonalFilesSubTool: SubTool {
    /// Whether the sub-tool lists `file`. Read-only files are listed too, but never become items (FCL-011).
    func includes(_ file: PersonalFile) -> Bool
    /// Why `file` is listed, shown next to it.
    func reason(for file: PersonalFile) -> LocalizedStringResource
    /// Looks up last-opened dates during the scan, for a sub-tool that lists files by them (OLD-002). `nil` for the
    /// others, so the scan spends no time on lookups for them.
    var lastOpenedReader: LastOpenedReader? { get }
}

extension PersonalFilesSubTool {
    public var lastOpenedReader: LastOpenedReader? { nil }

    /// Personal files are "Your data", moved to the Trash (LRG-004, OLD-004).
    public var tiers: Set<Tier> { [.yourData] }

    /// The home folder. The path guard and the protected locations still apply inside it (SAF-007).
    public func allowedRoots(home: URL) -> [URL] { [home] }

    /// `file` as this sub-tool's item, or `nil` if the sub-tool does not list it or it is read-only.
    public func scanItem(for file: PersonalFile) -> ScanItem? {
        guard includes(file) else { return nil }
        return file.scanItem(source: id, reason: reason(for: file))
    }

    /// Runs a personal-files scan and streams the items this sub-tool lists. Cancelling the consuming task cancels
    /// the scan (SAF-014).
    public func scan(_ context: ScanContext) -> AsyncStream<ScanEvent> {
        let events = PersonalFilesScanner(context: context, lastOpened: lastOpenedReader).scan()
        return AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    switch event {
                    case .files(let files):
                        for item in files.compactMap(scanItem(for:)) {
                            continuation.yield(.item(item))
                        }
                    case .notAccessible(let url):
                        continuation.yield(.notAccessible(url))
                    case .unreadable(let url):
                        continuation.yield(.unreadable(url))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
