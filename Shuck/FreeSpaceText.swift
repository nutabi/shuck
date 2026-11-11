import ShuckExecution
import ShuckKit
import SwiftUI

/// Reads the bytes free on the scanned volume, or `nil` if macOS doesn't say (SAF-013). The app passes
/// ``AppEnvironment/availableSpace()``; tests pass a stub.
typealias ReadFreeSpace = @Sendable () -> Int64?

extension FreeSpaceChange {
    /// The change between two readings around `report`'s run, or `nil` if either reading is missing. The estimate is
    /// what the run deleted and the estimates of the tools it ran to the end; what it moved to the Trash frees nothing
    /// yet.
    nonisolated init?(before: Int64?, after: Int64?, report: RunReport) {
        guard let before, let after else { return nil }
        var deleted: Int64 = 0
        var toolEstimate: Int64?
        var toolSizeUnknown = false
        for outcome in report.outcomes {
            guard case .done = outcome.result else { continue }
            switch outcome.item.method {
            case .delete: deleted += outcome.item.allocatedSize
            // A tool without an estimate has a size of zero: "Size not known" (D-125).
            case .tool where outcome.item.allocatedSize == 0: toolSizeUnknown = true
            case .tool: toolEstimate = (toolEstimate ?? 0) + outcome.item.allocatedSize
            default: break
            }
        }
        self.init(
            before: before, after: after, deleted: deleted, toolEstimate: toolEstimate, toolSizeUnknown: toolSizeUnknown
        )
    }
}

/// The measured change in free space in a run's summary, under the estimate the summary states, and why the two can
/// differ (SAF-013, R-06).
struct FreeSpaceText: View {
    let change: FreeSpaceChange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if change.measured > 0 {
                Text("Measured on the disk, free space grew by \(change.measured, format: .byteCount(style: .file)).")
            } else {
                Text("Measured on the disk, free space didn't grow.")
            }
            ForEach(change.gaps, id: \.self) { gap in
                Self.explanation(of: gap)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func explanation(of gap: FreeSpaceChange.Gap) -> Text {
        switch gap {
        case .snapshotsAndClones:
            Text(
                "Local Time Machine snapshots and APFS clones can keep deleted data on the disk, so less space may be freed until macOS removes them."
            )
        case .toolEstimate:
            Text("A tool's size is the most it may remove, so it can free less.")
        case .toolSizeUnknown:
            Text(
                "Shuck doesn't know how much a tool removes when its size is not known, so the estimate leaves it out.")
        case .otherActivity:
            Text(
                "macOS and other apps also use and free space while Shuck runs, and macOS frees purgeable space when it needs it."
            )
        }
    }
}
