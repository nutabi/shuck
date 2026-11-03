#!/bin/bash
# Static checks (ENG-006): rules from the PRD that a pattern search can enforce. CI runs this script; run it locally
# before committing.
#
# Usage: scripts/static-checks.sh [root]    root defaults to the repository; scripts/static-checks-test.sh passes a
#                                           fixture tree
#
# Each rule scans Swift code lines (whole-line comments are skipped) in the folders it covers. The checks are a safety
# net, not a proof: review still matters, and a rule that blocks legitimate code should be discussed with the owner,
# not worked around.

set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

failures=0
swift_files="$(find . -name '*.swift' -not -path '*/.build/*' -not -path './build/*' -not -path './.git/*' |
    sed 's|^\./||' | sort)"

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

# scan RULE MESSAGE PATTERN INCLUDE [EXCLUDE]: report code lines matching PATTERN in Swift files whose path matches
# INCLUDE and not EXCLUDE.
scan() {
    local rule="$1" message="$2" pattern="$3" include="$4" exclude="${5:-}"
    local file hits hit
    while IFS= read -r file; do
        [[ -n "$file" && "$file" =~ $include ]] || continue
        if [[ -n "$exclude" && "$file" =~ $exclude ]]; then continue; fi
        hits="$(grep -nE -- "$pattern" "$file" | grep -vE '^[0-9]+:[[:space:]]*(//|\*|/\*)' || true)"
        [[ -n "$hits" ]] || continue
        while IFS= read -r hit; do
            report "$file:${hit%%:*}: [$rule] $message"
        done <<<"$hits"
    done <<<"$swift_files"
}

# NFR-SEC-001: no network APIs anywhere.
scan network "network API; Shuck makes no network connections (NFR-SEC-001)" \
    '\b(URLSession|NSURLSession|NSURLConnection|URLSessionWebSocketTask|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFSocket[A-Za-z]*|CFStreamCreatePairWithSocket[A-Za-z]*|WKWebView)\b|^[[:space:]]*import[[:space:]]+(Network|WebKit)\b|\bsocket\(' \
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
# change a file too. Any use of `SMAppService` counts, since its `register` and `unregister` change launchd state and
# the call can sit on another line than the type's name.
scan mutation "file or launchd mutation outside ShuckExecution (SAF-017)" \
    '\b(removeItem|trashItem|recycle|moveItem|replaceItem|replaceItemAt|unlink|unlinkat|rmdir|rename|renameat|renamex_np|renameatx_np|exchangedata|removefile|removefileat|truncate|ftruncate|copyfile|fcopyfile|clonefile|clonefileat|fclonefileat|chflags|lchflags|fchflags|utimes|lutimes|futimes|utimensat|futimens|setattrlist|fsetattrlist|setattrlistat|setxattr|fsetxattr|removexattr|fremovexattr|setResourceValue|setResourceValues|setIcon|SMLoginItemSetEnabled)\(|\bSMAppService\b|"(bootout|bootstrap|kickstart|load|unload|enable|disable)"' \
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
# folder; the label often sits on the call's second line. `NSWorkspace.duplicate` copies files.
scan file-write "file creation or write outside ShuckExecution and History (SAF-017)" \
    '\b(createFile|createDirectory|createSymbolicLink|linkItem|copyItem|OutputStream)\(|\.write\((to|toFile):|FileHandle\((forWritingTo|forWritingAtPath|forUpdating|forUpdatingAtPath)|\bcreate:[[:space:]]*true\b|\.duplicate\(|(^|[^.[:alnum:]_]|\bDarwin\.)(fopen|open|openat|creat|mkdir|mkdirat|mkfifo|mkfifoat|mknod|mknodat|symlink|symlinkat|link|linkat)\(' \
    "$outside_execution" \
    '^Packages/ShuckKit/Sources/ShuckKit/History/'

# D-82: only ShuckExecution may start a subprocess, so every tool command goes through its checks (DEV-004, SAF-010).
# Any use of the `Process` type counts, so `let p: Process = .init()` does too; `ProcessInfo` is a different word.
scan process "subprocess outside ShuckExecution (D-82)" \
    '\bProcess\b|\bNSTask\b|\b(posix_spawn|posix_spawnp|fork|vfork|execv|execve|execvp|execl|execle|execlp)\(' \
    '.' \
    "$execution"

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

# NFR-SEC-002, D-29: no third-party packages. The only package is the local ShuckKit.
while IFS= read -r manifest; do
    [[ -n "$manifest" ]] || continue
    if grep -nE '\.package\(' "$manifest" >/dev/null; then
        report "$manifest: [packages] package dependency; Shuck uses Apple frameworks only (NFR-SEC-002)"
    fi
done <<<"$(find . -name Package.swift -not -path '*/.build/*' -not -path './build/*' | sed 's|^\./||')"

while IFS= read -r project; do
    [[ -n "$project" ]] || continue
    if grep -nE '"kind"[[:space:]]*:[[:space:]]*"remote"|"url"[[:space:]]*:|XCRemoteSwiftPackageReference' "$project" >/dev/null; then
        report "$project: [packages] remote package reference; only the local ShuckKit package is allowed (NFR-SEC-002, D-29)"
    fi
done <<<"$(find . \( -name project.xcproj -o -name project.pbxproj \) -not -path './build/*' | sed 's|^\./||')"

while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    report "$file: [packages] third-party dependency manager file (NFR-SEC-002)"
done <<<"$(find . \( -name Package.resolved -o -name Podfile -o -name Cartfile -o -name Cartfile.resolved \) \
    -not -path '*/.build/*' -not -path './build/*' -not -path './.git/*' | sed 's|^\./||')"

# ENG-010: AGENTS.md is the only agent-instruction file.
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    report "$file: [agents] use AGENTS.md only; do not add CLAUDE.md (ENG-010)"
done <<<"$(find . -iname 'CLAUDE.md' -not -path './.git/*' -not -path '*/.build/*' | sed 's|^\./||')"

if ((failures > 0)); then
    echo "static-checks: $failures problem(s)" >&2
    exit 1
fi
echo "static-checks: OK"
