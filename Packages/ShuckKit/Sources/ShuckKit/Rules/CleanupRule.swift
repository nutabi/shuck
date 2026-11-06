import Foundation

/// One category in a rebuildable review's totals (SAF-003). Its stable ID is independent of its localized name.
public struct ItemCategory: Equatable, Sendable {
    public let id: String
    public let name: LocalizedStringResource

    public init(id: String, name: LocalizedStringResource) {
        self.id = id
        self.name = name
    }
}

/// Default selection only: a recent item may still be selected explicitly (DEV-005).
public enum RuleSelection: Equatable, Sendable {
    case never
    case always
    case modifiedAtLeast(days: Int)

    public func selects(modified: Date?, now: Date) -> Bool {
        switch self {
        case .never: false
        case .always: true
        case .modifiedAtLeast(let days):
            modified.map { now.timeIntervalSince($0) >= Double(days) * 86_400 } ?? false
        }
    }
}

/// Rules are engine data, validated when constructed (DEV-001). No built-in rule is enabled here: M2-T05 onwards
/// adds each one with its scanner, ownership entries and fixture tests.
public struct CleanupRule: Equatable, Sendable {
    public enum Detection: Equatable, Sendable {
        case folder(URL)
        case executable(String)

        /// Read-only detection; missing tools and data hide their rules (DEV-002).
        public var isAvailable: Bool {
            switch self {
            case .folder(let url):
                guard let resolved = ResolvedPath.realPath(url) else { return false }
                let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
                return attributes?[.type] as? FileAttributeType == .typeDirectory
            case .executable(let path):
                // Homebrew and language tools commonly install symlinked executables. Detection follows the link,
                // verifies the final file and reads no directory contents; it never grants permission to delete it.
                guard let resolved = ResolvedPath.realPath(URL(filePath: path)) else { return false }
                let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
                return attributes?[.type] as? FileAttributeType == .typeRegular
                    && FileManager.default.isExecutableFile(atPath: resolved.path)
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case paths([RulePath], method: ActionMethod, scope: ItemScope = .item)
        case command(ToolCommand)

        public var method: ActionMethod {
            switch self {
            case .paths(_, let method, _): method
            case .command: .tool
            }
        }
    }

    public let id: String
    public let name: LocalizedStringResource
    public let description: LocalizedStringResource
    public let category: ItemCategory
    public let detection: Detection
    public let action: Action
    public let tier: Tier
    public let selection: RuleSelection
    public let explanation: LocalizedStringResource
    public let documentation: URL

    public init(
        id: String, name: LocalizedStringResource, description: LocalizedStringResource, category: ItemCategory,
        detection: Detection, action: Action, tier: Tier, selection: RuleSelection,
        explanation: LocalizedStringResource, documentation: URL
    ) throws(RuleError) {
        guard !id.isEmpty else { throw .emptyID }
        guard tier.allows(action.method) else { throw .methodNotAllowed }
        switch detection {
        case .folder(let url):
            guard url.isFileURL, url.path.hasPrefix("/"), !url.pathComponents.contains("..") else {
                throw .invalidDetection
            }
        case .executable(let path):
            guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else {
                throw .invalidDetection
            }
        }
        if case .command(let command) = action, detection != .executable(command.executable) {
            throw .invalidDetection
        }
        if case .paths(let paths, let method, let scope) = action {
            guard !paths.isEmpty else { throw .invalidPath }
            guard method == .trash || method == .delete else { throw .pathMethodNotAllowed }
            guard scope != .contents || method == .delete else { throw .contentsNotAllowed }
        }
        if case .modifiedAtLeast(let days) = selection, days <= 0 { throw .invalidStaleness }
        guard tier != .yourData || selection == .never else { throw .yourDataSelected }
        guard documentation.scheme.map({ ["https", "http"].contains($0) }) == true, documentation.host != nil else {
            throw .invalidDocumentation
        }
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.detection = detection
        self.action = action
        self.tier = tier
        self.selection = selection
        self.explanation = explanation
        self.documentation = documentation
    }
}

public enum RuleError: Error, Equatable {
    case emptyID
    case invalidPath
    case invalidDetection
    case methodNotAllowed
    case pathMethodNotAllowed
    case contentsNotAllowed
    case invalidStaleness
    case yourDataSelected
    case invalidDocumentation
}
