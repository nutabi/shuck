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

# expect_rule RULE: the checks fail on the current tree and report RULE.
expect_rule() {
    local output
    if output="$("$checks" "$tree" 2>&1)"; then
        echo "FAIL: [$1] expected a failure, got none" >&2
        failed=1
    elif ! grep -q "\[$1\]" <<<"$output"; then
        echo "FAIL: [$1] not reported. Output was:" >&2
        echo "$output" >&2
        failed=1
    else
        echo "ok: [$1] reported"
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
new_tree trash && put "$engine" 'try FileManager.default.trashItem(at: url, resultingItemURL: nil)' && expect_rule mutation
new_tree remove-app && put "$app" 'try FileManager.default.removeItem(at: url)' && expect_rule mutation
new_tree launchctl && put "$engine" 'let arguments = ["bootout", target]' && expect_rule mutation
new_tree write && put "$engine" 'try data.write(to: url)' && expect_rule file-write
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
let arguments = ["bootout", target]'
put Packages/ShuckKit/Sources/ShuckKit/History/HistoryWriter.swift 'try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
fchmod(descriptor, 0o600)'
put Packages/ShuckKit/Sources/ShuckKitTestSupport/FakeTool.swift 'let script = "#!/bin/sh\nexit 0"
try script.write(to: url, atomically: true, encoding: .utf8)'
put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift 'print("debug output in a test")'
put "$app" '// URLSession is banned, and this comment mentions it without using it.
NSWorkspace.shared.open(settingsURL)
let n = items.remove(at: 0)'
put Shuck.xcodeproj/project.xcproj '"packages": [ { "kind": "local", "path": "Packages/ShuckKit" } ]'
expect_clean "allowed code"

if ((failed)); then
    echo "static-checks-test: FAILED" >&2
    exit 1
fi
echo "static-checks-test: OK"
