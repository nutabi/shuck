import Foundation

/// "What is taking the most space?": personal files whose allocated size is at least a minimum, whatever their age
/// (LRG-001).
public struct LargeFiles: PersonalFilesSubTool {
    /// 500 MB, the default minimum size (LRG-001, SET-002).
    public static let defaultMinimumSize: Int64 = 500_000_000

    /// Files smaller than this, in allocated bytes (SAF-013), are not listed.
    public let minimumSize: Int64

    public init(minimumSize: Int64 = defaultMinimumSize) {
        self.minimumSize = minimumSize
    }

    public var info: ToolInfo {
        ToolInfo(
            id: .largeFiles, name: LocalizedStringResource("Large Files", bundle: #bundle),
            summary: LocalizedStringResource("What is taking the most space?", bundle: #bundle),
            symbolName: "scalemass", availability: .available)
    }

    public func includes(_ file: PersonalFile) -> Bool {
        file.snapshot.allocatedSize >= minimumSize
    }

    public func reason(for file: PersonalFile) -> LocalizedStringResource {
        let minimum = minimumSize.formatted(.byteCount(style: .file))
        return LocalizedStringResource("At least \(minimum)", bundle: #bundle)
    }
}
