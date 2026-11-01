import ShuckKit
import SwiftUI

/// Stands in for a tool's page until its milestone builds it.
struct PlaceholderView: View {
    let label: DestinationLabel

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(label.name)
            } icon: {
                Image(systemName: label.symbolName)
            }
        } description: {
            Text(label.summary)
        } actions: {
            if case .planned(let milestone) = label.availability {
                Text("Planned for milestone \(milestone).")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text(label.name))
    }
}

#Preview {
    if let info = ToolRegistry.standard.info(.largeFiles) {
        PlaceholderView(label: DestinationLabel(info))
    }
}
