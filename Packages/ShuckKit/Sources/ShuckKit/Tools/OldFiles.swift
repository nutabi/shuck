import Foundation

/// "What haven't I opened in a long time?": personal files not opened for at least a period, and at least a minimum
/// size, so the list stays focused on space (OLD-001).
///
/// "Last opened" is Spotlight's last-used date, or the modified date when Spotlight has none (OLD-002).
public struct OldFiles: PersonalFilesSubTool {
    /// 12 months, the default period (OLD-001, SET-002).
    public static let defaultPeriodMonths = 12
    /// The periods Settings offers (OLD-001). Any other number of months is a custom value.
    public static let presetPeriodMonths = [3, 6, 12, 24]
    /// 50 MB, the default minimum size (OLD-001, SET-002).
    public static let defaultMinimumSize: Int64 = 50_000_000

    /// Files opened within this many months are not listed.
    public let periodMonths: Int
    /// Files smaller than this, in allocated bytes (SAF-013), are not listed. Can be 0.
    public let minimumSize: Int64
    private let lastUsedDate: LastOpenedReader.LastUsedDate

    /// - Parameter lastUsedDate: Reads Spotlight's last-used date; tests stub it.
    public init(
        periodMonths: Int = defaultPeriodMonths, minimumSize: Int64 = defaultMinimumSize,
        lastUsedDate: @escaping LastOpenedReader.LastUsedDate = LastOpenedReader.spotlightLastUsedDate
    ) {
        self.periodMonths = periodMonths
        self.minimumSize = minimumSize
        self.lastUsedDate = lastUsedDate
    }

    public var info: ToolInfo {
        ToolInfo(
            id: .oldFiles, name: LocalizedStringResource("Old Files", bundle: #bundle),
            summary: LocalizedStringResource("What haven't I opened in a long time?", bundle: #bundle),
            symbolName: "calendar.badge.clock", availability: .available)
    }

    /// Looks up a last-opened date for every file of at least ``minimumSize``, and for no other (OLD-002).
    public var lastOpenedReader: LastOpenedReader? {
        LastOpenedReader(minimumSize: minimumSize, lastUsedDate: lastUsedDate)
    }

    /// The period in words, such as "12 months".
    public var period: String {
        DateComponentsFormatter.localizedString(from: DateComponents(month: periodMonths), unitsStyle: .full)
            ?? "\(periodMonths)"
    }

    public func includes(_ file: PersonalFile) -> Bool {
        includes(file, now: .now)
    }

    /// Whether `file` is at least ``minimumSize`` and was last opened no later than ``cutoff(now:)``. A file with no
    /// date at all is not listed: nothing shows that it is old.
    public func includes(_ file: PersonalFile, now: Date) -> Bool {
        guard file.snapshot.allocatedSize >= minimumSize, let date = file.lastOpened?.date ?? file.modified else {
            return false
        }
        return date <= cutoff(now: now)
    }

    /// ``periodMonths`` months before `now`. If the calendar cannot work it out, no date is old enough, so nothing is
    /// listed.
    public func cutoff(now: Date) -> Date {
        Calendar.current.date(byAdding: .month, value: -periodMonths, to: now) ?? .distantPast
    }

    public func reason(for file: PersonalFile) -> LocalizedStringResource {
        if file.lastOpened?.source == .lastUsed {
            return LocalizedStringResource("Not opened in \(period)", bundle: #bundle)
        }
        // Spotlight has no record of the file being opened, so the date is when it last changed (OLD-002).
        return LocalizedStringResource("Not modified in \(period)", bundle: #bundle)
    }
}
