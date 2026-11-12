#!/bin/bash
# Self-test for scripts/static-checks.sh: every rule must fire on a violation and stay quiet on allowed code.
# CI runs it next to the checks themselves, so a broken pattern cannot silently pass everything. Each fixture tree is a
# git repository, since the checks read only the files git tracks; `stage` adds a tree's files before a run.

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

# The Must SAF IDs, built from their numbers so that this script does not name them: it is a script, and the checks
# count a script's IDs as named. ids_except [ID...] prints every ID but those given.
ids_except() {
    local n id out=""
    for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 16 17 18; do
        id="$(printf 'SAF-%03d' "$n")"
        case " $* " in *" $id "*) continue ;; esac
        out="$out$id "
    done
    echo "$out"
}

# new_tree NAME: an empty git repository whose test folder names every Must SAF ID (R-12), so only a case that changes
# that fails the saf-tests check. autostage is on: expect_rule and expect_clean add the tree's files first.
new_tree() {
    tree="$work/$1"
    mkdir -p "$tree"
    git -C "$tree" init -q
    autostage=1
    put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except)"
}

# stage: add every file of the current tree to git's index, as a developer's `git add` does.
stage() {
    git -C "$tree" -c core.excludesFile=/dev/null add -A
}

# expect_rule RULE [REQUIREMENT]: the checks fail on the current tree and report RULE. REQUIREMENT names the
# requirement the case tests, such as SAF-017 (NFR-QA-001).
expect_rule() {
    local output label="[$1]${2:+ ($2)}"
    if ((autostage)); then stage; fi
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

# expect_output TEXT: the checks fail on the current tree and their output holds TEXT.
expect_output() {
    local output
    if ((autostage)); then stage; fi
    if output="$("$checks" "$tree" 2>&1)"; then
        echo "FAIL: expected a failure in $(basename "$tree"), got none" >&2
        failed=1
    elif ! grep -qF -- "$1" <<<"$output"; then
        echo "FAIL: '$1' not reported in $(basename "$tree"). Output was:" >&2
        echo "$output" >&2
        failed=1
    else
        echo "ok: '$1' reported in $(basename "$tree")"
    fi
}

# expect_clean NAME: the checks pass on the current tree.
expect_clean() {
    local output
    if ((autostage)); then stage; fi
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
    'clonefileat(fd, from, fd, to, 0)' 'fclonefileat(fd, dirfd, to, 0)' 'chflags(path, UInt32(UF_HIDDEN))' \
    'lchflags(path, 0)' 'fchflags(fd, 0)' 'setxattr(path, name, value, size, 0, 0)' 'fsetxattr(fd, name, v, n, 0, 0)' \
    'removexattr(path, name, 0)' 'fremovexattr(fd, name, 0)' 'try url.setResourceValues(values)' \
    'try url.setResourceValue(true, forKey: .isHiddenKey)'; do
    new_tree "mutation-${call%%(*}" && put "$engine" "let result = $call" && expect_rule mutation SAF-017
done
# Dates, attribute lists, Finder icons and login items (#56).
for call in 'utimes(path, nil)' 'lutimes(path, nil)' 'futimes(fd, nil)' 'utimensat(fd, path, &times, 0)' \
    'futimens(fd, &times)' 'setattrlist(path, &list, &buffer, size, 0)' 'fsetattrlist(fd, &list, &buffer, size, 0)' \
    'setattrlistat(fd, path, &list, &buffer, size, 0)' 'NSWorkspace.shared.setIcon(image, forFile: path)' \
    'SMLoginItemSetEnabled(identifier as CFString, true)'; do
    new_tree "mutation-${call%%(*}" && put "$app" "let result = $call" && expect_rule mutation SAF-017
done
new_tree login-item && put "$app" 'try SMAppService.agent(plistName: "agent.plist").register()' &&
    expect_rule mutation SAF-017
new_tree login-item-type && put "$engine" 'let service: SMAppService = .mainApp' && expect_rule mutation SAF-017
new_tree write && put "$engine" 'try data.write(to: url)' && expect_rule file-write SAF-017
for call in 'try "text".write(toFile: path, atomically: true, encoding: .utf8)' 'let fd = openat(dir, path, O_CREAT)' \
    'mkdirat(dir, path, 0o700)' 'let stream = OutputStream(url: url, append: true)' \
    'let fd = Darwin.open(path, O_WRONLY | O_CREAT, 0o600)' 'Darwin.mkdir(path, 0o700)' 'symlink(target, path)' \
    'symlinkat(target, fd, path)' 'link(from, to)' 'linkat(fd, from, fd, to, 0)'; do
    new_tree "file-write-$(tr -cd '[:alnum:]' <<<"${call:0:16}")" && put "$app" "$call" && expect_rule file-write SAF-017
done
# FIFOs, device nodes, folders that FileManager creates on request, and NSWorkspace's copies (#56).
for call in 'mkfifo(path, 0o600)' 'mkfifoat(fd, path, 0o600)' 'mknod(path, S_IFIFO | 0o600, 0)' \
    'mknodat(fd, path, S_IFIFO | 0o600, 0)' 'NSWorkspace.shared.duplicate([url]) { _, _ in }'; do
    new_tree "file-write-${call%%(*}" && put "$engine" "let result = $call" && expect_rule file-write SAF-017
done
new_tree replacement-folder && put "$engine" 'let folder = try FileManager.default.url(
    for: .itemReplacementDirectory, in: .localDomainMask, appropriateFor: target, create: true)' &&
    expect_rule file-write SAF-017
new_tree process && put "$app" 'let process = Process()' && expect_rule process D-82
new_tree process-run && put "$engine" 'try Process.run(url, arguments: [path])' && expect_rule process D-82
new_tree process-type && put "$app" 'let process: Process = .init()' && expect_rule process D-82
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
new_tree home-domain && put ShuckTests/SomeTests.swift \
    'let folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)' &&
    expect_rule real-home SAF-016
new_tree home-all-domains && put ShuckTests/SomeTests.swift \
    'let folders = FileManager.default.urls(for: .downloadsDirectory, in: .allDomainsMask)' && expect_rule real-home SAF-016
# The user's folders as URL properties, by type name or as an implicit member (#56).
for folder in userDirectory documentsDirectory desktopDirectory downloadsDirectory libraryDirectory \
    applicationSupportDirectory cachesDirectory moviesDirectory musicDirectory picturesDirectory sharedPublicDirectory \
    trashDirectory; do
    new_tree "home-$folder" && put ShuckTests/SomeTests.swift "let folder = URL.$folder.appending(path: \"a\")" &&
        expect_rule real-home SAF-016
done
new_tree home-implicit-member && put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift \
    'let folder: URL = .downloadsDirectory' && expect_rule real-home SAF-016
new_tree home-trash && put Packages/ShuckKit/Tests/ShuckExecutionTests/SomeTests.swift \
    'let action = TrashAction(trash: SystemTrash())' && expect_rule real-home SAF-016
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

# More network APIs, and loaders given a remote URL (#123). A URL held in a variable is not caught, so there is no case.
for call in 'import CFNetwork' 'import NetworkExtension' 'let status = getaddrinfo(host, nil, nil, &info)' \
    'let result = connect(fd, address, length)' 'let result = Darwin.connect(fd, address, length)' \
    'AsyncImage(url: image)' 'let data = try Data(contentsOf: URL(string: "https://example.com/a")!)' \
    'let text = try String(contentsOf: URL(string: "http://example.com/a")!)' \
    'for try await line in URL(string: "https://example.com/a")!.lines { use(line) }'; do
    new_tree "network-$(tr -cd '[:alnum:]' <<<"${call:0:24}")" && put "$app" "$call" &&
        expect_rule network NFR-SEC-001
done
# More file writes: the System framework's open that creates, and temporary files and folders (#123).
for call in 'let fd = try FileDescriptor.open(path, .writeOnly, options: [.create], permissions: .ownerReadWrite)' \
    'let fd = mkstemp(&template)' 'let fd = mkstemps(&template, 4)' 'let fd = mkostemp(&template, 0)' \
    'let folder = mkdtemp(&template)' 'let fd = Darwin.mkstemp(&template)'; do
    new_tree "file-write-$(tr -cd '[:alnum:]' <<<"${call:0:30}")" && put "$engine" "$call" &&
        expect_rule file-write SAF-017
done
# More mutations: C's remove(path), and iCloud's evict and move (#123).
for call in 'let result = remove(path)' 'let result = remove("/tmp/x")' 'let result = Darwin.remove(url.path)' \
    'try FileManager.default.evictUbiquitousItem(at: url)' \
    'try FileManager.default.setUbiquitous(true, itemAt: url, destinationURL: destination)'; do
    new_tree "mutation-$(tr -cd '[:alnum:]' <<<"${call:0:30}")" && put "$engine" "$call" &&
        expect_rule mutation SAF-017
done
for call in 'let task = try NSUserUnixTask(url: script)' 'let connection = NSXPCConnection(serviceName: name)'; do
    new_tree "process-$(tr -cd '[:alnum:]' <<<"${call:0:30}")" && put "$app" "$call" && expect_rule process D-82
done
for call in '@_silgen_name("unlink") func unlinkByName(_ path: UnsafePointer<CChar>) -> Int32' \
    'let handle = dlopen(nil, RTLD_NOW)' 'let symbol = dlsym(handle, "unlink")'; do
    new_tree "native-call-$(tr -cd '[:alnum:]' <<<"${call:0:20}")" && put "$engine" "$call" &&
        expect_rule native-call SAF-017
done

# Calls wrapped across lines, as swift-format writes them, are joined and reported (#123).
new_tree wrapped-write && put "$engine" 'try data.write(
    to: url)' && expect_rule file-write SAF-017
new_tree wrapped-write-options && put "$engine" 'try data.write(
    to: url,
    options: .atomic
)' && expect_rule file-write SAF-017
new_tree wrapped-remove && put "$app" 'try FileManager.default.removeItem(
    at: url)' && expect_rule mutation SAF-017
new_tree wrapped-chain && put "$engine" 'try FileManager.default
    .removeItem(at: url)' && expect_rule mutation SAF-017
new_tree wrapped-handle && put "$engine" 'let handle = try FileHandle(
    forWritingTo: url)' && expect_rule file-write SAF-017
new_tree wrapped-loader && put "$app" 'let data = try Data(
    contentsOf: URL(string: "https://example.com/a")!)' && expect_rule network NFR-SEC-001
new_tree wrapped-comma && put "$engine" 'let (a, b) = (1,
    unlink(path))' && expect_rule mutation SAF-017
new_tree wrapped-create && put "$engine" 'let fd = try FileDescriptor.open(
    path, .writeOnly,
    options: [.create])' && expect_rule file-write SAF-017
# The report names the line the call starts on, and a comment between the lines does not stop the join.
new_tree wrapped-line-number && put "$engine" 'let first = 1
// a comment
try data.write(
    // a comment inside the call
    to: url)' &&
    expect_output "Engine.swift:3: [file-write]"

# Only the files git tracks are checked: a violating file that is not added leaves the checks passing (#122).
new_tree untracked && put "$app" 'let ok = true' && stage && put Shuck/Untracked.swift 'let session = URLSession.shared' &&
    autostage=0 expect_clean "an untracked violation"
new_tree untracked-claude && put "$app" 'let ok = true' && stage && put .claude/worktrees/x/Shuck/Leftover.swift 'print("x")' &&
    put .claude/worktrees/x/CLAUDE.md '# no' && autostage=0 expect_clean "an untracked CLAUDE.md"
new_tree tracked-then-deleted && put "$app" 'let session = URLSession.shared' && stage && rm "$tree/$app" &&
    autostage=0 expect_clean "a tracked file deleted from the working tree"

# Every Must SAF requirement is named in a test or a script, as a whole ID (NFR-QA-001, D-133).
new_tree saf-missing && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except SAF-018)" &&
    expect_rule saf-tests NFR-QA-001
new_tree saf-missing-first && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except SAF-001)" &&
    expect_output "SAF-001: [saf-tests]"
new_tree saf-longer-id && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt \
    "$(ids_except SAF-001) $(printf 'SAF-%04d' 1)" && expect_rule saf-tests NFR-QA-001
new_tree saf-in-checks-only && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except SAF-018)" &&
    put scripts/static-checks.sh "$(ids_except)" && expect_rule saf-tests NFR-QA-001
new_tree saf-in-source-only && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except SAF-018)" &&
    put "$engine" "// $(ids_except)" && expect_rule saf-tests NFR-QA-001
new_tree saf-spread && put Packages/ShuckKit/Tests/ShuckKitTests/RequirementIds.txt "$(ids_except SAF-017 SAF-018)" &&
    put scripts/other.sh "# $(ids_except | cut -d' ' -f1-16)" &&
    put ShuckUITests/FlowTests.swift "// $(ids_except SAF-001 SAF-002 SAF-003 SAF-004 SAF-005 SAF-006 SAF-007 SAF-008 SAF-009 SAF-010 SAF-011 SAF-012 SAF-013 SAF-014 SAF-016)" &&
    expect_clean "IDs spread over tests and scripts"

new_tree allowed
put "$execution" 'try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
let arguments = ["bootout", target]
guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { return }
let process = Process()
try data.write(
    to: url)
let removed = remove(path)
let fd = mkstemp(&template)
try SMAppService.agent(plistName: "agent.plist").unregister()
let replacement = try FileManager.default.url(
    for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)'
put Packages/ShuckKit/Sources/ShuckKit/History/HistoryWriter.swift 'try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
fchmod(descriptor, 0o600)'
put Packages/ShuckKit/Sources/ShuckKitTestSupport/FakeTool.swift 'let script = "#!/bin/sh\nexit 0"
try script.write(to: url, atomically: true, encoding: .utf8)'
put ShuckTests/TrashTests.swift '#expect(environment.trash is SystemTrash)'
put Packages/ShuckKit/Tests/ShuckKitTests/SomeTests.swift 'print("debug output in a test")
#expect(ResultRow.folder(of: file, home: home) == "~/Downloads")
let info = ProcessInfo.processInfo
let scratch = URL.temporaryDirectory.appending(path: "scratch")
let duplicate = entries.filter { $0.isDuplicate }'
put "$app" '// URLSession is banned, and this comment mentions it without using it.
NSWorkspace.shared.open(settingsURL)
Link("Privacy settings", destination: settingsURL)
let processName = ProcessInfo.processInfo.processName
let n = items.remove(at: 0)
remove(urls)
mutating func remove(_ urls: some Sequence<URL>) {}
let local = try Data(contentsOf: localURL)
let text = try String(contentsOf: localURL, encoding: .utf8)
for try await line in localURL.lines { use(line) }
let documentation = URL(string: "https://developer.apple.com/documentation/foundation/filemanager")
Link("Documentation", destination: URL(string: "https://developer.apple.com/documentation")!)
try await socket.connect(to: peer)
let task = connection.connect(host)
let fd = try FileDescriptor.open(path, .readOnly)
let home = URL.homeDirectory
let downloads = URL.downloadsDirectory
let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)'
put Shuck.xcodeproj/project.xcproj '"packages": [ { "kind": "local", "path": "Packages/ShuckKit" } ]'
expect_clean "allowed code"

if ((failed)); then
    echo "static-checks-test: FAILED" >&2
    exit 1
fi
echo "static-checks-test: OK"
