#!/bin/bash
# Prints a version's release notes: its section of CHANGELOG.md, then a link to the full changelog (D-95). The Release
# workflow uses them for the GitHub release, so a version without a section, or without a link, fails the release.
# With --check, it checks that every released version has notes and a link, and that Unreleased has a heading and a
# link, so CI finds a broken changelog before a release does. With --tag-ready, it also fails when "## [Unreleased]"
# still holds entries: at a tagged commit they would be missing from every release's notes (#180). Releasing moves
# them under the version's heading (docs/releasing.md); the Release workflow runs --tag-ready before it builds.
#
# Usage: scripts/release-notes.sh VERSION    for example scripts/release-notes.sh 0.1.1
#        scripts/release-notes.sh --check
#        scripts/release-notes.sh --tag-ready

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
    echo "usage: scripts/release-notes.sh VERSION | --check | --tag-ready" >&2
    exit 2
fi

# section VERSION: prints the version's section. It runs from its "## [VERSION]" heading to the next heading or to the
# link definitions at the end. Blank lines before its first line are left out; $(...) drops those after its last. A
# GitHub release shows each line break, so a bullet's wrapped lines, indented by two spaces, are joined onto the bullet.
section() {
    awk -v heading="## [$1]" '
        index($0, heading) == 1 { found = 1; next }
        !found { next }
        /^## \[/ || /^\[[^]]+\]: / { exit }
        !started && /^$/ { next }
        /^  [^ ]/ && line != "" { sub(/^ +/, ""); line = line " " $0; next }
        { if (started) print line; started = 1; line = $0 }
        END { if (started) print line }
    ' CHANGELOG.md
}

# link VERSION: prints the version's link definition, such as its comparison with the version before.
link() {
    awk -v prefix="[$1]: " '
        index($0, prefix) == 1 { print substr($0, length(prefix) + 1); exit }
    ' CHANGELOG.md
}

if [[ "$1" == --check ]]; then
    failed=0
    if ! grep -qxF '## [Unreleased]' CHANGELOG.md; then
        echo "release-notes: CHANGELOG.md has no \"## [Unreleased]\" heading" >&2
        failed=1
    fi
    if [[ -z "$(link Unreleased)" ]]; then
        echo "release-notes: CHANGELOG.md has no link for [Unreleased]" >&2
        failed=1
    fi
    while IFS= read -r version; do
        [[ -n "$version" ]] || continue
        if [[ -z "$(section "$version")" ]]; then
            echo "release-notes: CHANGELOG.md has no notes for $version" >&2
            failed=1
        fi
        if [[ -z "$(link "$version")" ]]; then
            echo "release-notes: CHANGELOG.md has no link for [$version]" >&2
            failed=1
        fi
    done <<<"$(sed -nE 's/^## \[([^]]+)\].*/\1/p' CHANGELOG.md | grep -vxF Unreleased || true)"
    if ((failed)); then
        exit 1
    fi
    echo "release-notes: CHANGELOG.md OK"
    exit 0
fi

if [[ "$1" == --tag-ready ]]; then
    if ! grep -qxF '## [Unreleased]' CHANGELOG.md; then
        echo "release-notes: CHANGELOG.md has no \"## [Unreleased]\" heading" >&2
        exit 1
    fi
    if [[ -n "$(section Unreleased)" ]]; then
        echo "release-notes: \"## [Unreleased]\" in CHANGELOG.md still has entries; move them under the version" >&2
        echo "release-notes: being released before tagging (docs/releasing.md), or they miss its notes (#180)" >&2
        exit 1
    fi
    echo "release-notes: Unreleased is empty"
    exit 0
fi

version="$1"
notes="$(section "$version")"
link="$(link "$version")"

if [[ -z "$notes" ]]; then
    echo "release-notes: CHANGELOG.md has no notes for $version" >&2
    exit 1
fi
if [[ -z "$link" ]]; then
    echo "release-notes: CHANGELOG.md has no link for [$version]" >&2
    exit 1
fi

printf '%s\n\n**Full changelog**: %s\n' "$notes" "$link"
