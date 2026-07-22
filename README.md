 # Time Machine Analyzer

Time Machine Analyzer is a read-only macOS app for comparing local Time Machine
backup snapshots. It reports added, removed, modified, and metadata-only items,
along with logical size changes and the folders responsible for those changes.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later for local development
- A locally mounted Time Machine backup volume, or manually selected snapshot folders

The app does not modify, delete, restore, or write to backup content.

## Build

Open `Time Machine Analyzer.xcodeproj` in Xcode and run the `Time Machine Analyzer`
scheme. The project is configured to use the included `Time Machine
Analyzer.icon` asset and targets macOS 13.

For a command-line build:

```sh
xcodebuild \
  -project "Time Machine Analyzer.xcodeproj" \
  -scheme "Time Machine Analyzer" \
  -configuration Debug \
  -sdk macosx \
  build \
  CODE_SIGNING_ALLOWED=NO
```

To compile the unit-test target without running it:

```sh
xcodebuild \
  -project "Time Machine Analyzer.xcodeproj" \
  -scheme "Time Machine Analyzer" \
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

Run them from Xcode with the `Time Machine Analyzer Tests` target, or use:

```sh
xcodebuild \
  -project "Time Machine Analyzer.xcodeproj" \
  -scheme "Time Machine Analyzer" \
  -configuration Debug \
  -sdk macosx \
  test \
  CODE_SIGNING_ALLOWED=NO
```

## License

Time Machine Analyzer is released under the MIT License. See `LICENSE`.
