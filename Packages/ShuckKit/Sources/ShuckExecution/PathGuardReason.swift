import ShuckKit

extension PathGuard {
    /// Why the guard refused a path, as a skip reason: a refusal because of a folder the user excluded in Settings says
    /// so, and any other refusal is a rejection (SET-001, SAF-011, D-149). The guard itself is unchanged; it refuses an
    /// exclusion as it refuses any protected location, and this only looks at which location it named.
    func reason(for error: PathGuardError) -> ItemOutcome.SkipReason {
        if let path = excludedPath(in: error) { return .userExclusion(path) }
        return .rejected(error)
    }

    /// Restore's counterpart of ``reason(for:)``.
    func restoreReason(for error: PathGuardError) -> RestoreOutcome.SkipReason {
        if let path = excludedPath(in: error) { return .userExclusion(path) }
        return .rejected(error)
    }

    private func excludedPath(in error: PathGuardError) -> String? {
        guard case .protectedLocation(_, let protected) = error else { return nil }
        return configuration.userExclusions.contains { $0.path == protected } ? protected : nil
    }
}
