#!/bin/bash
# Self-test for scripts/static-checks.sh: every rule must fire on a violation and stay quiet on allowed code.
# CI runs it next to the checks themselves, so a broken pattern cannot silently pass everything.

set -euo pipefail
checks="$(cd "$(dirname "$0")" && pwd)/static-checks.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

# put PATH CONTENT: write a file into the current fixture tree.
put() {
    mkdir -p "$(dirname "$tree/$1")"
    printf '%s\n' "$2" >"$tree/$1"
}

new_tree() {
    tree="$work/$1"
    mkdir -p "$tree"
}

# expect_rule RULE [REQUIREMENT]: the checks fail on the current tree and report RULE. REQUIREMENT names the
# requirement the case tests, such as SAF-017 (NFR-QA-001).
expect_rule() {
    local output label="[$1]${2:+ ($2)}"
    if output="$("$checks" "$tree" 2>&1)"; then
        echo "FAIL: $label expected a failure in $(basename "$tree"), got none" >&2
        failed=1
    elif ! grep -q "\[$1\]" <<<"$output"; then
        echo "FAIL: $label not reported in $(basename "$tree"). Output was:" >&2
        echo "$output" >&2
        failed=1
    else
        echo "ok: $label reported in $(basename "$tree")"
    fi
}

# expect_clean NAME: the checks pass on the current tree.
expect_clean() {
    local output
    if ! output="$("$checks" "$tree" 2>&1)"; then
        echo "FAIL: $1 expected to pass. Output was:" >&2
        echo "$output" >&2
        failed=1
    else
        echo "ok: $1 passes"
    fi
}

app=Shuck/App.swift
engine=Packages/ShuckKit/Sources/ShuckKit/Engine.swift
execution=Packages/ShuckKit/Sources/ShuckExecution/Executor.swift

new_tree network && put "$app" 'let session = URLSession.shared' && expect_rule network
new_tree network-import && put "$engine" 'import Network' && expect_rule network
new_tree shell && put "$engine" 'let shell = URL(filePath: "/bin/sh")' && expect_rule shell
new_tree popen && put "$execution" 'let pipe = popen("ls", "r")' && expect_rule shell
new_tree privilege && put "$app" 'var ref: AuthorizationRef?' && expect_rule privilege
new_tree trash && put "$engine" 'try FileManager.default.trashItem(at: url, resultingItemURL: nil)' &&
    expect_rule mutation SAF-017
new_tree remove-app && put "$app" 'try FileManager.default.removeItem(at: url)' && expect_rule mutation SAF-017
new_tree launchctl && put "$engine" 'let arguments = ["bootout", target]' && expect_rule mutation SAF-017
# The C calls' *at, _np and f* variants (TD-02).
for call in 'renamex_np(from, to, flags)' 'renameat(fd, from, fd, to)' 'renameatx_np(fd, from, fd, to, flags)' \
    'unlinkat(fd, path, 0)' 'exchangedata(a, b, 0)' 'removefileat(fd, path, nil, 0)' 'ftruncate(fd, 0)' \
    'copyfile(from, to, nil, flags)' 'fcopyfile(a, b, nil, flags)' 'clonefile(from, to, 0)' \
    'clonefileat(fd, from, fd, to, 0)' 'fclonefileat(fd, dirfd, to, 0)'; do
    new_tree "mutation-${call%%(*}" && put "$engine" "let result = $call" && expect_rule mutation SAF-017
done
new_tree write && put "$engine" 'try data.write(to: url)' && expect_rule file-write SAF-017
for call in 'try "text".write(toFile: path, atomically: true, encoding: .utf8)' 'let fd = openat(dir, path, O_CREAT)' \
    'mkdirat(dir, path, 0o700)' 'let stream = OutputStream(url: url, append: true)'; do
    new_tree "file-write-$(tr -cd '[:alnum:]' <<<"${call:0:16}")" && put "$app" "$call" && expect_rule file-write SAF-017
done
new_tree process && put "$app" 'let process = Process()' && expect_rule process D-82
new_tree process-run && put "$engine" 'try Process.run(url, arguments: [path])' && expect_rule process D-82
new_tree posix-spawn && put "$engine" 'posix_spawn(&pid, path, nil, nil, argv, envp)' && expect_rule process D-82
new_tree process-test && put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift 'let process = Process()' &&
    expect_rule process D-82
new_tree home-url && put ShuckTests/SomeTests.swift 'let file = URL.homeDirectory.appending(path: "Downloads/a.dmg")' &&
    expect_rule real-home SAF-016
new_tree home-manager && put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift \
    'let home = FileManager.default.homeDirectoryForCurrentUser' && expect_rule real-home SAF-016
new_tree home-function && put ShuckUITests/SomeTests.swift 'let home = NSHomeDirectory()' && expect_rule real-home SAF-016
new_tree home-tilde && put Packages/ShuckKit/Sources/ShuckKitTestSupport/Helper.swift \
    'let path = ("~/Downloads" as NSString).expandingTildeInPath' && expect_rule real-home SAF-016
new_tree home-environment && put ShuckTests/SomeTests.swift 'let home = ProcessInfo.processInfo.environment["HOME"]' &&
    expect_rule real-home SAF-016
new_tree permissions && put "$engine" 'try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)' &&
    expect_rule permissions
new_tree fchmod && put "$app" 'fchmod(descriptor, 0o600)' && expect_rule permissions
new_tree print && put "$app" 'print("hello")' && expect_rule print
new_tree force-cast && put "$engine" 'let n = value as! Int' && expect_rule force-cast
new_tree package && put Packages/ShuckKit/Package.swift \
    'dependencies: [.package(url: "https://example.com/x.git", from: "1.0.0")]' && expect_rule packages
new_tree remote-project && put Shuck.xcodeproj/project.xcproj '"packages": [ { "kind": "remote", "url": "x" } ]' &&
    expect_rule packages
new_tree resolved && put Shuck.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved '{}' &&
    expect_rule packages
new_tree claude && put docs/CLAUDE.md '# no' && expect_rule agents

new_tree allowed
put "$execution" 'try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
let arguments = ["bootout", target]
guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { return }
let process = Process()'
put Packages/ShuckKit/Sources/ShuckKit/History/HistoryWriter.swift 'try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
fchmod(descriptor, 0o600)'
put Packages/ShuckKit/Sources/ShuckKitTestSupport/FakeTool.swift 'let script = "#!/bin/sh\nexit 0"
try script.write(to: url, atomically: true, encoding: .utf8)'
put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift 'print("debug output in a test")
#expect(ResultRow.folder(of: file, home: home) == "~/Downloads")
let info = ProcessInfo.processInfo'
put "$app" '// URLSession is banned, and this comment mentions it without using it.
NSWorkspace.shared.open(settingsURL)
let n = items.remove(at: 0)
let home = URL.homeDirectory'
put Shuck.xcodeproj/project.xcproj '"packages": [ { "kind": "local", "path": "Packages/ShuckKit" } ]'
expect_clean "allowed code"

if ((failed)); then
    echo "static-checks-test: FAILED" >&2
    exit 1
fi
echo "static-checks-test: OK"
