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

result="$(mktemp)"
trap 'rm -f "$result"' EXIT

echo "notarize: submitting $(basename "$file")"
xcrun notarytool submit "$file" "${credentials[@]}" --wait --output-format json >"$result"
status="$(plutil -extract status raw -o - "$result")"
id="$(plutil -extract id raw -o - "$result")"

if [[ "$status" != "Accepted" ]]; then
    echo "notarize: $status (submission $id). Apple's log:" >&2
    xcrun notarytool log "$id" "${credentials[@]}" >&2 || true
    exit 1
fi
echo "notarize: accepted (submission $id)"
