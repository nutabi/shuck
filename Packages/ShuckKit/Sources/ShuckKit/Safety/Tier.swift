/// How an item is reviewed and which methods may act on it (PRD section 8.2, SAF-004).
public enum Tier: String, Codable, Sendable {
    /// Data that tools rebuild on demand, such as caches. One summary confirmation; Delete or Tool.
    case rebuildable
    /// The user's own data. An itemized review; Trash, Tool or Launchctl, never Delete.
    case yourData
}
