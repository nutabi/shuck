#!/bin/bash
# Runs every test the way CI does (ENG-005, ENG-012): engine tests with a coverage report, then the app build with its
# unit and UI tests.
#
# Usage: scripts/test.sh            all tests
#        scripts/test.sh --no-ui    skip the UI tests (they take over the mouse and keyboard while they run)
#
# On CI (CI=true, set by GitHub Actions) the app is signed ad hoc, because runners have no certificates. Locally it
# keeps the project's signing: macOS ties UI-automation permission to the test runner's signature, and an ad hoc runner
# waits for an approval prompt. Release signing happens only in scripts/build-dmg.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

skip_ui=()
case "${1:-}" in
    "") ;;
    --no-ui) skip_ui=(-skip-testing:ShuckUITests) ;;
    *)
        echo "usage: scripts/test.sh [--no-ui]" >&2
        exit 2
        ;;
esac

signing=()
if [[ "${CI:-}" == "true" ]]; then
    signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

echo "== Engine tests (Packages/ShuckKit)"
swift test --package-path Packages/ShuckKit --enable-code-coverage

echo "== Engine line coverage (report only until the engine has code; target SM-4: 80%)"
codecov_json="$(swift test --package-path Packages/ShuckKit --show-codecov-path)"
python3 -I - "$codecov_json" <<'EOF'
import json, sys

files = json.load(open(sys.argv[1]))["data"][0]["files"]
sources = [f for f in files if "/Sources/" in f["filename"] and "/.build/" not in f["filename"]]
for f in sorted(sources, key=lambda f: f["filename"]):
    lines = f["summary"]["lines"]
    print(f"  {lines['percent']:6.1f}%  {f['filename'].split('/Sources/', 1)[1]}")
covered = sum(f["summary"]["lines"]["covered"] for f in sources)
count = sum(f["summary"]["lines"]["count"] for f in sources)
if count:
    print(f"  {100 * covered / count:6.1f}%  total ({covered} of {count} lines)")
else:
    print("  no executable engine code yet")
EOF

echo "== App build, unit tests and UI tests"
xcodebuild test \
    -project Shuck.xcodeproj \
    -scheme Shuck \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build/DerivedData \
    -enableCodeCoverage YES \
    ${skip_ui[@]+"${skip_ui[@]}"} \
    ${signing[@]+"${signing[@]}"} \
    | { grep -E --line-buffered '^(\*\*|Test Suite|Test case|✔|✘|◇ Test run|.*error:|.*warning: )' || true; }
# pipefail makes the pipeline fail when xcodebuild does, even though grep succeeds.
