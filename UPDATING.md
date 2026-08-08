# Publishing a TimeVault Update

TimeVault uses Sparkle for secure automatic updates. The release script creates
the signed update metadata automatically.

## Before building

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the TimeVault
   target’s Build Settings.
2. Update `Distribution/ReleaseNotes.md`.
3. Confirm that the release will be signed with the same stable
   certificate-backed identity as the previous release. Use Developer ID
   Application for notarized distribution, or a self-signed identity for
   personal use on this Mac. macOS Full Disk Access is tied to the app's
   bundle identity and code signature.

## Build the release

```zsh
./Scripts/build-dmg.sh
```

The script builds and signs the app, creates and verifies the customized DMG,
signs the DMG for Sparkle, and writes:

- `dist/TimeVault.dmg`
- `dist/appcast.xml`
- `appcast.xml`

If the signing identity is not discoverable automatically, set
`TIMEVAULT_CODESIGN_IDENTITY` before running the script. The script refuses to
produce a release DMG without a stable certificate-backed identity. Ad hoc
signing is available only as an explicit local-testing opt-in:

```zsh
TIMEVAULT_ALLOW_ADHOC_SIGNING=1 ./Scripts/build-dmg.sh
```

Ad hoc updates may require Full Disk Access approval again. Install the
release in `/Applications` and keep the bundle identifier and certificate
unchanged so macOS can preserve the approval across signed updates. A
self-signed identity is not trusted for notarization or general distribution.

## Publish on GitHub

1. Commit and push the updated source, version, release notes, and root
   `appcast.xml` to `main`.
2. Create a GitHub release tagged `v<version>`.
3. Upload `dist/TimeVault.dmg` as a release asset.
4. Confirm the release asset URL matches the enclosure URL in `appcast.xml`.
5. Open the raw `appcast.xml` URL in a browser and confirm it is publicly
   accessible.

The appcast URL used by TimeVault is:

```text
https://raw.githubusercontent.com/MinimackStudios/TimeVault/main/appcast.xml
```
