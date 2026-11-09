import Foundation

/// What an item acts on. Tool cleanup has no pretend file path: the reviewed command is its target (SAF-001).
public enum ItemTarget: Equatable, Hashable, Sendable {
    case path(URL)
    case command(ToolCommand)

    public var url: URL? {
        if case .path(let url) = self { url } else { nil }
    }

    /// The path, or the exact command for review, errors and the history log (SAF-006).
    public var description: String {
        switch self {
        case .path(let url): url.path
        case .command(let command): command.display
        }
    }
}

/// Whether an item starts selected, or why it cannot be selected. A recent item is unselected but selectable
/// (DEV-005); an item belonging to a running app is disabled (``appIsRunning``, SAF-009).
public enum ItemSelection: Equatable, Sendable {
    case unselected
    case selected
    case disabled(LocalizedStringResource)

    public var isSelectable: Bool {
        if case .disabled = self { false } else { true }
    }

    public var disabledReason: LocalizedStringResource? {
        if case .disabled(let reason) = self { reason } else { nil }
    }
}

extension ItemCategory {
    /// Existing personal-file scans have one category and never select anything by default (D-10).
    public static var personalFiles: ItemCategory {
        ItemCategory(id: "personalFiles", name: LocalizedStringResource("Personal files", bundle: #bundle))
    }
}
