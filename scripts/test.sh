#!/bin/bash
# Runs every test the way CI does (ENG-005, ENG-012): engine tests with an 80% coverage gate (D-44), then the app build
# with its unit and UI tests.
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

echo "== Engine line coverage (SM-4: at least 80%, test support not counted; D-44)"
codecov_json="$(swift test --package-path Packages/ShuckKit --show-codecov-path)"
python3 -I - "$codecov_json" <<'EOF'
import json, sys

files = json.load(open(sys.argv[1]))["data"][0]["files"]
sources = [f for f in files if "/Sources/" in f["filename"] and "/.build/" not in f["filename"]]
gated = []
for f in sorted(sources, key=lambda f: f["filename"]):
    lines = f["summary"]["lines"]
    name = f["filename"].split("/Sources/", 1)[1]
    is_test_support = name.startswith("ShuckKitTestSupport/")
    if not is_test_support:
        gated.append(f)
    print(f"  {lines['percent']:6.1f}%  {name}{'  (not gated)' if is_test_support else ''}")
covered = sum(f["summary"]["lines"]["covered"] for f in gated)
count = sum(f["summary"]["lines"]["count"] for f in gated)
if not count:
    sys.exit("coverage: no executable engine code found; is the report path right?")
percent = 100 * covered / count
print(f"  {percent:6.1f}%  total of ShuckKit and ShuckExecution ({covered} of {count} lines)")
if percent < 80:
    sys.exit(f"coverage: {percent:.1f}% is below the 80% gate (SM-4)")
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
