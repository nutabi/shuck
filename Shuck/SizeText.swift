import ShuckKit
import SwiftUI

/// The size next to an item: a file's allocated size, or for a tool's command an estimate, which is "up to" what the
/// tool might remove, or "not known" when Shuck has no way to measure it (DEV-003, SAF-013, D-125).
///
/// The estimate comes from measuring the tool's cache folder. It is never read from the tool's output (R-07).
///
/// A folder whose size could not be measured fully, because a folder inside it could not be read, reads "At least"
/// instead: the number is a lower bound (SAF-012, D-195). That is display only. It changes nothing a plan
/// accepts, what is selected or what a run does.
struct SizeText: View {
    let target: ItemTarget
    let bytes: Int64
    /// `false` when `bytes` is smaller than the real size, because part of the item could not be read.
    let isComplete: Bool

    init(target: ItemTarget, bytes: Int64, isComplete: Bool = true) {
        self.target = target
        self.bytes = bytes
        self.isComplete = isComplete
    }

    /// The size of an item with the `snapshot` its scan took, if it has one: a tool's command has none.
    init(target: ItemTarget, bytes: Int64, snapshot: ItemSnapshot?) {
        self.init(target: target, bytes: bytes, isComplete: Self.isComplete(snapshot))
    }

    /// Whether `snapshot` measured the whole item. An item without a snapshot has no lower bound to state.
    static func isComplete(_ snapshot: ItemSnapshot?) -> Bool {
        snapshot?.isComplete ?? true
    }

    var body: some View {
        Group {
            switch target {
            case .path:
                if isComplete {
                    Text(bytes, format: .byteCount(style: .file))
                } else {
                    // The words carry the meaning, not a color or a symbol, and VoiceOver reads them (NFR-A11Y-001).
                    Text("At least \(bytes, format: .byteCount(style: .file))")
                        .help("Some folders inside could not be read, so this is not the whole size.")
                }
            case .command:
                if bytes > 0 {
                    Text("Up to \(bytes, format: .byteCount(style: .file))")
                } else {
                    Text("Size not known")
                }
            }
        }
        .monospacedDigit()
    }
}
