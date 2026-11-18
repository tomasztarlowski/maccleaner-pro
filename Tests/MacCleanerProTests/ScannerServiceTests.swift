import XCTest
@testable import MacCleanerPro

final class ScannerServiceTests: XCTestCase {
    func testDuplicateDetectionFindsPairs() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let a = tmp.appendingPathComponent("a.bin")
        let b = tmp.appendingPathComponent("b.bin")
        let c = tmp.appendingPathComponent("c.bin")

        let payload = Data(repeating: 0xAB, count: 11 * 1024 * 1024)
        try payload.write(to: a)
        try payload.write(to: b)
        try Data(repeating: 0xCD, count: 11 * 1024 * 1024).write(to: c)

        let scanner = ScannerService()
        let large = scanner.scanLargeFiles(root: tmp, minSizeMB: 1)
        XCTAssertEqual(large.count, 3)

        let groups = scanner.scanDuplicates(root: tmp, minSizeMB: 10)
        XCTAssertEqual(groups.count, 1)
        guard let firstGroup = groups.first else { return XCTFail("Expected one duplicate group") }
        XCTAssertEqual(firstGroup.files.count, 2)
        let paths = Set(firstGroup.files.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        XCTAssertEqual(paths, Set(["a.bin", "b.bin"]))
    }

    func testLargeFilesRespectsThreshold() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let small = tmp.appendingPathComponent("small.dat")
        let big = tmp.appendingPathComponent("big.dat")

        try Data(repeating: 1, count: 2 * 1024 * 1024).write(to: small)
        try Data(repeating: 2, count: 7 * 1024 * 1024).write(to: big)

        let scanner = ScannerService()
        let files = scanner.scanLargeFiles(root: tmp, minSizeMB: 5)

        XCTAssertEqual(files.count, 1)
        guard let first = files.first else { return XCTFail("Expected one large file") }
        XCTAssertTrue(first.path.hasSuffix("big.dat"))
    }
}

extension ScannerServiceTests {
    func testLeftoversSkipInstalledBundleIDsAndUnclassifiedData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let apps = root.appendingPathComponent("Applications")
        let installed = apps.appendingPathComponent("Tools/Fixture.app/Contents")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "com.fixture.installed"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: installed.appendingPathComponent("Info.plist"))

        let candidates = [
            "com.fixture.installed",
            "com.fixture.installed.extension",
            "com.fixture.orphan",
            "com.apple.fixture",
            "Unclassified"
        ]
        for candidate in candidates {
            let directory = root.appendingPathComponent("Library/Application Support/\(candidate)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("fixture.bin"))
        }

        let results = ScannerService(home: root, applicationDirectories: [apps]).scanAppLeftovers()
        XCTAssertEqual(results.map(\.appName), ["com.fixture.orphan"])
        XCTAssertEqual(results.first?.totalSize, 1)
    }

    func testDeveloperScannerReportsNamedLocationsOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        for relativePath in [".npm/_cacache", "Library/Developer/Xcode/DerivedData", "Documents"] {
            let directory = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1, 2]).write(to: directory.appendingPathComponent("fixture.cache"))
        }

        let groups = ScannerService(home: root).scanDevJunk()
        XCTAssertEqual(Set(groups.map(\.category)), ["Node/npm caches", "Xcode DerivedData"])
        XCTAssertEqual(groups.reduce(0) { $0 + $1.totalSize }, 4)
    }

    func testTrashRejectsDirectoriesAndSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("keep.txt")
        let link = root.appendingPathComponent("link.txt")
        try Data([1]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let result = ScannerService().moveToTrash([root.path, link.path])
        XCTAssertEqual(result.failed, 2)
        XCTAssertTrue(result.removedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
