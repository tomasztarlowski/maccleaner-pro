import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var language: AppLanguage = .polish
    @Published var scanPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published var scanProfile: ScanProfile = .standard {
        didSet { applyProfileDefaults() }
    }
    @Published var minLargeFileMB: Int = 800

    @Published var scanLargeFilesEnabled = true
    @Published var scanDuplicatesEnabled = true
    @Published var scanLeftoversEnabled = true
    @Published var scanDevJunkEnabled = true

    @Published var isScanning = false
    @Published private var scanStatus: ScanStatus = .ready

    private enum ScanStatus {
        case ready, scanning, complete, invalidFolder, noCategories
        case trashResult(moved: Int, failed: Int)
    }

    var status: String {
        switch scanStatus {
        case .ready: tr("Gotowy do skanowania", "Ready to scan")
        case .scanning: tr("Skanowanie…", "Scanning…")
        case .complete: tr("Skan zakończony", "Scan complete")
        case .invalidFolder: tr("Wybierz dostępny folder.", "Choose an accessible folder.")
        case .noCategories: tr("Wybierz kategorię w opcjach skanowania.", "Choose a category in Scan Options.")
        case let .trashResult(moved, failed):
            failed == 0
                ? tr("Przeniesiono do Kosza: \(moved)", "Moved to Trash: \(moved)")
                : tr("W Koszu: \(moved) · Nie przeniesiono: \(failed)", "Moved to Trash: \(moved) · Failed: \(failed)")
        }
    }

    @Published var largeFiles: [FileItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var leftoverGroups: [LeftoverGroup] = []
    @Published var devJunkGroups: [DevJunkGroup] = []
    @Published var history: [ScanSnapshot] = []

    @Published var selectedPaths = Set<String>()

    private let scanner: ScannerService
    private let historyURL: URL
    private var lastScan: (root: URL, profile: ScanProfile)?

    var hasScanResults: Bool { lastScan != nil }

    init(historyURL: URL? = nil, scanner: ScannerService = ScannerService()) {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacCleanerPro", isDirectory: true)
        self.historyURL = historyURL ?? appSupport.appendingPathComponent("scan-history.json")
        self.scanner = scanner
        loadHistory()
    }

    var totalSelectedSize: Int64 {
        guard !selectedPaths.isEmpty else { return 0 }
        let files = largeFiles
            + duplicateGroups.flatMap { $0.files }
            + leftoverGroups.flatMap { $0.files }
            + devJunkGroups.flatMap { $0.files }
        let byPath = Dictionary(
            files.lazy.filter { self.selectedPaths.contains($0.path) }.map { ($0.path, $0.size) },
            uniquingKeysWith: { first, _ in first }
        )
        return byPath.values.reduce(0, +)
    }

    func applyProfileDefaults() {
        minLargeFileMB = scanProfile.largeFileThresholdMB
    }

    @discardableResult
    func runFullScan() -> Task<Void, Never>? {
        guard !isScanning else { return nil }
        let path = scanPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: root.path) else {
            scanStatus = .invalidFolder
            return nil
        }

        let scanLarge = scanLargeFilesEnabled
        let scanCopies = scanDuplicatesEnabled
        let scanLeftovers = scanLeftoversEnabled
        let scanDev = scanDevJunkEnabled
        guard scanLarge || scanCopies || scanLeftovers || scanDev else {
            scanStatus = .noCategories
            return nil
        }

        let threshold = minLargeFileMB
        let profile = scanProfile
        let scanner = self.scanner
        isScanning = true
        scanStatus = .scanning
        selectedPaths.removeAll()

        return Task {
            let results = await Task.detached(priority: .userInitiated) {
                (
                    large: scanLarge ? scanner.scanLargeFiles(root: root, minSizeMB: threshold) : [],
                    copies: scanCopies ? scanner.scanDuplicates(root: root) : [],
                    leftovers: scanLeftovers ? scanner.scanAppLeftovers() : [],
                    developer: scanDev ? scanner.scanDevJunk() : []
                )
            }.value

            largeFiles = results.large
            duplicateGroups = results.copies
            leftoverGroups = results.leftovers
            devJunkGroups = results.developer
            lastScan = (root, profile)
            appendHistorySnapshot()
            scanStatus = .complete
            isScanning = false
        }
    }

    func toggle(_ path: String) {
        if selectedPaths.contains(path) { selectedPaths.remove(path) }
        else { selectedPaths.insert(path) }
    }

    func clearSelection() { selectedPaths.removeAll() }

    func selectRecommended() {
        selectedPaths = Set(duplicateGroups.flatMap { $0.files.dropFirst().map(\.path) })
    }

    @discardableResult
    func moveSelectedToTrash() -> Task<Void, Never>? {
        guard !isScanning, !selectedPaths.isEmpty else { return nil }
        let paths = selectedPaths.sorted()
        let scanner = self.scanner
        isScanning = true

        return Task {
            let result = await Task.detached(priority: .userInitiated) {
                scanner.moveToTrash(paths)
            }.value

            let removed = result.removedPaths
            largeFiles.removeAll { removed.contains($0.path) }
            duplicateGroups = duplicateGroups.compactMap { group in
                let remaining = group.files.filter { !removed.contains($0.path) }
                return remaining.count > 1 ? DuplicateGroup(hash: group.hash, files: remaining) : nil
            }
            leftoverGroups = leftoverGroups.compactMap { group in
                let remaining = group.files.filter { !removed.contains($0.path) }
                return remaining.isEmpty ? nil : LeftoverGroup(appName: group.appName, files: remaining)
            }
            devJunkGroups = devJunkGroups.compactMap { group in
                let remaining = group.files.filter { !removed.contains($0.path) }
                return remaining.isEmpty ? nil : DevJunkGroup(category: group.category, files: remaining)
            }
            selectedPaths.subtract(removed)
            scanStatus = .trashResult(moved: result.moved, failed: result.failed)
            isScanning = false
        }
    }

    func totalPotentialRecovery() -> Int64 {
        let dupWaste = duplicateGroups.reduce(0) { $0 + $1.totalWaste }
        let leftovers = leftoverGroups.reduce(0) { $0 + $1.totalSize }
        let devJunk = devJunkGroups.reduce(0) { $0 + $1.totalSize }
        return dupWaste + leftovers + devJunk
    }

    func reportText() -> String {
        let totalLarge = largeFiles.reduce(0) { $0 + $1.size }
        let dupWaste = duplicateGroups.reduce(0) { $0 + $1.totalWaste }
        let leftovers = leftoverGroups.reduce(0) { $0 + $1.totalSize }
        let devJunk = devJunkGroups.reduce(0) { $0 + $1.totalSize }

        let isPL = language == .polish
        return """
        MacCleaner Pro — \(isPL ? "Raport skanowania" : "Scan report")
        \(isPL ? "Data" : "Date"): \(Date())
        \(isPL ? "Folder" : "Folder"): \(lastScan?.root.path ?? scanPath)
        \(isPL ? "Profil" : "Profile"): \((lastScan?.profile ?? scanProfile).label(language))

        [\(isPL ? "Podsumowanie" : "Summary")]
        \(isPL ? "Duże pliki" : "Large files"): \(largeFiles.count) (\(totalLarge.formattedSize(language)))
        \(isPL ? "Duplikaty" : "Duplicates"): \(ScanCountUnit.group.label(duplicateGroups.count, language: language)) (\(isPL ? "potencjalny odzysk" : "potential recovery"): \(dupWaste.formattedSize(language)))
        \(isPL ? "Pozostałości" : "Leftovers"): \(ScanCountUnit.group.label(leftoverGroups.count, language: language)) (\(leftovers.formattedSize(language)))
        Dev Junk: \(ScanCountUnit.category.label(devJunkGroups.count, language: language)) (\(devJunk.formattedSize(language)))
        \(isPL ? "Zaznaczone" : "Selected"): \(selectedPaths.count) (\(totalSelectedSize.formattedSize(language)))
        \(isPL ? "Potencjalny odzysk" : "Potential recovery"): \(totalPotentialRecovery().formattedSize(language))

        [\(isPL ? "Top 20 dużych plików" : "Top 20 large files")]
        \(largeFiles.prefix(20).map { "- \($0.size.formattedSize(language))  \($0.path)" }.joined(separator: "\n"))
        """
    }

    func saveReport(to url: URL) throws {
        try reportText().write(to: url, atomically: true, encoding: .utf8)
    }

    private func appendHistorySnapshot() {
        let snapshot = ScanSnapshot(
            largeFilesCount: largeFiles.count,
            duplicateGroupsCount: duplicateGroups.count,
            leftoversCount: leftoverGroups.count,
            devJunkGroupsCount: devJunkGroups.count,
            largeFilesSize: largeFiles.reduce(0) { $0 + $1.size },
            duplicateWaste: duplicateGroups.reduce(0) { $0 + $1.totalWaste },
            leftoversSize: leftoverGroups.reduce(0) { $0 + $1.totalSize },
            devJunkSize: devJunkGroups.reduce(0) { $0 + $1.totalSize }
        )
        history.insert(snapshot, at: 0)
        history = Array(history.prefix(30))
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    private func tr(_ polish: String, _ english: String) -> String {
        language == .polish ? polish : english
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else { return }
        history = decoded
    }
}
