import XCTest
import Darwin
@testable import Strata

final class TrashAnalyzerTests: XCTestCase {
    func testTrashIsExcludedFromParentAndCountedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let trash = root.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16_384).write(to: trash.appending(path: "deleted"))
        try Data(repeating: 2, count: 8_192).write(to: root.appending(path: "kept"))
        let scanner = FileSystemScanner()
        let all = scanner.measure(urls: [root])
        let users = scanner.measure(urls: [root], excludedURLs: TrashAnalyzer.exclusions(for: trash, dataRoot: root))
        let separate = TrashAnalyzer().measure(at: trash, expectedDevice: scanner.deviceID(for: root))
        XCTAssertGreaterThan(separate.allocatedBytes, 0)
        XCTAssertEqual(users.allocatedBytes + separate.allocatedBytes, all.allocatedBytes)
        XCTAssertEqual(separate.inaccessibleItemCount, 0)
        XCTAssertTrue(separate.isTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appending(path: "deleted").path))
    }

    func testMissingAndEmptyTrashAreKnownZero() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let trash = root.appending(path: ".Trash")
        let device = FileSystemScanner().deviceID(for: root)
        let missing = TrashAnalyzer().measure(at: trash, expectedDevice: device)
        XCTAssertEqual(missing.capacityText, "0 KB")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let empty = TrashAnalyzer().measure(at: trash, expectedDevice: device)
        XCTAssertEqual(empty.capacityText, "0 KB")
        XCTAssertEqual(empty.inaccessibleItemCount, 0)
    }

    func testDeniedTrashIsNotReportedAsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let trash = root.appending(path: ".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer {
            _ = trash.path.withCString { chmod($0, 0o700) }
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(trash.path.withCString { chmod($0, 0) }, 0)
        guard geteuid() != 0 else { throw XCTSkip("Root bypasses directory permissions") }
        let result = TrashAnalyzer().measure(at: trash, expectedDevice: FileSystemScanner().deviceID(for: root))
        XCTAssertEqual(result.capacityText, "측정 불가")
        XCTAssertGreaterThan(result.inaccessibleItemCount, 0)
    }

    func testDataVolumeAliasIsExcludedAndSymlinkIsNotFollowed() throws {
        let aliases = TrashAnalyzer.exclusions(for: URL(fileURLWithPath: "/Users/example/.Trash"),
            dataRoot: URL(fileURLWithPath: "/System/Volumes/Data")).map(\.path)
        XCTAssertEqual(aliases, ["/Users/example/.Trash", "/System/Volumes/Data/Users/example/.Trash"])
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let trash = root.appending(path: ".Trash")
        try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: root)
        let report = TrashAnalyzer().measure(at: trash, expectedDevice: FileSystemScanner().deviceID(for: root))
        XCTAssertEqual(report.capacityText, "측정 불가")
    }

    func testSmallTrashIsPinnedAndPartialMeasurementIsExplicit() {
        var trash = VolumeAreaUsage(name: "휴지통", path: "/Users/example/.Trash", symbol: "trash", allocatedBytes: 1,
            inaccessibleItemCount: 0, inaccessiblePaths: [], isTrash: true)
        let others = (1...9).map { VolumeAreaUsage(name: "영역 \($0)", path: "/area\($0)", symbol: "folder", allocatedBytes: 10,
            inaccessibleItemCount: 0, inaccessiblePaths: []) }
        let breakdown = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 200, availableBytes: 20), areas: others + [trash])
        XCTAssertEqual(breakdown.bands.first { $0.id == trash.path }?.bytes, 1)
        XCTAssertFalse(breakdown.bands.first { $0.kind == .grouped }!.areas.contains { $0.isTrash })
        XCTAssertEqual(breakdown.bands.reduce(0) { $0 + $1.bytes }, 200)
        XCTAssertLessThanOrEqual(breakdown.bands.count, 7)
        trash = VolumeAreaUsage(name: "휴지통", path: trash.path, symbol: "trash", allocatedBytes: 1000,
            inaccessibleItemCount: 1, inaccessiblePaths: [], isTrash: true)
        XCTAssertTrue(trash.capacityText.contains("일부 측정"))
    }
}
