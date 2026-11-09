import ShuckKit
import SwiftUI

/// The size next to an item: a file's allocated size, or for a tool's command an estimate, which is "up to" what the
/// tool might remove, or "not known" when Shuck has no way to measure it (DEV-003, SAF-013, D-125).
///
/// The estimate comes from measuring the tool's cache folder. It is never read from the tool's output (R-07).
struct SizeText: View {
    let target: ItemTarget
    let bytes: Int64

    var body: some View {
        Group {
            switch target {
            case .path:
                Text(bytes, format: .byteCount(style: .file))
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
