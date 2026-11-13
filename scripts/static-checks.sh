#!/bin/bash
# Static checks (ENG-006): rules from the PRD that a pattern search can enforce. CI runs this script; run it locally
# before committing.
#
# Usage: scripts/static-checks.sh [root]    root defaults to the repository; scripts/static-checks-test.sh passes a
#                                           fixture tree (a git repository)
#
# Each rule scans Swift code in the folders it covers, in the files git tracks (`git ls-files --cached`), so leftover
# worktrees and build output are not checked (#122). Whole-line comments are skipped. A call wrapped over several lines,
# as swift-format wraps `try data.write(` and `to: url)`, is joined into one logical line before matching, and a match
# is reported at the line the call starts on (#123). A call is joined while its brackets are open, while its line ends
# with a comma, and when the next line starts with `.`, up to 15 lines. One more check reads the tests: every Must SAF
# requirement is named in a test or a script (NFR-QA-001, D-133).
#
# The checks are a safety net, not a proof. A rule that blocks legitimate code goes to the advisor, who decides
# how it changes (AGENTS.md); never just work around it.

set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

failures=0
# Files in git's index, with paths as they are: git would quote one with non-ASCII letters, and the quoted name
# names no file. A tracked file deleted from the working tree is skipped where it is read.
tracked="$(git -C "$root" -c core.quotePath=false ls-files --cached)"
swift_files="$(grep -E '\.swift$' <<<"$tracked" || true)"

# The Must SAF requirements, each of which a test or a script must name (NFR-QA-001, D-133). SAF-015 is a Should.
must_saf="SAF-001 SAF-002 SAF-003 SAF-004 SAF-005 SAF-006 SAF-007 SAF-008 SAF-009 SAF-010 SAF-011 SAF-012 SAF-013
SAF-014 SAF-016 SAF-017 SAF-018"
# Where a Must SAF ID counts as named: tests, test support and scripts. This script holds the list, so it does not count.
saf_named_in='^(ShuckTests|ShuckUITests|Packages/ShuckKit/Tests|Packages/ShuckKit/Sources/ShuckKitTestSupport|scripts)/'

# Code that ships in the app: the app target and the engine's library modules (not tests or test support).
shipped='^(Shuck|Packages/ShuckKit/Sources/(ShuckKit|ShuckExecution))/'
# Shipped code outside the Execution module (SAF-017, D-28).
outside_execution='^(Shuck|Packages/ShuckKit/Sources/ShuckKit)/'
# The Execution module, the only code that may mutate files or start a subprocess.
execution='^Packages/ShuckKit/Sources/ShuckExecution/'
# Test code: the app's unit and UI tests, the engine's tests and its test support.
tests='^(ShuckTests|ShuckUITests|Packages/ShuckKit/(Tests|Sources/ShuckKitTestSupport))/'

report() {
    echo "$1" >&2
    failures=$((failures + 1))
}

# Joined copies of the Swift files: the same paths under a temporary folder, with the same number of lines. A comment
# line is empty. A wrapped call is on the line it starts on, with its other lines empty, so a match reports the first
# line's number. Bash 3.2 (macOS) and BSD awk must run this, so it uses nothing beyond POSIX awk.
joined="$(mktemp -d)"
trap 'rm -rf "$joined"' EXIT

join_awk='
function flush(   i) {
    if (out == "") return
    for (i = 1; i <= n; i++) print lines[i] > out
    close(out)
}
FNR == 1 {
    flush()
    out = dir "/" FILENAME
    n = 0; start = 0; depth = 0; trailing = 0
}
{
    n = FNR
    t = $0
    sub(/^[ \t]+/, "", t)
    if (t == "" || t ~ /^(\/\/|\*|\/\*)/) { lines[n] = ""; next }
    code = $0
    gsub(/"([^"\\]|\\.)*"/, "\"\"", code)
    sub(/\/\/.*$/, "", code)
    a = code; b = code; c = code; d = code
    opened = gsub(/\(/, "", a) + gsub(/\[/, "", b) - gsub(/\)/, "", c) - gsub(/\]/, "", d)
    if (start > 0 && n - start < 15 && (depth > 0 || trailing || t ~ /^\.[A-Za-z_]/)) {
        lines[start] = lines[start] " " t
        lines[n] = ""
        depth += opened
    } else {
        start = n
        lines[n] = $0
        depth = opened
    }
    if (depth < 0) depth = 0
    trailing = (code ~ /,[ \t]*$/)
}
END { flush() }'

existing=()
while IFS= read -r file; do
    [[ -n "$file" && -f "$file" ]] || continue
    existing+=("$file")
    if [[ "$file" == */* ]]; then mkdir -p "$joined/${file%/*}"; fi
    : >"$joined/$file"
done <<<"$swift_files"
if ((${#existing[@]} > 0)); then
    awk -v dir="$joined" "$join_awk" "${existing[@]}"
fi

# scan RULE MESSAGE PATTERN INCLUDE [EXCLUDE]: report code matching PATTERN in Swift files whose path matches INCLUDE
# and not EXCLUDE. The pattern is matched against logical lines, so it allows white space after a `(`.
scan() {
    local rule="$1" message="$2" pattern="$3" include="$4" exclude="${5:-}"
    local file hit rest
    local selected=()
    for file in ${existing[@]+"${existing[@]}"}; do
        [[ "$file" =~ $include ]] || continue
        if [[ -n "$exclude" && "$file" =~ $exclude ]]; then continue; fi
        selected+=("$file")
    done
    ((${#selected[@]} > 0)) || return 0
    while IFS= read -r hit; do
        [[ -n "$hit" ]] || continue
        file="${hit%%:*}"
        rest="${hit#*:}"
        report "$file:${rest%%:*}: [$rule] $message"
    done <<<"$(cd "$joined" && grep -nHE -- "$pattern" "${selected[@]}" || true)"
}

# NFR-SEC-001: no network APIs anywhere. `connect(` counts as a bare C call, not as a method such as `.connect(`.
scan network "network API; Shuck makes no network connections (NFR-SEC-001)" \
    '\b(URLSession|NSURLSession|NSURLConnection|URLSessionWebSocketTask|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFSocket[A-Za-z]*|CFStreamCreatePairWithSocket[A-Za-z]*|WKWebView|AsyncImage)\b|^[[:space:]]*import[[:space:]]+(Network|WebKit|CFNetwork|NetworkExtension)\b|\b(socket|getaddrinfo)\(|(^|[^.[:alnum:]_]|\bDarwin\.)connect\(' \
    '.'

# NFR-SEC-001: a loader given a remote URL. The line must hold an `http://` or `https://` literal, so a URL held in a
# variable is not caught; reading local files with these is fine. A rule's documentation link is a literal too, but it
# is only ever shown or opened, never passed to a loader.
scan network "loading a remote URL; Shuck makes no network connections (NFR-SEC-001)" \
    '(\b(Data|NSData|String|NSString)\([[:space:]]*contentsOf:|\.lines\b).*https?://|https?://.*(\b(Data|NSData|String|NSString)\([[:space:]]*contentsOf:|\.lines\b)' \
    '.'

# NFR-SEC-004: no shell execution in shipped code. Subprocesses use absolute paths and argument arrays (DEV-004).
scan shell "shell execution; use Process with an absolute path and an argument array (NFR-SEC-004)" \
    '"/bin/(ba|z|k|c|tc|da)?sh"|"/usr/bin/env"|\b(system|popen)\(|\bNSAppleScript\b|\bosascript\b' \
    "$shipped"

# ONB-003: no authorization or privilege APIs anywhere.
scan privilege "authorization or privilege API; the MVP never asks for admin rights (ONB-003)" \
    '\b(Authorization(Create|ExecuteWithPrivileges|CopyRights|MakeExternalForm)|AuthorizationRef|SMJobBless|kAuthorizationRight[A-Za-z]*|setuid|seteuid|setgid)\b|SMAppService\.daemon|\bsudo\b' \
    '.'

# SAF-017: only ShuckExecution may delete, move or modify files, or change launchd state. The C calls include their
# `*at`, `_np` and `f*` variants. Flags, dates, attribute lists, extended attributes, resource values and Finder icons
# change a file too, and so do iCloud's evict and move to the cloud. Any use of `SMAppService` counts, since its
# `register` and `unregister` change launchd state and the call can sit on another line than the type's name. C's
# `remove(` takes a path, so it counts only as a bare call (not a method such as `items.remove(at:)`) whose first
# argument is a string literal or names a path; the app's own `remove(urls)` methods, which a pattern cannot tell
# from it by name, do not count.
scan mutation "file or launchd mutation outside ShuckExecution (SAF-017)" \
    '\b(removeItem|trashItem|recycle|moveItem|replaceItem|replaceItemAt|unlink|unlinkat|rmdir|rename|renameat|renamex_np|renameatx_np|exchangedata|removefile|removefileat|truncate|ftruncate|copyfile|fcopyfile|clonefile|clonefileat|fclonefileat|chflags|lchflags|fchflags|utimes|lutimes|futimes|utimensat|futimens|setattrlist|fsetattrlist|setattrlistat|setxattr|fsetxattr|removexattr|fremovexattr|setResourceValue|setResourceValues|setIcon|SMLoginItemSetEnabled|evictUbiquitousItem|setUbiquitous)\(|(^|[^.[:alnum:]_]|\bDarwin\.)remove\(([[:space:]]*"|[^_)]*(path|Path|cString|fileSystemRepresentation))|\bSMAppService\b|"(bootout|bootstrap|kickstart|load|unload|enable|disable)"' \
    "$outside_execution"

# SAF-017, NFR-SEC-005: permissions and ownership change only in ShuckExecution, and in History for Shuck's own data
# folder and log (D-45).
scan permissions "permission or owner change outside ShuckExecution and History (SAF-017)" \
    '\b(setAttributes|chmod|fchmod|lchmod|fchmodat|chown|fchown|lchown|fchownat)\(' \
    "$outside_execution" \
    '^Packages/ShuckKit/Sources/ShuckKit/History/'

# SAF-017: creating or writing files is allowed only in ShuckExecution and in History, which writes Shuck's own log.
# The C calls count with or without a `Darwin.` prefix, but not as other types' methods, such as `NSWorkspace.open`.
# `create: true` is how `FileManager.url(for:in:appropriateFor:create:)` creates a folder, such as an item replacement
# folder; the label often sits on the call's second line. `NSWorkspace.duplicate` copies files. The System framework's
# `FileDescriptor.open` creates a file when its options hold `.create`; `mkstemp` and `mkdtemp` and their variants
# always create one.
scan file-write "file creation or write outside ShuckExecution and History (SAF-017)" \
    '\b(createFile|createDirectory|createSymbolicLink|linkItem|copyItem|OutputStream)\(|\.write\([[:space:]]*(to|toFile):|FileHandle\([[:space:]]*(forWritingTo|forWritingAtPath|forUpdating|forUpdatingAtPath)|\bcreate:[[:space:]]*true\b|\.duplicate\(|FileDescriptor\.open\(.*\.create\b|(^|[^.[:alnum:]_]|\bDarwin\.)(fopen|open|openat|creat|mkdir|mkdirat|mkfifo|mkfifoat|mknod|mknodat|symlink|symlinkat|link|linkat|mkstemp|mkstemps|mkostemp|mkostemps|mkdtemp)\(' \
    "$outside_execution" \
    '^Packages/ShuckKit/Sources/ShuckKit/History/'

# D-82: only ShuckExecution may start a subprocess, so every tool command goes through its checks (DEV-004, SAF-010).
# Any use of the `Process` type counts, so `let p: Process = .init()` does too; `ProcessInfo` is a different word.
# `NSUserUnixTask` runs a script outside the sandbox, and `NSXPCConnection` hands work to another process.
scan process "subprocess outside ShuckExecution (D-82)" \
    '\bProcess\b|\bNSTask\b|\bNSUserUnixTask\b|\bNSXPCConnection\b|\b(posix_spawn|posix_spawnp|fork|vfork|execv|execve|execvp|execl|execle|execlp)\(' \
    '.' \
    "$execution"

# SAF-017, D-82: `@_silgen_name` declares any C function, and `dlsym` and `dlopen` look one up by name, so each one
# reaches calls the rules above search for by name. No code uses them.
scan native-call "calling C by name (@_silgen_name, dlsym, dlopen) would bypass these checks (SAF-017, D-82)" \
    '@_silgen_name|\b(dlsym|dlopen)\(' \
    '.'

# SAF-016, AGENTS.md safety rule 3: test code never names the real home folder; it uses the fixture root. A "~/" string
# is fine, since nothing expands it unless asked. The user's folders count as the home folder: the search path domains
# that include them (`.userDomainMask`, `.allDomainsMask`) and the folders by name, as `URL`'s properties
# (`URL.downloadsDirectory`, or `.downloadsDirectory` where a `URL` is expected) or as `FileManager`'s search path
# folders. So does a real Trash (`SystemTrash()`, which moves items to the user's own Trash); tests use `FakeTrash`.
# Checking a value's type, as in `trash is SystemTrash`, is fine. `URL.temporaryDirectory` is not in the home folder.
scan real-home "the real home folder in test code; use the fixture root (SAF-016)" \
    '\b(homeDirectory|NSHomeDirectory|getpwuid|getpwnam|CFCopyHomeDirectoryURL|userDomainMask|allDomainsMask)|\.(userDirectory|documentsDirectory|desktopDirectory|downloadsDirectory|libraryDirectory|applicationSupportDirectory|cachesDirectory|moviesDirectory|musicDirectory|picturesDirectory|sharedPublicDirectory|trashDirectory)\b|\bSystemTrash\(|expandingTildeInPath|"HOME"' \
    "$tests"

# AGENTS.md: shipped code logs through Logger, never print.
scan print "print or NSLog in shipped code; use Logger (NFR-OBS-001)" \
    '(^|[^.[:alnum:]_])(print|debugPrint|dump|NSLog)\(' \
    "$shipped"

# AGENTS.md: no forced casts in the engine. swift-format covers force unwraps and try!.
scan force-cast "forced cast (as!) in the engine" \
    '[[:space:]]as![[:space:]]' \
    '^Packages/ShuckKit/'

# tracked_matching PATTERN [GREP OPTION]: the tracked files whose path matches PATTERN.
tracked_matching() {
    grep ${2:+"$2"} -E -- "$1" <<<"$tracked" || true
}

# NFR-SEC-002, D-29: no third-party packages. The only package is the local ShuckKit.
while IFS= read -r manifest; do
    [[ -f "$manifest" ]] || continue
    if grep -nE '\.package\(' "$manifest" >/dev/null; then
        report "$manifest: [packages] package dependency; Shuck uses Apple frameworks only (NFR-SEC-002)"
    fi
    # A binary target is a prebuilt framework that nobody reviews (#122).
    if grep -nE '\.binaryTarget\(' "$manifest" >/dev/null; then
        report "$manifest: [packages] binary target; Shuck builds all its code from source (NFR-SEC-002)"
    fi
done <<<"$(tracked_matching '(^|/)Package\.swift$')"

while IFS= read -r project; do
    [[ -f "$project" ]] || continue
    if grep -nE '"kind"[[:space:]]*:[[:space:]]*"remote"|"url"[[:space:]]*:|XCRemoteSwiftPackageReference' "$project" >/dev/null; then
        report "$project: [packages] remote package reference; only the local ShuckKit package is allowed (NFR-SEC-002, D-29)"
    fi
done <<<"$(tracked_matching '(^|/)project\.(xcproj|pbxproj)$')"

while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    report "$file: [packages] third-party dependency manager file (NFR-SEC-002)"
done <<<"$(tracked_matching '(^|/)(Package\.resolved|Podfile|Cartfile|Cartfile\.resolved)$')"

# ENG-010: AGENTS.md is the only agent-instruction file.
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    report "$file: [agents] use AGENTS.md only; do not add CLAUDE.md (ENG-010)"
done <<<"$(tracked_matching '(^|/)claude\.md$' -i)"

# NFR-QA-001, D-133: every Must SAF requirement is named, as a whole ID, in a test or a script.
named_files=()
while IFS= read -r file; do
    [[ -f "$file" && "$file" != scripts/static-checks.sh ]] || continue
    named_files+=("$file")
done <<<"$(tracked_matching "$saf_named_in")"
named_ids=""
if ((${#named_files[@]} > 0)); then
    named_ids="$(grep -ohE 'SAF-[0-9]+' "${named_files[@]}" | sort -u || true)"
fi
for id in $must_saf; do
    if ! grep -qx -- "$id" <<<"$named_ids"; then
        report "$id: [saf-tests] named in no test or script; add a test that names it (NFR-QA-001, D-133)"
    fi
done

if ((failures > 0)); then
    echo "static-checks: $failures problem(s)" >&2
    exit 1
fi
echo "static-checks: OK"
