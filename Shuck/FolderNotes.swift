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
/// Shuck in (SAF-012, ONB-002). A symbol and words, never color alone. A page that has the folders lists them under
/// the note.
struct NotAccessibleNote: View {
    var folders: [URL] = []

    var body: some View {
        FolderNote(folders: folders, identifier: "not-accessible-folders") {
            Label {
                Text(
                    "Not accessible: macOS kept Shuck out of some folders, so they are not listed. Allow Full Disk Access for Shuck in System Settings, then scan again to include them."
                )
            } icon: {
                Image(systemName: "lock")
            }
        }
    }
}

/// What a page tells if a scan could not read some folders for another reason, such as a disk error (SAF-011).
struct UnreadableNote: View {
    var folders: [URL] = []

    var body: some View {
        FolderNote(folders: folders, identifier: "unreadable-folders") {
            Label("Some folders could not be read", systemImage: "exclamationmark.triangle")
        }
    }
}

/// A note in a strip above a list, with the paths of the folders it is about under it.
private struct FolderNote<Message: View>: View {
    let folders: [URL]
    let identifier: String
    @ViewBuilder let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            message
            ForEach(folders, id: \.self) { folder in
                Text(verbatim: folder.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.leading, 22)
            }
            .accessibilityIdentifier(identifier)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
