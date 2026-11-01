/// How an item is reviewed and which methods may act on it (PRD section 8.2, SAF-004).
public enum Tier: String, Codable, Sendable, CaseIterable {
    /// Data that tools rebuild on demand, such as caches. One summary confirmation; Delete or Tool.
    case rebuildable
    /// The user's own data. An itemized review; Trash, Tool or Launchctl, never Delete.
    case yourData

    /// Whether this tier allows `method` (SAF-004). "Your data" is never deleted permanently.
    public func allows(_ method: ActionMethod) -> Bool {
        switch (self, method) {
        case (.rebuildable, .delete), (.rebuildable, .tool): true
        case (.yourData, .trash), (.yourData, .tool), (.yourData, .launchctl): true
        default: false
        }
    }
}

/// How an action removes or changes an item (PRD section 8.1). Each rule or action declares its method.
public enum ActionMethod: String, Codable, Sendable, CaseIterable {
    /// Move to the Trash; restorable.
    case trash
    /// Delete permanently; not restorable.
    case delete
    /// Run the owning tool's documented clean command; not restorable (SAF-010).
    case tool
    /// Unload, disable or enable a user's launchd job; reversed by the opposite action.
    case launchctl
}
