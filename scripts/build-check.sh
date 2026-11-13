#!/bin/bash
# Builds what only a release or an older Mac would break, so CI finds it before a tag does (#126, ENG-005, ENG-007).
# scripts/test.sh builds the Debug configuration with the macOS 27 toolchain only.
#
# Usage: scripts/build-check.sh release   the app in the Release configuration, unsigned: the optimizer and the
#                                         release-only build settings (D-86) compile the same code differently
#        scripts/build-check.sh engine    the ShuckKit package with SwiftPM, which compiles it for macOS 26 alone from
#                                         Package.swift: an API newer than macOS 26 in the engine fails here even with
#                                         the macOS 27 SDK (NFR-COMP-001, D-06). CI's "Lint, build and test" runs it
#                                         with Xcode 27 (#213).
#
# Release signing happens only in scripts/build-dmg.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    release)
        echo "== Build the app, Release configuration, unsigned"
        xcodebuild build \
            -workspace Shuck.xcworkspace \
            -scheme Shuck \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -derivedDataPath build/DerivedData \
            COMPILATION_CACHE_ENABLE_CACHING=YES \
            CODE_SIGNING_ALLOWED=NO \
            | { grep -E --line-buffered '^(\*\*|.*error:|.*warning: )' || true; }
        # pipefail makes the pipeline fail when xcodebuild does, even though grep succeeds.
        ;;
    engine)
        echo "== Build the engine package with SwiftPM"
        swift build --package-path Packages/ShuckKit --build-path build/SwiftPM
        ;;
    *)
        echo "usage: scripts/build-check.sh release | engine" >&2
        exit 2
        ;;
esac
echo "build-check: OK"
