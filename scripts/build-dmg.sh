#!/bin/bash
# Builds the release DMG (ENG-007): archive → Developer ID signature → notarize and staple the app → DMG → sign,
# notarize and staple the DMG → SHA-256 checksum. The release workflow runs this script; the owner can run it locally
# to release without CI (ENG-012, docs/releasing.md).
#
# Usage: scripts/build-dmg.sh [--skip-notarization]
#
# Environment:
#   SHUCK_SIGN_IDENTITY   signing identity (default "Developer ID Application"). "-" signs ad hoc for a local dry
#                         run, which requires --skip-notarization.
#   SHUCK_TEAM_ID         Apple Developer team (default XCJ348BL6P, the project's team)
#   SHUCK_EXPECT_VERSION  fail unless the app's version (MARKETING_VERSION) equals this; the release workflow passes the
#                         tag's version
#   Notarization credentials: see scripts/notarize.sh.
#
# Output: build/release/Shuck-<version>.dmg and Shuck-<version>.dmg.sha256

set -euo pipefail
cd "$(dirname "$0")/.."

notarize=true
case "${1:-}" in
    "") ;;
    --skip-notarization) notarize=false ;;
    *)
        echo "usage: scripts/build-dmg.sh [--skip-notarization]" >&2
        exit 2
        ;;
esac

identity="${SHUCK_SIGN_IDENTITY:-Developer ID Application}"
team="${SHUCK_TEAM_ID:-XCJ348BL6P}"
timestamp=(--timestamp)
if [[ "$identity" == "-" ]]; then
    if $notarize; then
        echo "build-dmg: ad hoc signing cannot be notarized; add --skip-notarization" >&2
        exit 2
    fi
    team=""
    timestamp=()
fi

out=build/release
rm -rf "$out"
mkdir -p "$out"

version="$(xcodebuild -project Shuck.xcodeproj -scheme Shuck -configuration Release -showBuildSettings 2>/dev/null |
    awk '$1 == "MARKETING_VERSION" { print $3; exit }')"
if [[ -n "${SHUCK_EXPECT_VERSION:-}" && "$version" != "$SHUCK_EXPECT_VERSION" ]]; then
    echo "build-dmg: the app's version is $version but the tag says $SHUCK_EXPECT_VERSION." >&2
    echo "build-dmg: bump MARKETING_VERSION in a pull request before tagging (docs/releasing.md)." >&2
    exit 1
fi
# The build number counts commits, so it always increases along main and is the same locally and on CI.
build_number="$(git rev-list --count HEAD)"
echo "build-dmg: Shuck $version ($build_number), signed with \"$identity\""

xcodebuild archive \
    -project Shuck.xcodeproj \
    -scheme Shuck \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$out/Shuck.xcarchive" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    DEVELOPMENT_TEAM="$team" \
    OTHER_CODE_SIGN_FLAGS="${timestamp[*]-}" \
    CURRENT_PROJECT_VERSION="$build_number" \
    | { grep -E --line-buffered '^(\*\*|.*error:)' || true; }

app="$out/Shuck.app"
ditto "$out/Shuck.xcarchive/Products/Applications/Shuck.app" "$app"

# NFR-SEC-003: Hardened Runtime on, and no get-task-allow (which would let other processes attach a debugger).
codesign --verify --strict --deep "$app"
# Capture before grepping: grep -q exits early, and pipefail would turn codesign's SIGPIPE into a failure.
signature="$(codesign --display --verbose "$app" 2>&1)"
entitlements="$(codesign --display --entitlements - --xml "$app" 2>/dev/null || true)"
if ! grep -qE '^CodeDirectory .*flags=.*runtime' <<<"$signature"; then
    echo "build-dmg: Hardened Runtime is off" >&2
    exit 1
fi
if grep -q 'get-task-allow' <<<"$entitlements"; then
    echo "build-dmg: the release build has the get-task-allow entitlement" >&2
    exit 1
fi

if $notarize; then
    ditto -c -k --keepParent "$app" "$out/Shuck.zip"
    scripts/notarize.sh "$out/Shuck.zip"
    xcrun stapler staple "$app"
    rm "$out/Shuck.zip"
fi

dmg="$out/Shuck-$version.dmg"
staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Shuck.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Shuck" -srcfolder "$staging" -format UDZO -ov "$dmg"
rm -rf "$staging"
codesign --sign "$identity" ${timestamp[@]+"${timestamp[@]}"} "$dmg"

if $notarize; then
    scripts/notarize.sh "$dmg"
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi

(cd "$out" && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
echo "build-dmg: $dmg"
cat "$dmg.sha256"
