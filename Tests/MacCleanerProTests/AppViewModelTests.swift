import XCTest
@testable import MacCleanerPro

final class AppViewModelTests: XCTestCase {
    func testSelectionCountsAFileInMultipleCategoriesOnlyOnce() async {
        await MainActor.run {
            let model = AppViewModel()
            let original = FileItem(path: "/fixture/original", size: 1_500_000_000)
            let duplicate = FileItem(path: "/fixture/duplicate", size: 1_500_000_000)
            model.largeFiles = [original, duplicate]
            model.duplicateGroups = [DuplicateGroup(hash: "fixture", files: [original, duplicate])]
            model.selectedPaths = [duplicate.path]

            XCTAssertEqual(model.totalSelectedSize, duplicate.size)
        }
    }

    func testRecommendedSelectionKeepsOneCopyAndIgnoresOtherCategories() async {
        await MainActor.run {
            let model = AppViewModel()
            let original = FileItem(path: "/fixture/original", size: 1_500_000_000)
            let duplicate = FileItem(path: "/fixture/duplicate", size: original.size)
            let large = FileItem(path: "/fixture/large", size: 2_000_000_000)
            let leftover = FileItem(path: "/fixture/leftover", size: 100_000_000)
            let cache = FileItem(path: "/fixture/cache", size: 100_000_000)
            model.largeFiles = [large, original, duplicate]
            model.duplicateGroups = [DuplicateGroup(hash: "fixture", files: [original, duplicate])]
            model.leftoverGroups = [LeftoverGroup(appName: "Fixture", files: [leftover])]
            model.devJunkGroups = [DevJunkGroup(category: "Fixture", files: [cache])]

            model.selectRecommended()

            XCTAssertEqual(model.selectedPaths, [duplicate.path])
        }
    }
}

extension AppViewModelTests {
    @MainActor
    func testScanPersistsHistoryAndExportsActualScanScope() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let historyURL = root.appendingPathComponent("history.json")
        let reportURL = root.appendingPathComponent("report.txt")
        let payload = Data(repeating: 0x31, count: 11 * 1024 * 1024)
        try payload.write(to: root.appendingPathComponent("original.bin"))
        try payload.write(to: root.appendingPathComponent("copy.bin"))

        let model = AppViewModel(historyURL: historyURL)
        model.language = .english
        model.scanPath = root.path
        model.minLargeFileMB = 5
        model.scanLeftoversEnabled = false
        model.scanDevJunkEnabled = false

        let scan = try XCTUnwrap(model.runFullScan())
        XCTAssertNil(model.runFullScan())
        await scan.value

        XCTAssertTrue(model.hasScanResults)
        XCTAssertEqual(model.largeFiles.count, 2)
        XCTAssertEqual(model.duplicateGroups.count, 1)
        XCTAssertEqual(model.history.count, 1)
        XCTAssertEqual(AppViewModel(historyURL: historyURL).history.first?.duplicateGroupsCount, 1)

        model.scanPath = "/unscanned"
        model.scanProfile = .aggressive
        try model.saveReport(to: reportURL)
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("Folder: \(root.path)"))
        XCTAssertTrue(report.contains("Profile: Standard"))
        XCTAssertTrue(report.contains("Duplicates: 1"))
        XCTAssertFalse(report.contains("/unscanned"))
    }

    @MainActor
    func testInvalidFolderAndEmptyCategorySelectionDoNotRecordScan() {
        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppViewModel(historyURL: historyURL)
        model.language = .english
        model.scanPath = " "
        XCTAssertNil(model.runFullScan())
        XCTAssertEqual(model.status, "Choose an accessible folder.")

        model.scanPath = FileManager.default.temporaryDirectory.path
        model.scanLargeFilesEnabled = false
        model.scanDuplicatesEnabled = false
        model.scanLeftoversEnabled = false
        model.scanDevJunkEnabled = false
        XCTAssertNil(model.runFullScan())
        XCTAssertEqual(model.status, "Choose a category in Scan Options.")
        XCTAssertTrue(model.history.isEmpty)
    }
}
