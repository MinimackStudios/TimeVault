# TimeVault

TimeVault is a read-only macOS app for understanding Time Machine protection.
Its dashboard reports backup activity, startup-disk capacity, and local APFS
snapshot counts. Its snapshot browser shows local snapshots alongside mounted
backup snapshots, which can be compared to report added, removed, modified,
and metadata-only items, logical size changes, and the folders responsible.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later for local development
- A locally mounted Time Machine backup volume, or manually selected snapshot folders

The app does not modify, delete, restore, or write to backup content.

## Build

Open `TimeVault.xcodeproj` in Xcode and run the `TimeVault`
scheme. The project is configured to use the included `Time Machine
Analyzer.icon` asset and targets macOS 13.

For a command-line build:

```sh
xcodebuild \
  -project "TimeVault.xcodeproj" \
  -scheme "TimeVault" \
  -configuration Debug \
  -sdk macosx \
  build \
  CODE_SIGNING_ALLOWED=NO
```

To build the customized release DMG and signed automatic-update feed:

```sh
./Scripts/build-dmg.sh
```

See [`UPDATING.md`](UPDATING.md) for the complete GitHub release workflow.

To compile the unit-test target without running it:

```sh
xcodebuild \
  -project "TimeVault.xcodeproj" \
  -scheme "TimeVault" \
  -configuration Debug \
  -sdk macosx \
  build-for-testing \
  CODE_SIGNING_ALLOWED=NO
```

## Permissions

Select a mounted backup volume through the app so macOS can grant a
security-scoped read permission. Some backup locations also require Full Disk
Access in System Settings under Privacy & Security. The app verifies access and
reports failures without attempting to bypass macOS protections.

## Software updates

TimeVault uses Sparkle 2 for native automatic updates. It checks once per day
by default, can download and install signed updates automatically, and also
provides Check for Updates in the application menu and General settings.

## Time Machine support

The discovery layer supports the classic `Backups.backupdb` layout and local
APFS Time Machine paths exposed by the file system or `tmutil`. macOS does not
provide one public API that exposes every Time Machine implementation, so
discovery can be limited by permissions, encryption, volume state, or changes
in internal backup layout.

The app compares logical file metadata. Logical bytes are not a measurement of
physical space consumed on the backup disk because hard links, APFS clones,
compression, and deduplication can change physical storage usage.

## Testing

The test suite covers comparison classification, path normalization, symbolic
links, hard-link accounting, permission failures, snapshot timestamp parsing,
and scanner cancellation. Tests use local metadata and temporary fixture trees.

Run them from Xcode with the `TimeVaultTests` target, or use:

```sh
xcodebuild \
  -project "TimeVault.xcodeproj" \
  -scheme "TimeVault" \
  -configuration Debug \
  -sdk macosx \
  test \
  CODE_SIGNING_ALLOWED=NO
```

## License

TimeVault is released under the MIT License. See `LICENSE`.
