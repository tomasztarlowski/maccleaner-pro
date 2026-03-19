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
    @Published var recommendedLargeFileMB: Int = 1200

    @Published var scanLargeFilesEnabled = true
    @Published var scanDuplicatesEnabled = true
    @Published var scanLeftoversEnabled = true
    @Published var scanDevJunkEnabled = true

    @Published var isScanning = false
    @Published var status = "Gotowy"

    @Published var largeFiles: [FileItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var leftoverGroups: [LeftoverGroup] = []
    @Published var devJunkGroups: [DevJunkGroup] = []
    @Published var history: [ScanSnapshot] = []

    @Published var selectedPaths = Set<String>()

    private let scanner = ScannerService()
    private let historyURL: URL

    init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacCleanerPro", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.historyURL = appSupport.appendingPathComponent("scan-history.json")
        loadHistory()
    }

    var totalSelectedSize: Int64 {
        let byPath = Dictionary(uniqueKeysWithValues:
            (largeFiles + duplicateGroups.flatMap { $0.files } + leftoverGroups.flatMap { $0.files } + devJunkGroups.flatMap { $0.files }).map { ($0.path, $0.size) }
        )
        return selectedPaths.reduce(0) { $0 + (byPath[$1] ?? 0) }
    }

    var cleanupHealthScore: Int {
        let recoveryGB = Double(totalPotentialRecovery()) / 1_073_741_824
        let score = max(0, 100 - Int(recoveryGB * 6.0))
        return min(score, 100)
    }

    func applyProfileDefaults() {
        minLargeFileMB = scanProfile.largeFileThresholdMB
        recommendedLargeFileMB = scanProfile.recommendationThresholdMB
    }

    func runFullScan() {
        isScanning = true
        status = "Skanowanie…"
        selectedPaths.removeAll()

        let root = URL(fileURLWithPath: scanPath)
        let minMB = minLargeFileMB
        let scanner = self.scanner

        Task {
            if self.scanLargeFilesEnabled {
                let large = await Task.detached { scanner.scanLargeFiles(root: root, minSizeMB: minMB) }.value
                await MainActor.run {
                    self.largeFiles = large
                    self.status = "Duże pliki: \(large.count)."
                }
            } else {
                await MainActor.run { self.largeFiles = [] }
            }

            if self.scanDuplicatesEnabled {
                let dupes = await Task.detached { scanner.scanDuplicates(root: root) }.value
                await MainActor.run {
                    self.duplicateGroups = dupes
                    self.status = "Duplikaty: \(dupes.count) grup."
                }
            } else {
                await MainActor.run { self.duplicateGroups = [] }
            }

            if self.scanLeftoversEnabled {
                let leftovers = await Task.detached { scanner.scanAppLeftovers() }.value
                await MainActor.run {
                    self.leftoverGroups = leftovers
                }
            } else {
                await MainActor.run { self.leftoverGroups = [] }
            }

            if self.scanDevJunkEnabled {
                let devJunk = await Task.detached { scanner.scanDevJunk() }.value
                await MainActor.run {
                    self.devJunkGroups = devJunk
                }
            } else {
                await MainActor.run { self.devJunkGroups = [] }
            }

            await MainActor.run {
                self.appendHistorySnapshot()
                self.status = "Gotowe ✅"
                self.isScanning = false
            }
        }
    }

    func toggle(_ path: String) {
        if selectedPaths.contains(path) { selectedPaths.remove(path) }
        else { selectedPaths.insert(path) }
    }

    func clearSelection() { selectedPaths.removeAll() }

    func selectRecommended() {
        var picks = Set<String>()

        for group in duplicateGroups {
            for file in group.files.dropFirst() { picks.insert(file.path) }
        }

        let threshold = Int64(recommendedLargeFileMB) * 1024 * 1024
        for file in largeFiles where file.size >= threshold { picks.insert(file.path) }

        let leftoverThreshold: Int64 = 50 * 1024 * 1024
        for file in leftoverGroups.flatMap({ $0.files }) where file.size >= leftoverThreshold { picks.insert(file.path) }

        for group in devJunkGroups.prefix(2) {
            for file in group.files.prefix(20) { picks.insert(file.path) }
        }

        selectedPaths = picks
        status = "Zaznaczono rekomendowane: \(selectedPaths.count)"
    }

    func moveSelectedToTrash() {
        guard !selectedPaths.isEmpty else { return }
        do {
            try scanner.moveToTrash(Array(selectedPaths))
            status = "Przeniesiono do Kosza: \(selectedPaths.count)"
            runFullScan()
        } catch {
            status = "Błąd kosza: \(error.localizedDescription)"
        }
    }

    func removeLeftoverGroup(_ group: LeftoverGroup) {
        do {
            try scanner.moveToTrash(group.files.map { $0.path })
            status = "Usunięto pozostałości: \(group.appName)"
            runFullScan()
        } catch {
            status = "Błąd usuwania grupy: \(error.localizedDescription)"
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
        \(isPL ? "Folder" : "Folder"): \(scanPath)
        \(isPL ? "Profil" : "Profile"): \(scanProfile.label(language))

        [\(isPL ? "Podsumowanie" : "Summary")]
        \(isPL ? "Duże pliki" : "Large files"): \(largeFiles.count) (\(totalLarge.humanSize))
        \(isPL ? "Duplikaty" : "Duplicates"): \(duplicateGroups.count) \(isPL ? "grup" : "groups") (\(isPL ? "potencjalny odzysk" : "potential recovery"): \(dupWaste.humanSize))
        \(isPL ? "Pozostałości" : "Leftovers"): \(leftoverGroups.count) \(isPL ? "grup" : "groups") (\(leftovers.humanSize))
        Dev Junk: \(devJunkGroups.count) \(isPL ? "grup" : "groups") (\(devJunk.humanSize))
        \(isPL ? "Zaznaczone" : "Selected"): \(selectedPaths.count) (\(totalSelectedSize.humanSize))
        \(isPL ? "Potencjalny odzysk" : "Potential recovery"): \(totalPotentialRecovery().humanSize)

        [\(isPL ? "Top 20 dużych plików" : "Top 20 large files")]
        \(largeFiles.prefix(20).map { "- \($0.size.humanSize)  \($0.path)" }.joined(separator: "\n"))
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
        try? data.write(to: historyURL)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ScanSnapshot].self, from: data) else { return }
        history = decoded
    }
}
