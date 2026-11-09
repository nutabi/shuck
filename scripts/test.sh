#!/bin/bash
# Runs every test the way CI does (ENG-005, ENG-012): one xcodebuild run of the engine tests, the app's unit tests and
# its UI tests, from the test plan Shuck.xctestplan, then the 80% engine coverage gate (D-44).
#
# Usage: scripts/test.sh                all tests
#        scripts/test.sh --no-ui        skip the UI tests (they take over the mouse and keyboard while they run)
#        scripts/test.sh --build-only   build for testing without running anything; CI's main branch runs it to keep
#                                       the compilation cache warm for pull requests (D-111)
#
# The engine and the app build once, in one Xcode build (D-111). `swift test --package-path Packages/ShuckKit` still
# runs the engine tests on their own, but it builds the engine again with SwiftPM.
#
# Xcode's compilation cache is on (COMPILATION_CACHE_ENABLE_CACHING), in build/DerivedData/CompilationCache.noindex.
# Its entries are keyed by content, not file dates, so CI can restore it into a fresh checkout and skip recompiling
# unchanged files (D-111).
#
# On CI (CI=true, set by GitHub Actions) the app is signed ad hoc, because runners have no certificates. Locally it
# keeps the project's signing: macOS ties UI-automation permission to the test runner's signature, and an ad hoc runner
# waits for an approval prompt. Release signing happens only in scripts/build-dmg.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

action=test
skip_ui=()
case "${1:-}" in
    "") ;;
    --no-ui) skip_ui=(-skip-testing:ShuckUITests) ;;
    --build-only) action=build-for-testing ;;
    *)
        echo "usage: scripts/test.sh [--no-ui | --build-only]" >&2
        exit 2
        ;;
esac

signing=()
if [[ "${CI:-}" == "true" ]]; then
    signing=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

# The upload step in ci.yml collects this bundle when a run fails (D-34). xcodebuild refuses to overwrite one.
result_bundle=build/DerivedData/Logs/Test/Shuck.xcresult
rm -rf "$result_bundle"

echo "== Build, then engine tests, app unit tests and UI tests"
xcodebuild "$action" \
    -workspace Shuck.xcworkspace \
    -scheme Shuck \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath build/DerivedData \
    -resultBundlePath "$result_bundle" \
    -enableCodeCoverage YES \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    ${skip_ui[@]+"${skip_ui[@]}"} \
    ${signing[@]+"${signing[@]}"} \
    | { grep -E --line-buffered '^(\*\*|Test Suite|Test case|✔|✘|◇ Test run|.*error:|.*warning: )' || true; }
# pipefail makes the pipeline fail when xcodebuild does, even though grep succeeds.

if [[ "$action" == build-for-testing ]]; then
    exit 0
fi

echo "== Engine line coverage (SM-4: at least 80%, test support not counted; D-44)"
coverage_json="$(mktemp)"
trap 'rm -f "$coverage_json"' EXIT
# The archive merges each file's line counts from every test bundle that ran it (D-111).
xcrun xccov view --archive --json "$result_bundle" > "$coverage_json"
python3 -I - "$coverage_json" <<'EOF'
import json, sys

archive = json.load(open(sys.argv[1]))
covered = count = 0
for path in sorted(archive):
    if "/Packages/ShuckKit/Sources/" not in path:
        continue
    lines = [line for line in archive[path] if line["isExecutable"]]
    hit = sum(1 for line in lines if line.get("executionCount", 0) > 0)
    name = path.split("/Packages/ShuckKit/Sources/", 1)[1]
    is_test_support = name.startswith("ShuckKitTestSupport/")
    if not is_test_support:
        covered += hit
        count += len(lines)
    percent = 100 * hit / len(lines) if lines else 100
    print(f"  {percent:6.1f}%  {name}{'  (not gated)' if is_test_support else ''}")
if not count:
    sys.exit("coverage: no executable engine code found; did the engine tests run?")
percent = 100 * covered / count
print(f"  {percent:6.1f}%  total of ShuckKit and ShuckExecution ({covered} of {count} lines)")
if percent < 80:
    sys.exit(f"coverage: {percent:.1f}% is below the 80% gate (SM-4)")
EOF
