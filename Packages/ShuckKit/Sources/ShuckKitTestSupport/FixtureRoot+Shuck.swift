import Foundation
import ShuckKit

extension FixtureRoot {
    /// The release build's data folder inside the root, which holds the history log the tests' executors write.
    public var historyFolder: URL {
        HistoryLog.folder(home: url, bundleID: ShuckKit.bundleID)
    }

    /// The `.Trash` folder inside the root, where the tests' fake Trash puts items, so they never touch the real Trash
    /// (D-47).
    public var trashFolder: URL {
        url.appending(path: ".Trash")
    }
}

/// The items a sub-tool's scan reports, in the order it reports them.
public func items(from subTool: some SubTool, context: ScanContext) async -> [ScanItem] {
    var items: [ScanItem] = []
    for await event in subTool.scan(context) {
        if case .item(let item) = event { items.append(item) }
    }
    return items
}
