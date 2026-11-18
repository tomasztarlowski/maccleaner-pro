# Changelog

## 3.1.0

- Redesigned the macOS interface with native navigation, folder selection, scan options, searchable results, and a persistent selection bar.
- Added English and Polish labels throughout the updated interface.
- Fixed a crash when the same file appeared in multiple categories. The selected size counts each path once.
- Limited automatic selection to extra copies in duplicate groups. Moving files to the Trash requires confirmation and reports partial failures.
- Narrowed the app-leftover scan to bundle-like identifiers and excluded apps found in standard Applications folders.
- Validated folder paths before scanning and kept exported reports tied to the last completed scan.
- Made scanner tests portable and added coverage for scan history, report export, developer data, and cleanup safeguards.
- Updated the app bundle version and signed the local build ad hoc before DMG packaging.

## 3.0.0

- Initial public release with large-file, duplicate, and app-leftover scanning.
- Added a SwiftUI interface and cleanup through the macOS Trash.
