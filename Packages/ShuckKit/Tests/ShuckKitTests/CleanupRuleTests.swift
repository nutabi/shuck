import Foundation
import ShuckKit
import ShuckKitTestSupport
import Testing

struct CleanupRuleTests {
    let root: FixtureRoot
    let cache: URL
    let path: RulePath

    init() throws {
        root = try FixtureRoot()
        cache = try root.folder("Library/Caches/Fixture")
        path = try RulePath(root: cache, pattern: "*")
    }

    func rule(
        id: String = "fixture", detection: CleanupRule.Detection? = nil, action: CleanupRule.Action? = nil,
        tier: Tier = .rebuildable, selection: RuleSelection = .modifiedAtLeast(days: 30), documentation: URL? = nil
    ) throws -> CleanupRule {
        try CleanupRule(
            id: id, name: "Fixture", description: "Fixture cache",
            category: ItemCategory(id: "fixture", name: "Fixture"),
            detection: detection ?? .folder(cache), action: action ?? .paths([path], method: .delete), tier: tier,
            selection: selection, explanation: "Can be rebuilt",
            documentation: try documentation ?? #require(URL(string: "https://example.test/cache")))
    }

    @Test func definitionsLoadAndValidateDEV001SAF004() throws {
        let rule = try rule()
        #expect(rule.id == "fixture" && rule.action.method == .delete)
        #expect(throws: RuleError.emptyID) { try self.rule(id: "") }
        #expect(throws: RuleError.invalidPath) { try self.rule(action: .paths([], method: .delete)) }
        #expect(throws: RuleError.methodNotAllowed) { try self.rule(tier: .yourData, selection: .never) }
        #expect(throws: RuleError.pathMethodNotAllowed) { try self.rule(action: .paths([path], method: .tool)) }
        #expect(throws: RuleError.contentsNotAllowed) {
            try self.rule(action: .paths([path], method: .trash, scope: .contents), tier: .yourData, selection: .never)
        }
        #expect(throws: RuleError.invalidStaleness) { try self.rule(selection: .modifiedAtLeast(days: 0)) }
        #expect(throws: RuleError.yourDataSelected) {
            try self.rule(action: .paths([path], method: .trash), tier: .yourData, selection: .always)
        }
        #expect(throws: RuleError.invalidDocumentation) { try self.rule(documentation: cache) }
        #expect(throws: RuleError.invalidApp) {
            try CleanupRule(
                id: "fixture", name: "Fixture", description: "Fixture", category: ItemCategory(id: "f", name: "F"),
                detection: .folder(cache), action: .paths([path], method: .delete), tier: .rebuildable,
                selection: .always, explanation: "Fixture",
                documentation: #require(URL(string: "https://example.test")),
                apps: ["com.example.Fixture", ""])
        }
        #expect(throws: RuleError.invalidDetection) { try self.rule(detection: .executable("relative")) }
        #expect(throws: RuleError.invalidDetection) { try self.rule(detection: .executable("/tools/../tool")) }
    }

    @Test func onlyExistingDataAndExecutableToolsAreAvailableDEV002() throws {
        #expect(try rule().detection.isAvailable)
        let missing = try root.url("missing")
        #expect(!CleanupRule.Detection.folder(missing).isAvailable)
        let file = try root.file("tools/cleaner", permissions: 0o700)
        let ordinary = try root.file("tools/data")
        #expect(CleanupRule.Detection.executable(file.path).isAvailable)
        #expect(!CleanupRule.Detection.executable(ordinary.path).isAvailable)
        #expect(!CleanupRule.Detection.executable(cache.path).isAvailable)
        #expect(!CleanupRule.Detection.folder(file).isAvailable)
        #expect(!CleanupRule.Detection.executable(missing.path).isAvailable)
        let alias = try root.symlink("tools/alias", to: file)
        let folderAlias = try root.symlink("tools/folder", to: cache)
        let broken = try root.symlink("tools/broken", to: missing)
        #expect(CleanupRule.Detection.executable(alias.path).isAvailable)
        #expect(CleanupRule.Detection.folder(folderAlias).isAvailable)
        #expect(!CleanupRule.Detection.executable(folderAlias.path).isAvailable)
        #expect(!CleanupRule.Detection.executable(broken.path).isAvailable)
    }

    @Test func staleBoundaryUsesTheConfiguredNumberOfDaysDEV005() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let selection = try rule().selection
        #expect(selection.selects(modified: now.addingTimeInterval(-30 * 86_400), now: now))
        #expect(!selection.selects(modified: now.addingTimeInterval(-30 * 86_400 + 1), now: now))
        #expect(!selection.selects(modified: now.addingTimeInterval(1), now: now))
        #expect(!selection.selects(modified: nil, now: now))
        #expect(RuleSelection.modifiedAtLeast(days: 7).selects(modified: now.addingTimeInterval(-7 * 86_400), now: now))
        #expect(!RuleSelection.never.selects(modified: now, now: now))
        #expect(RuleSelection.always.selects(modified: nil, now: now))
    }

    @Test func pathPatternsMatchOnlyTheirDepthAndRootDEV001SAF007() throws {
        let item = try root.folder("Library/Caches/Fixture/Project")
        let nested = try root.file("Library/Caches/Fixture/Project/inside")
        let sibling = try root.file("Library/Caches/Fixture-other/item")
        #expect(path.matches(item))
        #expect(!path.matches(nested) && !path.matches(cache) && !path.matches(sibling))
        let named = try RulePath(root: cache, pattern: "project/*")
        #expect(named.matches(nested))
        let outside = try root.file("Downloads/keep")
        let link = try root.symlink("Library/Caches/Fixture/link", to: outside)
        #expect(!path.matches(link))
        for invalid in ["", "/absolute", "../escape", "a/../b", "a//b", ".", "a/\0"] {
            #expect(throws: RuleError.invalidPath) { try RulePath(root: cache, pattern: invalid) }
        }
    }

    @Test func commandsAreStructuredAndToolRulesNeverUseDeleteDEV004SAF010() throws {
        let executable = try root.file("tools/cleaner", permissions: 0o700).path
        let command = try ToolCommand(
            executable: executable, arguments: ["cache", "a b", "it's"], environment: ["PATH": "/usr/bin:/bin"])
        let rule = try rule(detection: .executable(executable), action: .command(command), selection: .always)
        #expect(rule.action.method == .tool && command.timeout == 600)
        #expect(command.display.hasSuffix("'cache' 'a b' 'it'\\''s'"))
        #expect(throws: RuleError.invalidDetection) { try self.rule(action: .command(command)) }
        for invalid in ["relative", "/tools/../cleaner", "/tools/clean\0er"] {
            #expect(throws: ToolCommandError.invalidExecutable) {
                try ToolCommand(executable: invalid, arguments: [], environment: ["PATH": "/bin"])
            }
        }
        for environment in [[:], ["PATH": ""], ["PATH": "/bin", "BAD=KEY": "value"], ["PATH": "/bin", "KEY": "\0"]] {
            #expect(throws: ToolCommandError.invalidArgumentsOrEnvironment) {
                try ToolCommand(executable: executable, arguments: [], environment: environment)
            }
        }
        #expect(throws: ToolCommandError.invalidArgumentsOrEnvironment) {
            try ToolCommand(executable: executable, arguments: ["\0"], environment: ["PATH": "/bin"])
        }
        for timeout in [0.0, -1, .infinity, .nan] {
            #expect(throws: ToolCommandError.invalidTimeout) {
                try ToolCommand(executable: executable, arguments: [], environment: ["PATH": "/bin"], timeout: timeout)
            }
        }
    }
}
