import ShuckKit
import SwiftUI

/// An item's name and folder, with a trailing detail such as its size. The Move to Trash and Restore sheets use it.
struct ItemRow<Detail: View>: View {
    let target: ItemTarget
    let home: URL
    @ViewBuilder let detail: Detail

    init(url: URL, home: URL, @ViewBuilder detail: () -> Detail) {
        self.init(target: .path(url), home: home, detail: detail)
    }

    init(target: ItemTarget, home: URL, @ViewBuilder detail: () -> Detail) {
        self.target = target
        self.home = home
        self.detail = detail()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                switch target {
                case .path(let url):
                    Text(verbatim: url.lastPathComponent)
                    Text(verbatim: ResultRow.folder(of: url, home: home))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .command(let command):
                    Text(verbatim: command.commandLine)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
            Spacer()
            detail
        }
    }
}
