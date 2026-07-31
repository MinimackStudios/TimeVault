# Publishing a TimeVault Update

TimeVault uses Sparkle for secure automatic updates. The release script creates
the signed update metadata automatically.

## Before building

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the TimeVault
   target’s Build Settings.
2. Update `Distribution/ReleaseNotes.md`.

## Build the release

```zsh
./Scripts/build-dmg.sh
```

The script builds and ad hoc signs the app, creates and verifies the customized
DMG, signs the DMG for Sparkle, and writes:

- `dist/TimeVault.dmg`
- `dist/appcast.xml`
- `appcast.xml`

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
