import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// The run scaffolding Move to Trash, Restore and the summary confirmation share: one start, Stop, and a report or a
/// failure (SAF-011, SAF-014, TD-06).
///
/// The work is a stub, so these tests never touch the file system.
@MainActor
struct RunModelTests {
    @Test func aRunStartsOnceAndEndsWithItsReportSAF011() async {
        let calls = Mutex(0)
        let run = RunModel<Int>()
        #expect(run.phase == .waiting)

        let task = run.start { () async throws(HistoryError) -> Int in
            calls.withLock { $0 += 1 }
            return 7
        }
        #expect(run.phase == .running)
        #expect(run.start { () async throws(HistoryError) -> Int in 8 } == nil)
        await task?.value

        #expect(run.phase == .finished(7))
        #expect(run.start { () async throws(HistoryError) -> Int in 9 } == nil)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func aLogThatCannotBeOpenedFailsTheRunWithoutAReportSAF005() async {
        let failure = HistoryError.cannotOpen("/StubHome/log", errno: 13)
        let run = RunModel<Int>()
        let finished = Mutex<[Int?]>([])

        await run.start(
            onFinish: { report in finished.withLock { $0.append(report) } },
            work: { () async throws(HistoryError) -> Int in throw failure })?.value

        #expect(run.phase == .failed(failure))
        #expect(finished.withLock { $0 } == [nil])
    }

    @Test func finishingTellsTheCallerTheReportAfterThePhaseChanges() async {
        let run = RunModel<Int>()
        let seen = Mutex<[RunPhase<Int>]>([])

        await run.start(
            onFinish: { _ in
                let phase = run.phase
                seen.withLock { $0.append(phase) }
            },
            work: { () async throws(HistoryError) -> Int in 3 })?.value

        #expect(seen.withLock { $0 } == [.finished(3)])
    }

    @Test func stopCancelsTheRunSAF014() async {
        let run = RunModel<Int>()
        let task = run.start { () async throws(HistoryError) -> Int in
            while !Task.isCancelled { await Task.yield() }
            return -1
        }

        run.stop()
        await task?.value

        #expect(run.phase == .finished(-1))
    }
}
