# Releasing

How a signed, notarized Shuck DMG gets from a tag to a GitHub release (ENG-007 to ENG-009, D-17). CI does the work;
the owner publishes.

## Cutting a release

1. In a pull request, set **MARKETING_VERSION** in `Shuck.xcodeproj/project.xcproj` to the new version (Semantic
   Versioning, ENG-009). It is set once, in the project's own build settings, and every target inherits it (D-86). The
   release fails if the tag and the app's version differ. The build number is set automatically from the commit count.
   A milestone release takes the milestone's version (D-30). A fix for a High-severity bug in a published release may
   go out as a patch release, such as 0.1.1, before the milestone ends (D-94).

   In the same pull request, turn `## [Unreleased]` in `CHANGELOG.md` into the version's section, for example
   `## [0.1.1] - 2026-11-03`, with the day you expect to tag, and add an empty `## [Unreleased]` above it. Update the
   links at the end: `[Unreleased]` compares the new tag with `HEAD`, and the new version compares the previous tag
   with the new one. `scripts/release-notes.sh 0.1.1` prints the notes the release will get.
2. Merge the pull request.
3. Tag the merge commit on `main` and push the tag:

   ```bash
   git switch main && git pull
   git tag v0.0.1
   git push origin v0.0.1
   ```

4. The **Release** workflow (`.github/workflows/release.yml`) checks the tag is on `main`, runs the static checks,
   writes the version's notes from `CHANGELOG.md` and fails if it has none (D-95), then runs `scripts/build-dmg.sh`:
   archive, sign with Developer ID, notarize and staple the app, build the DMG, sign, notarize and staple it, and write
   a SHA-256 checksum. The job first waits for your approval in the `release` environment (**Review deployments** on
   the run's page), before it reads any secret. Once the build passes, it **publishes** the release with both files
   and the notes, with no further step (D-174). Versions below 1.0.0 are marked as pre-releases.
5. Download the DMG from the release, open it on your Mac, and check that Shuck launches without a Gatekeeper warning.
   If a note needs fixing, edit the release and fix `CHANGELOG.md` in a pull request too, so the two stay the same.
   If the build itself is wrong, mark the release as a pre-release or delete it, and release the fix as the next
   patch version.

## One-time setup

### Certificates and keys

- **Developer ID Application certificate.** Create it in Xcode (**Settings → Accounts → Manage Certificates → + →
  Developer ID Application**) or on the Apple Developer website. Then, in Keychain Access, export the certificate
  *with its private key* as a `.p12` file with a strong password.
- **App Store Connect API key for notarization.** In App Store Connect, **Users and Access → Integrations → App Store
  Connect API → Team Keys**, create a key with the **Developer** role, the narrowest role that can notarize (R-13).
  Download the `.p8` file (you can only download it once) and note the key ID and the issuer ID.

### GitHub environment and secrets (ENG-008)

1. In **Settings → Environments**, create an environment named **`release`**.
2. Under **Deployment branches and tags**, choose **Selected branches and tags** and add the tag rule `v*`. Pull request
   workflows can then never read its secrets.
3. Optionally add yourself as a **required reviewer**, so each release waits for your click before signing.
4. Add these **environment secrets**:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy`, then paste |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The `.p12` export password |
| `ASC_KEY_ID` | The API key's ID, for example `ABC123DEFG` |
| `ASC_ISSUER_ID` | The issuer ID shown above the keys list |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_ABC123DEFG.p8 \| pbcopy`, then paste |

Delete the local `.p12` and `.p8` copies once they are stored, or keep them only in a password manager. If any secret
might have leaked, revoke the certificate or key in Apple's portal and replace the secrets.

## Releasing without CI (ENG-012)

The same scripts run locally, with the Developer ID certificate in your login keychain.

1. Store notarization credentials once. notarytool keeps them in your keychain under the profile name `shuck-notary`:

   ```bash
   xcrun notarytool store-credentials shuck-notary --key AuthKey_ABC123DEFG.p8 --key-id ABC123DEFG --issuer <issuer-id>
   ```

2. From a clean checkout of the tag:

   ```bash
   SHUCK_EXPECT_VERSION=0.0.1 scripts/build-dmg.sh
   ```

3. Publish the release yourself, with the notes from `CHANGELOG.md`:

   ```bash
   scripts/release-notes.sh 0.0.1 > build/release/notes.md
   ```

   ```bash
   gh release create v0.0.1 --verify-tag --prerelease --title "Shuck 0.0.1" --notes-file build/release/notes.md build/release/Shuck-0.0.1.dmg build/release/Shuck-0.0.1.dmg.sha256
   ```

For a dry run without a certificate, `SHUCK_SIGN_IDENTITY=- scripts/build-dmg.sh --skip-notarization` signs ad hoc and
skips notarization. That DMG is for checking the packaging only; never publish it.
