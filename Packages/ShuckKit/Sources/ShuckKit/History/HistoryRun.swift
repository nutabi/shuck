import Foundation

/// One run from the history log, with every item it logged, as the History view lists it (HIS-002).
///
/// A run is one execution of a plan, or one restore (PRD section 8.1). Every item it logged is listed, including the
/// ones it skipped or that failed, with the reason (SAF-011). An item whose intent record has no result record, as
/// after a crash, is ``Item/Outcome/interrupted``: the log cannot tell whether it changed (HIS-001).
public struct HistoryRun: Equatable, Sendable, Identifiable {
    /// One logged item of a run.
    public struct Item: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            case succeeded
            /// The text is the logged reason.
            case skipped(String?)
            /// The text is the logged error.
            case failed(String?)
            /// An intent record without a result record.
            case interrupted
        }

        /// What was done to the item, or was to be done. A plan may mix methods, so the items of one run may differ
        /// (D-89).
        public let operation: HistoryRecord.Operation
        /// The original path; for a restore, where the item went (D-52). For a `tool` item, the quoted command
        /// (``LoggedCommand``); for `launchctl`, the job label. History shows each as its own kind of item (#63).
        public let path: String
        /// Where the item went in the Trash; for a restore, where it came from.
        public let trashedPath: String?
        /// The allocated size estimate in bytes.
        public let bytes: Int64?
        public let tier: Tier
        public let outcome: Outcome
        /// Whether Restore can undo the item now, for an item that succeeded and is not itself a restore (HIS-004).
        public let restorability: Restorability?
        /// The end of what a tool printed, for a `tool` item that logged some. It is not part of the outcome's text,
        /// which History words (#63, D-115).
        public let toolOutput: String?

        public init(
            operation: HistoryRecord.Operation, path: String, trashedPath: String?, bytes: Int64?, tier: Tier,
            outcome: Outcome, restorability: Restorability?, toolOutput: String? = nil
        ) {
            self.operation = operation
            self.path = path
            self.trashedPath = trashedPath
            self.bytes = bytes
            self.tier = tier
            self.outcome = outcome
            self.restorability = restorability
            self.toolOutput = toolOutput
        }
    }

    /// The run ID.
    public let id: UUID
    /// The sub-tool or tool that ran: ``ToolID/history`` for a restore.
    public let tool: ToolID
    /// When the run logged its first record.
    public let started: Date
    /// The items in the order the run logged them.
    public let items: [Item]

    public init(id: UUID, tool: ToolID, started: Date, items: [Item]) {
        self.id = id
        self.tool = tool
        self.started = started
        self.items = items
    }

    /// What the run did, each operation once, in the order its items first used it: one for most runs, several for a
    /// run whose plan mixed methods, such as Delete and Tool (HIS-002, D-89).
    public var operations: [HistoryRecord.Operation] {
        items.reduce(into: []) { operations, item in
            if !operations.contains(item.operation) { operations.append(item.operation) }
        }
    }

    /// The size of the items that succeeded, in bytes (SAF-013).
    public var succeededBytes: Int64 {
        items.filter { $0.outcome == .succeeded }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    public var succeededCount: Int {
        items.count(where: { $0.outcome == .succeeded })
    }
}

extension HistoryLog.Contents {
    /// Every run in the log, in the order each run started (HIS-002).
    ///
    /// An item's result record closes the latest open intent record of its run with the same path. Both name the same
    /// path, for a restore too (D-52).
    ///
    /// An intent record of a Trash item with no result, from a quit or crash, is shown as restorable when
    /// `trashFolder`, the folder the Trash moves items into, holds the item (HIS-001, SAF-005): see
    /// ``Restorability/interruptedTrash(_:in:)``. Without a `trashFolder`, such an item stays interrupted.
    public func runs(trashFolder: URL? = nil) -> [HistoryRun] {
        // What Restore can undo, for each successful result that is not a restore, in log order.
        var undoable = entries().makeIterator()
        var nextEntry = undoable.next()

        var order: [UUID] = []
        var runs: [UUID: (first: HistoryRecord, items: [HistoryRun.Item])] = [:]
        // The open intent records of each run, by path: the index of their item.
        var open: [UUID: [String: Int]] = [:]
        // The intent records still open, to look for their items in the Trash at the end.
        var interrupted: [UUID: [Int: HistoryRecord]] = [:]
        for record in records {
            if runs[record.run] == nil {
                order.append(record.run)
                runs[record.run] = (record, [])
            }
            switch record.phase {
            case .intent:
                let index = runs[record.run]?.items.count ?? 0
                open[record.run, default: [:]][record.path] = index
                if record.operation == .trash, record.identity != nil {
                    interrupted[record.run, default: [:]][index] = record
                }
                runs[record.run]?.items.append(Self.item(record, outcome: .interrupted, restorability: nil))
            case .result:
                var itemRestorability: Restorability?
                // entries() lists exactly the successful results that are not restores, in log order.
                if let entry = nextEntry, entry.record == record {
                    itemRestorability = entry.restorability
                    nextEntry = undoable.next()
                }
                let item = Self.item(record, outcome: Self.outcome(of: record), restorability: itemRestorability)
                if let index = open[record.run]?.removeValue(forKey: record.path) {
                    runs[record.run]?.items[index] = item
                    interrupted[record.run]?[index] = nil
                } else {
                    runs[record.run]?.items.append(item)
                }
            }
        }
        if let trashFolder {
            var trash = TrashListing(folder: trashFolder)
            for (run, records) in interrupted {
                for (index, record) in records {
                    guard let item = runs[run]?.items[index],
                        let restorability = Restorability.interruptedTrash(record, in: &trash)
                    else { continue }
                    runs[run]?.items[index] = HistoryRun.Item(
                        operation: item.operation, path: item.path, trashedPath: item.trashedPath, bytes: item.bytes,
                        tier: item.tier, outcome: item.outcome, restorability: restorability)
                }
            }
        }
        return order.compactMap { id in
            runs[id].map { run in
                HistoryRun(id: id, tool: run.first.tool, started: run.first.timestamp, items: run.items)
            }
        }
    }

    private static func item(_ record: HistoryRecord, outcome: HistoryRun.Item.Outcome, restorability: Restorability?)
        -> HistoryRun.Item
    {
        HistoryRun.Item(
            operation: record.operation, path: record.path, trashedPath: record.trashedPath, bytes: record.bytes,
            tier: record.tier, outcome: outcome, restorability: restorability,
            toolOutput: record.operation == .tool ? record.detail.flatMap { ToolRunDetail($0).output } : nil)
    }

    /// A tool's output is kept apart from the outcome's text (D-115).
    private static func outcome(of result: HistoryRecord) -> HistoryRun.Item.Outcome {
        let detail = result.operation == .tool ? result.detail.map { ToolRunDetail($0).summary } : result.detail
        return switch result.status {
        case .ok: .succeeded
        case .skipped: .skipped(detail)
        case .failed, nil: .failed(detail)
        }
    }
}
