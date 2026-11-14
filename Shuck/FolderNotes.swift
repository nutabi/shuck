import AppKit
import SwiftUI

/// Opens Finder with items selected. It only shows them; nothing is moved.
enum FinderReveal {
    static func show(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// What a page tells before its list if macOS kept the scan out of some folders: what is missing and how to let
/// Shuck in (SAF-012, ONB-002). A symbol and words, never color alone.
struct NotAccessibleNote: View {
    var body: some View {
        Label {
            Text(
                "Not accessible: macOS kept Shuck out of some folders, so they are not listed. Allow Full Disk Access for Shuck in System Settings, then scan again to include them."
            )
        } icon: {
            Image(systemName: "lock")
        }
        .noteBar()
    }
}

/// What a page tells if a scan could not read some folders for another reason, such as a disk error (SAF-011).
struct UnreadableNote: View {
    var body: some View {
        Label("Some folders could not be read", systemImage: "exclamationmark.triangle")
            .noteBar()
    }
}

extension View {
    /// The strip a note sits in above or below a list.
    fileprivate func noteBar() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
    }
}
