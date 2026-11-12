#!/bin/bash
# Lints all Swift code with swift-format (ENG-004, ENG-005) and checks that user-facing strings have String Catalog
# entries (NFR-L10N-001, scripts/strings-check.py).
#
# Usage: scripts/lint.sh          report problems and fail if there are any
#        scripts/lint.sh --fix    rewrite files in place, then lint again
#
# Formatting rules live in .swift-format; Packages/ShuckKit/.swift-format adds the engine's stricter rules.

set -euo pipefail
cd "$(dirname "$0")/.."

paths=(
    Shuck
    ShuckTests
    ShuckUITests
    Packages/ShuckKit/Package.swift
    Packages/ShuckKit/Sources
    Packages/ShuckKit/Tests
)

if [[ "${1:-}" == "--fix" ]]; then
    xcrun swift-format format --in-place --recursive --parallel "${paths[@]}"
elif [[ $# -gt 0 ]]; then
    echo "usage: scripts/lint.sh [--fix]" >&2
    exit 2
fi

xcrun swift-format lint --strict --recursive --parallel "${paths[@]}"
python3 -I scripts/strings-check.py --self-test || { echo "lint: the strings check fails its own examples" >&2; exit 1; }
python3 -I scripts/strings-check.py || { echo "lint: user-facing strings are missing from a String Catalog (NFR-L10N-001)" >&2; exit 1; }
echo "lint: OK"
