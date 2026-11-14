import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The skip codes the history log records, and re-validation's three results (D-88).
struct SkipCodeTests {
    /// SAF-011: every code reads back from the text the log records, with or without a detail.
    @Test func everyCodeReadsBackFromItsLoggedTextSAF011() {
        for code in SkipCode.allCases {
            #expect(SkipCode(detail: code.logged()) == code)
            #expect(SkipCode(detail: code.logged("file, 4096 bytes")) == code)
        }
        #expect(
            SkipCode.changed.logged(ItemSnapshot(kind: .folder, allocatedSize: 8192).logged)
                == "changed: folder, 8192 bytes")
        #expect(
            SkipCode.rejected.logged(PathGuardError.outsideAllowedRoots("/x/y").logged)
                == "rejected: outsideAllowedRoots")
    }

    /// SAF-011: the codes keep the case names Shuck 0.1.0 logged, so its records read the same.
    @Test func detailsShuck010WroteStillReadSAF011() {
        let logged: [String: SkipCode] = [
            "missing": .missing,
            "changed(ShuckKit.ItemSnapshot(kind: ShuckKit.ItemSnapshot.Kind.file, allocatedSize: 4))": .changed,
            #"rejected(ShuckKit.PathGuardError.outsideAllowedRoots("/x/y"))"#: .rejected,
            "cancelled": .cancelled,
            "historyUnavailable": .historyUnavailable,
            "unsupportedMethod(ShuckKit.ActionMethod.tool)": .unsupportedMethod,
            "originalTaken": .originalTaken,
            "notInTrash": .notInTrash,
            "otherItem": .otherItem,
        ]
        for (detail, code) in logged {
            #expect(SkipCode(detail: detail) == code)
        }
        #expect(SkipCode(detail: "somethingNew") == nil)
        #expect(SkipCode(detail: "") == nil)
    }

    /// SAF-014: measuring a folder stops as soon as it is asked to, and says so rather than calling the item missing.
    @Test func reValidationStopsMeasuringAFolderWhenAskedSAF014() throws {
        let root = try FixtureRoot()
        let backup = try root.folder("Library/Application Support/MobileSync/Backup/0000")
        for index in 1...10 { try root.file("Library/Application Support/MobileSync/Backup/0000/\(index)", size: 10) }
        let file = try root.file("Downloads/clip.mov", size: 4_096)

        var asked = 0
        #expect(
            ItemSnapshot.check(backup) {
                asked += 1
                return asked < 2
            } == .stopped)
        // It stopped after the first entry, rather than reading all ten.
        #expect(asked < 10)
        #expect(ItemSnapshot.check(file) { false } == ItemSnapshot.read(file).map(ItemSnapshot.Check.found))
        #expect(ItemSnapshot.check(root.url.appending(path: "Downloads/gone.mov")) { false } == .missing)
    }
}
