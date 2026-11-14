import Foundation
import ShuckExecution
import ShuckKit
import ShuckKitTestSupport
import Testing

/// The receipt reader runs a fake `pkgutil` inside the fixture root, never the real one (APP-008, SAF-016, D-82).
struct PkgutilReceiptReaderTests {
    let root: FixtureRoot
    let app = URL(filePath: "/Applications/Notes.app")

    init() throws { root = try FixtureRoot() }

    private func reader() -> PkgutilReceiptReader { PkgutilReceiptReader(executableRoots: [root.url]) }

    private func receipts(
        _ behavior: FakeTool
    ) async throws(PackageReceiptError) -> [PackageReceipt] {
        _ = try? root.tool("usr/sbin/pkgutil", behavior)
        return try await reader().receipts(forAppAt: app)
    }

    @Test func recordedOutputGivesTheAppsReceiptAPP008() async throws {
        let output = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>path</key><string>/Applications/Notes.app</string>
            <key>path-info</key><array><dict><key>pkgid</key><string>com.example.pkg</string>
            <key>pkg-version</key><string>2.1</string><key>install-time</key><integer>1700000000</integer></dict>
            </array></dict></plist>
            """
        let found = try await receipts(.exits(0, output: output))
        #expect(found.map(\.packageID) == ["com.example.pkg"])
    }

    @Test func aToolThatIsNotThereIsUnavailableNotAnEmptyReceiptAPP008() async {
        await #expect(throws: PackageReceiptError.toolUnavailable) {
            try await reader().receipts(forAppAt: app)
        }
    }

    @Test func aFailingToolIsAFailureNotAnEmptyReceiptAPP008() async {
        await #expect(throws: PackageReceiptError.failed(3)) { try await receipts(.exits(3, output: "boom")) }
    }

    @Test func outputThatIsNotAPropertyListIsUnreadableAPP008() async {
        await #expect(throws: PackageReceiptError.unreadableOutput) { try await receipts(.exits(0, output: "hello")) }
    }

    @Test func outputLongerThanTheLimitIsUnreadableNotParsedFromItsTailAPP008() async {
        await #expect(throws: PackageReceiptError.unreadableOutput) {
            try await receipts(.printsALot(bytes: 100_000, last: "</plist>"))
        }
    }
}
