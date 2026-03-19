import XCTest
@testable import MacCleanerPro

final class ScannerServiceTests: XCTestCase {
    func testDuplicateDetectionFindsPairs() throws {
        let tmp = URL(fileURLWithPath: "/Users/tomasztarlowski/.openclaw/workspace/MacCleanerPro/tmp-tests", isDirectory: true)
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
        let tmp = URL(fileURLWithPath: "/Users/tomasztarlowski/.openclaw/workspace/MacCleanerPro/tmp-tests", isDirectory: true)
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
