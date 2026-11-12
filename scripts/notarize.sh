#!/bin/bash
# Submits a file (.zip, .dmg or .pkg) to Apple's notary service and waits for the verdict (ENG-007). Stapling is the
# caller's job: scripts/build-dmg.sh staples the app and the DMG.
#
# Usage: scripts/notarize.sh FILE
#
# Credentials, in this order:
#   - An App Store Connect API key, as the release workflow provides: ASC_KEY_PATH (the .p8 file), ASC_KEY_ID and
#     ASC_ISSUER_ID.
#   - Otherwise a notarytool keychain profile, NOTARY_KEYCHAIN_PROFILE (default "shuck-notary"). Create it once with
#     `xcrun notarytool store-credentials shuck-notary` (docs/releasing.md).

set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "usage: scripts/notarize.sh FILE" >&2
    exit 2
fi
file="$1"

if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    credentials=(--key "$ASC_KEY_PATH" --key-id "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_PATH}" \
        --issuer "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_PATH}")
else
    credentials=(--keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-shuck-notary}")
fi

echo "notarize: submitting $(basename "$file")"
# set -e would stop at a failed submit before Apple's log is printed, so take the exit status by hand.
submit_status=0
output="$(xcrun notarytool submit "$file" "${credentials[@]}" --wait --output-format json)" || submit_status=$?

# Reads a key of the JSON output; empty when the output is not JSON or lacks the key.
field() {
    plutil -extract "$1" raw -o - - <<<"$output" 2>/dev/null || true
}
status="$(field status)"
id="$(field id)"

if [[ $submit_status -ne 0 || "$status" != "Accepted" ]]; then
    echo "notarize: failed (exit status $submit_status, status \"${status:-unknown}\", submission ${id:-unknown})" >&2
    if [[ -z "$status" || -z "$id" ]]; then
        echo "notarize: notarytool output:" >&2
        echo "$output" >&2
    fi
    if [[ -n "$id" ]]; then
        echo "notarize: Apple's log:" >&2
        xcrun notarytool log "$id" "${credentials[@]}" >&2 || true
    fi
    exit 1
fi
echo "notarize: accepted (submission $id)"
