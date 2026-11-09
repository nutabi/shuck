import ShuckExecution
import ShuckKit
import SwiftUI

/// The items a run did not act on, each with why, under a heading (SAF-011). Move to Trash's and the summary
/// confirmation's reports share it, so a skipped or failed item reads the same in both.
struct OutcomeList: View {
    let title: Text
    let outcomes: [ItemOutcome]
    /// The home folder, shown as `~` in folder paths.
    let home: URL

    var body: some View {
        title
            .font(.headline)
        List(outcomes, id: \.item.id) { outcome in
            ItemRow(target: outcome.item.target, home: home) {
                Text(OutcomeWording.result(of: outcome))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.bordered)
    }
}
