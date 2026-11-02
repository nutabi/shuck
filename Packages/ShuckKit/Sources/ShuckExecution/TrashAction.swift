import Foundation
import ShuckKit

/// Moves an item to the Trash: the action for Trash items, the only method "Your data" may be removed by (SAF-004).
package struct TrashAction: PlanAction {
    let trash: any Trash

    package init(trash: any Trash) {
        self.trash = trash
    }

    /// Moves the item to the Trash. The result record gets where it went and the file identity of what was moved,
    /// which a move into the Trash on the same volume keeps, so Restore can tell it from a later item with its name.
    package func act(on item: PlannedItem, at target: URL) -> Acted<ItemOutcome.SkipReason> {
        // Read last, just before the move, so the log records the item that was re-validated and moved (D-84).
        guard let identity = FileIdentity.read(target) else { return Acted(.skipped(.missing)) }
        do {
            let trashed = try trash.trashItem(at: target)
            return Acted(.done(trashed), trashedPath: trashed.path, identity: identity)
        } catch {
            return Acted(.failed(error))
        }
    }
}
