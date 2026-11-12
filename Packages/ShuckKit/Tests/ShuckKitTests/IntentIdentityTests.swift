import Foundation
import Testing

@testable import ShuckKit

/// The identity an intent record can carry is one added optional key (HIS-001, SAF-005).
struct IntentIdentityTests {
    @Test func anIntentWithoutAnIdentityStillReadsAndTheIdentityIsOneAddedKeyHIS001() throws {
        let run = UUID()
        let old =
            #"{"bytes":5,"op":"trash","path":"/Users/someone/a","phase":"intent","run":"\#(run)","#
            + #""tier":"yourData","tool":"largeFiles","ts":"2026-11-12T00:00:00.000Z","v":1}"#
        let record = try #require(HistoryRecord.decode(line: Data(old.utf8)))
        #expect(record.identity == nil)
        let identity = FileIdentity(volume: 1, file: 2)
        let new = HistoryRecord.intent(
            run: run, tool: .largeFiles, operation: .trash, path: "/Users/someone/a", tier: .yourData,
            identity: identity, bytes: 5)
        let line = try new.jsonLine()
        #expect(HistoryRecord.decode(line: line)?.identity == identity)
        // Only one optional key is added, which a reader of the old shape ignores.
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let oldKeys: Set = ["v", "ts", "run", "tool", "phase", "op", "path", "bytes", "tier"]
        #expect(Set(object.keys).subtracting(oldKeys) == ["identity"])
    }
}
