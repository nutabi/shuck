#!/bin/bash
# Prints a version's release notes: its section of CHANGELOG.md, then a link to the full changelog (D-95). The Release
# workflow uses them for the GitHub release, so a version without a section, or without a link, fails the release.
#
# Usage: scripts/release-notes.sh VERSION    for example scripts/release-notes.sh 0.1.1

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
    echo "usage: scripts/release-notes.sh VERSION" >&2
    exit 2
fi
version="$1"

# The section runs from its "## [VERSION]" heading to the next heading or to the link definitions at the end. Blank
# lines before its first line are left out; $(...) drops those after its last. A GitHub release shows each line break,
# so a bullet's wrapped lines, indented by two spaces, are joined onto the bullet.
notes="$(awk -v heading="## [$version]" '
    index($0, heading) == 1 { found = 1; next }
    !found { next }
    /^## \[/ || /^\[[^]]+\]: / { exit }
    !started && /^$/ { next }
    /^  [^ ]/ && line != "" { sub(/^ +/, ""); line = line " " $0; next }
    { if (started) print line; started = 1; line = $0 }
    END { if (started) print line }
' CHANGELOG.md)"
link="$(awk -v prefix="[$version]: " '
    index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }
' CHANGELOG.md)"

if [[ -z "$notes" ]]; then
    echo "release-notes: CHANGELOG.md has no notes for $version" >&2
    exit 1
fi
if [[ -z "$link" ]]; then
    echo "release-notes: CHANGELOG.md has no link for [$version]" >&2
    exit 1
fi

printf '%s\n\n**Full changelog**: %s\n' "$notes" "$link"
