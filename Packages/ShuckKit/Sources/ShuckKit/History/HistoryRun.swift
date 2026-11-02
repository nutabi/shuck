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

        /// The original path; for a restore, where the item went (D-52).
        public let path: String
        /// Where the item went in the Trash; for a restore, where it came from.
        public let trashedPath: String?
        /// The allocated size estimate in bytes.
        public let bytes: Int64?
        public let tier: Tier
        public let outcome: Outcome
        /// Whether Restore can undo the item now, for an item that succeeded and is not itself a restore (HIS-004).
        public let restorability: Restorability?

        public init(
            path: String, trashedPath: String?, bytes: Int64?, tier: Tier, outcome: Outcome,
            restorability: Restorability?
        ) {
            self.path = path
            self.trashedPath = trashedPath
            self.bytes = bytes
            self.tier = tier
            self.outcome = outcome
            self.restorability = restorability
        }
    }

    /// The run ID.
    public let id: UUID
    /// The sub-tool or tool that ran: ``ToolID/history`` for a restore.
    public let tool: ToolID
    public let operation: HistoryRecord.Operation
    /// When the run logged its first record.
    public let started: Date
    /// The items in the order the run logged them.
    public let items: [Item]

    public init(id: UUID, tool: ToolID, operation: HistoryRecord.Operation, started: Date, items: [Item]) {
        self.id = id
        self.tool = tool
        self.operation = operation
        self.started = started
        self.items = items
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
    public func runs() -> [HistoryRun] {
        // What Restore can undo, for each successful result that is not a restore, in log order.
        var undoable = entries().makeIterator()
        var nextEntry = undoable.next()

        var order: [UUID] = []
        var runs: [UUID: (first: HistoryRecord, items: [HistoryRun.Item])] = [:]
        // The open intent records of each run, by path: the index of their item.
        var open: [UUID: [String: Int]] = [:]
        for record in records {
            if runs[record.run] == nil {
                order.append(record.run)
                runs[record.run] = (record, [])
            }
            switch record.phase {
            case .intent:
                open[record.run, default: [:]][record.path] = runs[record.run]?.items.count
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
                } else {
                    runs[record.run]?.items.append(item)
                }
            }
        }
        return order.compactMap { id in
            runs[id].map { run in
                HistoryRun(
                    id: id, tool: run.first.tool, operation: run.first.operation, started: run.first.timestamp,
                    items: run.items)
            }
        }
    }

    private static func item(_ record: HistoryRecord, outcome: HistoryRun.Item.Outcome, restorability: Restorability?)
        -> HistoryRun.Item
    {
        HistoryRun.Item(
            path: record.path, trashedPath: record.trashedPath, bytes: record.bytes, tier: record.tier,
            outcome: outcome, restorability: restorability)
    }

    private static func outcome(of result: HistoryRecord) -> HistoryRun.Item.Outcome {
        switch result.status {
        case .ok: .succeeded
        case .skipped: .skipped(result.detail)
        case .failed, nil: .failed(result.detail)
        }
    }
}
