import Synchronization

@testable import Shuck

/// Free-space readings a test makes up, given out in order, one per read; `nil` once they run out. Counts the reads.
final class FreeSpaceReadings: Sendable {
    private let state: Mutex<(readings: [Int64?], count: Int)>

    init(_ readings: [Int64?]) {
        state = Mutex((readings, 0))
    }

    /// How many times ``read`` was called.
    var count: Int { state.withLock { $0.count } }

    var read: ReadFreeSpace {
        { self.next() }
    }

    private func next() -> Int64? {
        state.withLock { state in
            defer { state.count += 1 }
            return state.count < state.readings.count ? state.readings[state.count] : nil
        }
    }
}
