import Foundation
import CryptoKit

final class ScannerService {
    private let fileManager = FileManager.default
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

    /// Robust duplicate scan in three phases:
    /// 1) Group by size (but keep only repeated-size candidates)
    /// 2) Quick hash (first+last chunks)
    /// 3) Full SHA256 only for quick-hash collisions
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
        let installedApps = installedAppNames()
        let home = fileManager.homeDirectoryForCurrentUser

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
            enumerateFiles(root: root) { url in
                let parts = url.pathComponents
                guard let marker = parts.first(where: { $0.lowercased().contains("com.") || $0.lowercased().contains("org.") }) else {
                    let key = parts.dropFirst(parts.firstIndex(of: "Library") ?? 0).dropFirst().first ?? "Unknown"
                    self.addLeftoverCandidate(key: key, url: url, installedApps: installedApps, buckets: &buckets)
                    return true
                }
                self.addLeftoverCandidate(key: marker, url: url, installedApps: installedApps, buckets: &buckets)
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
        let home = fileManager.homeDirectoryForCurrentUser.path

        let targets: [(String, [String])] = [
            ("Docker", ["\(home)/Library/Containers/com.docker.docker/Data/vms/0/data"]),
            ("Xcode DerivedData", ["\(home)/Library/Developer/Xcode/DerivedData"]),
            ("iOS Simulators", ["\(home)/Library/Developer/CoreSimulator/Devices"]),
            ("Node/npm caches", ["\(home)/.npm", "\(home)/.pnpm-store", "\(home)/Library/Caches/Yarn"]),
            ("Python caches", ["\(home)/Library/Caches/pip", "\(home)/.cache/pip"]),
            ("Rust/Go build cache", ["\(home)/.cargo/registry", "\(home)/.cargo/git", "\(home)/go/pkg/mod/cache"])
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

    func moveToTrash(_ paths: [String]) throws {
        for p in paths {
            let url = URL(fileURLWithPath: p)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            _ = try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    // MARK: - Helpers

    private func addLeftoverCandidate(
        key: String,
        url: URL,
        installedApps: Set<String>,
        buckets: inout [String: [FileItem]]
    ) {
        guard let size = fileSize(url), size > 0 else { return }
        let normalized = key
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "org.", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if installedApps.contains(where: { normalized.contains($0) || $0.contains(normalized) }) {
            return
        }

        buckets[key, default: []].append(FileItem(path: url.path, size: size))
    }

    private func installedAppNames() -> Set<String> {
        let appDirs = ["/Applications", fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        var names: Set<String> = []

        for dir in appDirs {
            guard let items = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for app in items where app.hasSuffix(".app") {
                let clean = app.replacingOccurrences(of: ".app", with: "").lowercased()
                names.insert(clean)
            }
        }
        return names
    }

    private func enumerateFiles(root: URL, handle: (URL) -> Bool) {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            // Skip protected system trees unless user explicitly scans inside them.
            let shouldSkipByPrefix = excludedPrefixes.contains { prefix in
                url.path.hasPrefix(prefix) && !rootPath.hasPrefix(prefix)
            }
            if shouldSkipByPrefix { continue }

            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if handle(url) == false { break }
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
