import Testing

@testable import Shuck

/// Quitting during a run asks first, then stops the run and waits for it (SAF-005, SAF-014).
@MainActor
struct QuitDuringRunTests {
    @Test func quitsAtOnceWhenNothingRunsSAF005() {
        #expect(QuitDecision.decide(isRunning: false, stopAnswered: nil) == .quitNow)
    }

    @Test func keepsRunningUnlessTheUserStopsSAF005() {
        #expect(QuitDecision.decide(isRunning: true, stopAnswered: false) == .keepRunning)
        #expect(QuitDecision.decide(isRunning: true, stopAnswered: true) == .stopThenQuit)
    }

    @Test func aRunCountsUntilItsReportIsWrittenSAF005() async {
        let runs = ActiveRuns()
        let model = RunModel<Int>(runs: runs)
        #expect(!runs.isRunning)
        let task = model.start { 1 }
        #expect(runs.isRunning)
        await task?.value
        #expect(!runs.isRunning)
    }

    @Test func stopAndWaitCancelsAndWaitsForTheItemInHandSAF014() async {
        let runs = ActiveRuns()
        let model = RunModel<Int>(runs: runs)
        model.start {
            while !Task.isCancelled { await Task.yield() }
            return 7
        }
        #expect(runs.isRunning)
        await runs.stopAndWait()
        #expect(!runs.isRunning)
        #expect(model.phase == .finished(7))
    }
}
