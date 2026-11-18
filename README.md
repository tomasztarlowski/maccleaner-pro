# MacCleaner Pro

A native macOS disk scanner for finding large files, duplicate copies, possible app leftovers, and developer data. Scans run locally. You choose what moves to the Trash.

[![CI](https://github.com/tomasztarlowski/maccleaner-pro/actions/workflows/ci.yml/badge.svg)](https://github.com/tomasztarlowski/maccleaner-pro/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it scans

| Category | Scope |
| --- | --- |
| Large files | Regular files in the selected folder above the threshold set by the scan profile |
| Duplicates | Files in the selected folder with matching size and SHA-256 checksum. Automatic selection leaves one copy in each group |
| App leftovers | Possible matches in your Library that resemble bundle identifiers and do not match an app found in the standard Applications folders |
| Developer data | Known locations for Xcode, simulators, Docker, and package caches in your home folder |

The interface is available in English and Polish. Use **Options** to choose categories, then review the results by category or filter by path. The app keeps up to 30 scan summaries and exports a plain-text report.

Developer data can include active Docker volumes or simulator data. Review those files and possible app leftovers before cleanup. Reports can include full local paths. The size shown for selected files is their logical size. Actual space reclaimed can differ, especially with hard links or snapshots.

## Download and build

The [Releases page](https://github.com/tomasztarlowski/maccleaner-pro/releases) contains prebuilt downloads. The published v3.0.0 DMG is Apple Silicon only. To try the current source, build and open a local app on macOS 13 or later with a Swift 5.10 or newer toolchain.

```sh
swift test
bash build_app.sh
open "dist/MacCleaner Pro.app"
```

The build creates an app and DMG for the build machine's architecture. It uses an ad hoc signature and is not notarized. Some locations may be unreadable under macOS privacy restrictions. The duplicate scan skips files smaller than 10 MB or larger than 2 GiB and caps the candidate list.

See the [changelog](CHANGELOG.md) for release details. Created by Tomek and Jarvis and distributed under the [MIT License](LICENSE).
