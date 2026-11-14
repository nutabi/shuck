import Foundation
import ShuckKit
import Testing

/// `pkgutil --file-info-plist` output turns into receipts, and anything else is a typed error (APP-008, D-200). The
/// recorded output is from a real run on a package-installed folder, with made-up identifiers.
struct PackageReceiptTests {
    static func fileInfo(_ entries: String) -> Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict><key>path</key><string>/Applications/Notes.app</string>
            <key>path-info</key><array>\(entries)</array></dict></plist>
            """.utf8)
    }

    static func entry(id: String?, version: String? = "2.1", time: Int? = 1_700_000_000) -> String {
        var text = "<dict><key>gid</key><integer>0</integer><key>mode</key><integer>16877</integer>"
        if let id { text += "<key>pkgid</key><string>\(id)</string>" }
        if let version { text += "<key>pkg-version</key><string>\(version)</string>" }
        if let time { text += "<key>install-time</key><integer>\(time)</integer>" }
        return text + "</dict>"
    }

    @Test func aPackageGivesItsIDVersionAndInstallDateAPP008() throws {
        let receipts = try PackageReceipt.parse(fileInfo: Self.fileInfo(Self.entry(id: "com.example.notes.pkg")))
        #expect(
            receipts == [
                PackageReceipt(
                    packageID: "com.example.notes.pkg", version: "2.1",
                    installed: Date(timeIntervalSince1970: 1_700_000_000))
            ])
    }

    @Test func noReceiptIsAnEmptyListNotAnErrorAPP008() throws {
        #expect(try PackageReceipt.parse(fileInfo: Self.fileInfo("")).isEmpty)
    }

    @Test func aPackageNamedTwiceIsListedOnceAndAnEntryWithoutAnIDIsLeftOutAPP008() throws {
        let entries =
            Self.entry(id: "com.example.a") + Self.entry(id: nil) + Self.entry(id: "com.example.a")
            + Self.entry(id: "com.example.b", version: nil, time: nil)
        let receipts = try PackageReceipt.parse(fileInfo: Self.fileInfo(entries))
        #expect(receipts.map(\.packageID) == ["com.example.a", "com.example.b"])
        #expect(receipts[1].version == nil && receipts[1].installed == nil)
    }

    @Test(arguments: [
        "", "not a plist", "<plist version=\"1.0\"><dict><key>path</key><string>/x</string></dict></plist>",
    ])
    func outputThatIsNotTheExpectedPropertyListIsUnreadableAPP008(_ text: String) {
        #expect(throws: PackageReceiptError.unreadableOutput) { try PackageReceipt.parse(fileInfo: Data(text.utf8)) }
    }
}
