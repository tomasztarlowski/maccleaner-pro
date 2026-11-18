import Foundation
import CryptoKit
import Darwin

final class ScannerService {
    private let fileManager = FileManager.default
    private let home: URL
    private let applicationDirectories: [URL]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, applicationDirectories: [URL]? = nil) {
        self.home = home
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }
    private let excludedPrefixes: [String] = [
        "/System", "/private", "/usr", "/bin", "/sbin", "/opt/homebrew/Cellar"
    ]

    // Safety limits to prevent OOM / huge stalls on duplicate scan
    private let duplicateCandidateLimit = 80_000
    private let maxDuplicateHashFileSizeBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB
    private let maxFilesPerDevCategory = 25_000

    func scanLargeFiles(root: URL, minSizeMB: Int) -> [FileItem] {
        let minBytes = Int64(minSizeMB) * 1024 * 1024
        var result: [FileItem] = []

        enumerateFiles(root: root) { url in
            guard let size = fileSize(url), size >= minBytes else { return true }
            result.append(FileItem(path: url.path, size: size))
            return true
        }

        return result.sorted { $0.size > $1.size }
    }

    /// Group candidates by size, then compare full SHA-256 hashes.
    func scanDuplicates(root: URL, minSizeMB: Int = 10) -> [DuplicateGroup] {
        let minBytes = Int64(minSizeMB) * 1024 * 1024

        // Phase 1: avoid storing all unique files in memory
        var sizeCount: [Int64: Int] = [:]
        var firstBySize: [Int64: URL] = [:]
        var duplicateCandidatesBySize: [Int64: [URL]] = [:]
        var candidateCount = 0

        enumerateFiles(root: root) { url in
            guard let size = fileSize(url), size >= minBytes else { return true }
            guard size <= maxDuplicateHashFileSizeBytes else { return true } // skip huge files for stability

            let count = sizeCount[size, default: 0]
            if count == 0 {
                sizeCount[size] = 1
                firstBySize[size] = url
            } else if count == 1 {
                sizeCount[size] = 2
                if let first = firstBySize[size] {
                    duplicateCandidatesBySize[size] = [first, url]
                    candidateCount += 2
                }
            } else {
                sizeCount[size] = count + 1
                duplicateCandidatesBySize[size, default: []].append(url)
                candidateCount += 1
            }

            // hard cap to prevent pathological memory usage
            if candidateCount > duplicateCandidateLimit {
                return false
            }
            return true
        }

        var groups: [DuplicateGroup] = []

        for (_, urls) in duplicateCandidatesBySize {
            guard urls.count > 1 else { continue }

            // Full hash only for repeated-size candidates.
            var byFullHash: [String: [URL]] = [:]
            for url in urls {
                if let fh = fullFileHash(url) {
                    byFullHash[fh, default: []].append(url)
                }
            }

            for (hash, sameFiles) in byFullHash where sameFiles.count > 1 {
                let fileItems = sameFiles.compactMap { u -> FileItem? in
                    guard let s = fileSize(u) else { return nil }
                    return FileItem(path: u.path, size: s)
                }
                guard fileItems.count > 1 else { continue }
                groups.append(
                    DuplicateGroup(
                        hash: "\(hash.prefix(12))…",
                        files: fileItems.sorted { $0.path < $1.path }
                    )
                )
            }
        }

        return groups.sorted { $0.totalWaste > $1.totalWaste }
    }

    func scanAppLeftovers() -> [LeftoverGroup] {
        let installedIDs = installedBundleIdentifiers()

        let roots: [URL] = [
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Preferences"),
            home.appendingPathComponent("Library/Logs"),
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers")
        ]

        var buckets: [String: [FileItem]] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            let root = canonicalDirectory(root)
            let rootDepth = root.pathComponents.count
            enumerateFiles(root: root) { url in
                guard let component = url.pathComponents.dropFirst(rootDepth).first else { return true }
                let bundleID = component.hasSuffix(".plist") ? String(component.dropLast(6)) : component
                let normalized = bundleID.lowercased()
                let labels = normalized.split(separator: ".")
                guard labels.count >= 3, !normalized.hasPrefix("com.apple."),
                      labels.allSatisfy({ label in label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }),
                      !installedIDs.contains(normalized),
                      !installedIDs.contains(where: { normalized.hasPrefix($0 + ".") }),
                      let size = fileSize(url), size > 0 else { return true }

                buckets[bundleID, default: []].append(FileItem(path: url.path, size: size))
                return true
            }
        }

        return buckets.map { key, files in
            LeftoverGroup(appName: key, files: files.sorted { $0.size > $1.size })
        }
        .filter { !$0.files.isEmpty }
        .sorted { $0.totalSize > $1.totalSize }
    }

    func scanDevJunk() -> [DevJunkGroup] {
        let homePath = home.path

        let targets: [(String, [String])] = [
            ("Docker", ["\(homePath)/Library/Containers/com.docker.docker/Data/vms/0/data"]),
            ("Xcode DerivedData", ["\(homePath)/Library/Developer/Xcode/DerivedData"]),
            ("iOS Simulators", ["\(homePath)/Library/Developer/CoreSimulator/Devices"]),
            ("Node/npm caches", ["\(homePath)/.npm", "\(homePath)/.pnpm-store", "\(homePath)/Library/Caches/Yarn"]),
            ("Python caches", ["\(homePath)/Library/Caches/pip", "\(homePath)/.cache/pip"]),
            ("Rust/Go build cache", ["\(homePath)/.cargo/registry", "\(homePath)/.cargo/git", "\(homePath)/go/pkg/mod/cache"])
        ]

        return targets.compactMap { (name, paths) in
            var files: [FileItem] = []
            for p in paths {
                let url = URL(fileURLWithPath: p)
                guard fileManager.fileExists(atPath: url.path) else { continue }
                if let size = fileSize(url), (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    files.append(FileItem(path: url.path, size: size))
                } else {
                    enumerateFiles(root: url) { fileURL in
                        guard let size = fileSize(fileURL), size > 0 else { return true }
                        files.append(FileItem(path: fileURL.path, size: size))
                        return files.count < maxFilesPerDevCategory
                    }
                }
            }
            guard !files.isEmpty else { return nil }
            return DevJunkGroup(category: name, files: files.sorted { $0.size > $1.size })
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    struct TrashResult {
        var removedPaths: Set<String> = []
        var moved = 0
        var failed = 0
    }

    func moveToTrash(_ paths: [String]) -> TrashResult {
        var result = TrashResult()
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    result.failed += 1
                    continue
                }
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                result.removedPaths.insert(path)
                result.moved += 1
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                result.removedPaths.insert(path)
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    private func installedBundleIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        for directory in applicationDirectories {
            guard let apps = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in apps {
                guard url.pathExtension.lowercased() == "app",
                      let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
                identifiers.insert(bundleID.lowercased())
            }
        }
        return identifiers
    }

    private func enumerateFiles(root: URL, handle: (URL) -> Bool) {
        let root = canonicalDirectory(root)
        let rootPath = root.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            // Skip protected system trees unless user explicitly scans inside them.
            let shouldSkipByPrefix = excludedPrefixes.contains { prefix in
                (url.path == prefix || url.path.hasPrefix(prefix + "/"))
                    && rootPath != prefix && !rootPath.hasPrefix(prefix + "/")
            }
            if shouldSkipByPrefix {
                enumerator.skipDescendants()
                continue
            }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if handle(url) == false { break }
        }
    }

    private func canonicalDirectory(_ url: URL) -> URL {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return url.standardizedFileURL }
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        }
    }

    private func fileSize(_ url: URL) -> Int64? {
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let s = attrs[.size] as? NSNumber {
            return s.int64Value
        }
        return nil
    }

    private func fullFileHash(_ url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: read))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
