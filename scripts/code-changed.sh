#!/bin/bash
# Says whether a change touches code: prints "true" if any file that differs between two commits is not documentation,
# and "false" otherwise. CI's "Check" runs only its static and changelog checks when this prints "false" (D-66).
#
# Usage: scripts/code-changed.sh BASE [HEAD]    HEAD defaults to the checked-out commit
#
# Documentation is Markdown files and LICENSE. Everything else counts as code, including workflows, scripts, project
# files and String Catalogs, so a file nobody thought of runs the full check. A rename counts both paths, so renaming
# a Swift file to .md still counts as code.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: scripts/code-changed.sh BASE [HEAD]" >&2
    exit 2
fi

changed="$(git diff --name-only --no-renames "$1" "${2:-HEAD}")"
code=false
while IFS= read -r path; do
    case "$path" in
        '' | *.md | LICENSE) ;;
        *)
            echo "code: $path" >&2
            code=true
            ;;
    esac
done <<<"$changed"
echo "$code"
