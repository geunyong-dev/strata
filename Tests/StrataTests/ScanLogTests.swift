import XCTest
@testable import Strata

final class ScanLogTests: XCTestCase {
    func testLogsBothCapacityValuesWithoutChangingDisplayBasis() throws {
        let volume = VolumeUsage(totalBytes: 1000, availableBytes: 300, physicalAvailableBytes: 200,
                                 importantAvailableBytes: 300)
        let fields = ScanLog.capacityFields(volume)
        XCTAssertEqual(fields["ordinaryAvailableBytes"] as? Int64, 200)
        XCTAssertEqual(fields["importantAvailableBytes"] as? Int64, 300)
        XCTAssertEqual(fields["displayBasis"] as? String, "ordinary-free")
        XCTAssertEqual(volume.usedBytes, 800)
        let missing = ScanLog.capacityFields(VolumeUsage(totalBytes: 1000, availableBytes: 0))
        XCTAssertTrue(missing["ordinaryAvailableBytes"] is NSNull)
        XCTAssertTrue(missing["importantAvailableBytes"] is NSNull)
        XCTAssertEqual(missing["displayBasis"] as? String, "important-usage-fallback")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: missing))
    }

    func testLifecycleErrorsAndEventLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ScanLog(directory: directory, eventLimit: 3)
        ScanLogContext.$current.withValue(log) {
            ScanLogContext.posix(path: "/fixture/denied", operation: "lstat", code: 13)
        }
        log.write("test")
        log.write("omitted")
        log.finish(status: "cancelled")
        XCTAssertNil(log.warning)
        let rows = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[1]["domain"] as? String, NSPOSIXErrorDomain)
        XCTAssertEqual(rows[1]["code"] as? Int, 13)
        XCTAssertEqual(rows.last?["status"] as? String, "cancelled")
        XCTAssertEqual(rows.last?["omittedEvents"] as? Int, 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: log.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testWriteFailureIsVisibleAndSeparateScansHaveUniqueFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ScanLog(directory: directory)
        let second = ScanLog(directory: directory)
        XCTAssertNotEqual(first.url, second.url)
        first.finish(status: "completed")
        second.finish(status: "failed")
        let failed = ScanLog(directory: first.url)
        XCTAssertNotNil(failed.warning)
    }
}
