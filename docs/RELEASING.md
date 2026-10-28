# Releasing Agentch

Pushing a version tag builds a DMG on GitHub Actions and attaches it to a GitHub release:

```sh
# 1. Move the notes under [Unreleased] in CHANGELOG.md to a new "## [0.2.0]" section.
# 2. Commit, tag and push.
git commit -am "Release 0.2.0"
git tag v0.2.0
git push && git push --tags
```

The version comes from the tag, and the build number from the workflow run, so there is nothing to bump in the project. The release notes are the version's section of `CHANGELOG.md`.

To build the same DMG locally (it lands in `dist/`):

```sh
scripts/release.sh 0.2.0
```

## What gets signed

| Secrets present | Result |
| --- | --- |
| None | Ad-hoc signed DMG, published as a **draft** release. macOS blocks it on other Macs. |
| Certificate + notary key | Signed with Developer ID, notarized and stapled, published as a normal release. |
| …plus the tap token | Also updates the cask in `Osmait/homebrew-tap`. |

## One-time setup after joining the Apple Developer Program

### 1. Developer ID certificate

1. In Xcode, go to **Settings → Accounts**, select the team and click **Manage Certificates…**. Click **+** and choose **Developer ID Application**.
2. In **Keychain Access**, find "Developer ID Application: …", right-click it, choose **Export**, and save it as a `.p12` file with a strong password.
3. Add these repository secrets (**Settings → Secrets and variables → Actions**):
   - `DEVELOPER_ID_CERTIFICATE`: the `.p12` in base64. Copy it with `base64 -i certificate.p12 | pbcopy`.
   - `DEVELOPER_ID_CERTIFICATE_PASSWORD`: the export password.
   - `APPLE_TEAM_ID`: the team ID, shown at developer.apple.com → Membership.
4. Delete the exported `.p12` from disk.

### 2. Notarization key

1. In App Store Connect, go to **Users and Access → Integrations → App Store Connect API**. Create a key with the **Developer** role and download the `.p8`. It can only be downloaded once.
2. Add these secrets:
   - `NOTARY_KEY`: the `.p8` in base64 (`base64 -i AuthKey_XXXX.p8 | pbcopy`).
   - `NOTARY_KEY_ID`: the key ID.
   - `NOTARY_ISSUER_ID`: the issuer ID shown above the key list.

To notarize local builds too, store the same key once in your Keychain:

```sh
xcrun notarytool store-credentials agentch --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
SIGN_IDENTITY="Developer ID Application" TEAM_ID=<TEAM_ID> NOTARY_PROFILE=agentch scripts/release.sh 0.2.0
```

### 3. Homebrew tap

1. Create a **public** repository named `Osmait/homebrew-tap`.
2. Create a fine-grained personal access token with **Contents: Read and write** on that repository only, and add it as the `HOMEBREW_TAP_TOKEN` secret.

From the next release on, users can install with:

```sh
brew install --cask osmait/tap/agentch
```

### 4. Make the repository public

Releases in a private repository can't be downloaded by anyone else, and Homebrew downloads the DMG from the release.
