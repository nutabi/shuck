import ShuckKit
import Synchronization
import Testing

@testable import Shuck

/// The run scaffolding Move to Trash, Restore and the summary confirmation share: one start, Stop, a report or a
/// failure, and quitting during a run (SAF-005, SAF-011, SAF-014, TD-06).
///
/// The work is a stub, so these tests never touch the file system.
@MainActor
struct RunModelTests {
    /// What quitting does for each answer: nothing runs, or a run the user does or does not stop.
    @Test(
        arguments: [
            (false, nil, QuitDecision.quitNow), (true, false, .keepRunning), (true, true, .stopThenQuit),
        ] as [(Bool, Bool?, QuitDecision)])
    func quittingAsksOnlyDuringARunSAF005(isRunning: Bool, answer: Bool?, expected: QuitDecision) {
        #expect(QuitDecision.decide(isRunning: isRunning, stopAnswered: answer) == expected)
    }

    @Test func aRunStartsOnceCountsUntilItsReportIsWrittenSAF005SAF011() async {
        let calls = Mutex(0)
        let runs = ActiveRuns()
        let run = RunModel<Int>(runs: runs)
        let seen = Mutex<[RunPhase<Int>]>([])
        #expect(run.phase == .waiting)
        #expect(!runs.isRunning)

        let task = run.start(
            onFinish: { _ in
                let phase = run.phase
                seen.withLock { $0.append(phase) }
            },
            work: { () async throws(HistoryError) -> Int in
                calls.withLock { $0 += 1 }
                return 7
            })
        #expect(run.phase == .running)
        #expect(runs.isRunning)
        #expect(run.start { () async throws(HistoryError) -> Int in 8 } == nil)
        await task?.value

        #expect(run.phase == .finished(7))
        #expect(!runs.isRunning)
        // The caller hears of the report after the phase has changed.
        #expect(seen.withLock { $0 } == [.finished(7)])
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

    /// Quitting stops every run and waits for the item in hand; a model's own Stop cancels the same way.
    @Test func stopAndQuitCancelARunAndWaitForItSAF014() async {
        let runs = ActiveRuns()
        let quitting = RunModel<Int>(runs: runs)
        quitting.start { () async throws(HistoryError) -> Int in
            await waitUntilCancelled() ? 7 : 0
        }
        #expect(runs.isRunning)
        await runs.stopAndWait()
        #expect(!runs.isRunning)
        #expect(quitting.phase == .finished(7))

        let stopped = RunModel<Int>()
        let task = stopped.start { () async throws(HistoryError) -> Int in
            await waitUntilCancelled() ? -1 : 0
        }
        stopped.stop()
        await task?.value
        #expect(stopped.phase == .finished(-1))
    }
}
