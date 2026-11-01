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

# SAF-017: only ShuckExecution may delete, move or modify files, or change launchd state.
scan mutation "file or launchd mutation outside ShuckExecution (SAF-017)" \
    '\b(removeItem|trashItem|recycle|moveItem|replaceItem|replaceItemAt|setAttributes|unlink|rmdir|rename|removefile|chmod|chown|truncate)\(|"(bootout|bootstrap|kickstart|load|unload|enable|disable)"' \
    "$outside_execution"

# SAF-017: creating or writing files is allowed only in ShuckExecution and in History, which writes Shuck's own log.
scan file-write "file creation or write outside ShuckExecution and History (SAF-017)" \
    '\b(createFile|createDirectory|createSymbolicLink|linkItem|copyItem)\(|\.write\(to:|FileHandle\((forWritingTo|forWritingAtPath|forUpdating|forUpdatingAtPath)|(^|[^.[:alnum:]_])(fopen|open|creat|mkdir)\(' \
    "$outside_execution" \
    '^Packages/ShuckKit/Sources/ShuckKit/History/'

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
