import SwiftUI

/// An item's name and folder, with a trailing detail such as its size. The Move to Trash and Restore sheets use it.
struct ItemRow<Detail: View>: View {
    let url: URL
    let home: URL
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: url.lastPathComponent)
                Text(verbatim: ResultRow.folder(of: url, home: home))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            detail
        }
    }
}
