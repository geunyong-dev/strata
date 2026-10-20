import XCTest
import Darwin
import ReadOnlyScanCore
@testable import Strata

final class AdministratorScanTests: XCTestCase {
    private func area(_ bytes: Int64 = 100, errors: Int = 2) -> VolumeAreaUsage {
        .init(name: "Library", path: "/Library", symbol: "folder", allocatedBytes: bytes,
              inaccessibleItemCount: errors, inaccessiblePaths: ["/Library/blocked"])
    }
    private func result(_ bytes: Int64 = 150, errors: Int = 1, complete: Bool = true) -> ReadOnlyMeasurement {
        .init(path: "/System/Volumes/Data/Library", bytes: bytes,
              unreadablePaths: errors > 0 ? ["/System/Volumes/Data/Library/blocked"] : [],
              unreadableCount: errors, visited: 10, complete: complete)
    }
    private func encoded(_ response: ReadOnlyScanResponse) throws -> String {
        String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    }

    func testReplaceAreaInsteadOfAddingToItAndLeaveUserTrashUntouched() {
        let user = VolumeAreaUsage(name: "Users", path: "/Users", symbol: "folder", allocatedBytes: 200,
                                  inaccessibleItemCount: 0, inaccessiblePaths: [])
        let trash = VolumeAreaUsage(name: "Trash", path: "/Users/test/.Trash", symbol: "trash", allocatedBytes: 50,
                                   inaccessibleItemCount: 0, inaccessiblePaths: [], isTrash: true)
        let (areas, report) = AdministratorScan.merge([area(), user, trash],
            response: .init(effectiveUID: 0, results: [result()]))
        XCTAssertEqual(areas.map(\.allocatedBytes), [150, 200, 50])
        XCTAssertEqual(report.additionalBytes, 50)
        XCTAssertEqual(report.improvedAreas, 1)
        XCTAssertTrue(areas[2].isTrash)
        XCTAssertEqual(areas[0].inaccessibleItemCount, 1)
    }

    func testIncompleteAndSmallerMeasurementsPreserveOrdinaryResults() {
        for result in [result(500, complete: false), result(90), result(100, errors: 3)] {
            let (areas, report) = AdministratorScan.merge([area()], response: .init(effectiveUID: 0, results: [result]))
            XCTAssertEqual(areas[0].allocatedBytes, 100)
            XCTAssertEqual(areas[0].inaccessibleItemCount, 2)
            XCTAssertEqual(report.additionalBytes, 0)
            XCTAssertEqual(report.status, .partial)
        }
    }

    func testEqualBytesWithFewerErrorsIsAnImprovement() {
        let (areas, report) = AdministratorScan.merge([area()], response: .init(effectiveUID: 0, results: [result(100, errors: 0)]))
        XCTAssertEqual(areas[0].inaccessibleItemCount, 0)
        XCTAssertEqual(report.improvedAreas, 1)
        XCTAssertEqual(report.additionalBytes, 0)
    }

    func testProtocolRejectsInvalidUnprivilegedAndUnscopedResponses() throws {
        XCTAssertNotNil(AdministratorScan.decode(try encoded(.init(effectiveUID: 0, results: [result()]))))
        for response in [
            ReadOnlyScanResponse(effectiveUID: 501, results: [result()]),
            .init(version: 2, effectiveUID: 0, results: [result()]),
            .init(effectiveUID: 0, results: []),
            .init(effectiveUID: 0, results: [result(), result()]),
            .init(effectiveUID: 0, results: [result(-1)]),
            .init(effectiveUID: 0, results: [.init(path: "/Users", bytes: 20, unreadablePaths: [], unreadableCount: 0, visited: 1, complete: true)])
        ] { XCTAssertNil(AdministratorScan.decode(try encoded(response))) }
        XCTAssertNil(AdministratorScan.decode("unfinished output"))
    }

    func testAuthorizationArgumentsAreFixedAndShellQuoted() {
        let args = AdministratorScan.arguments(helper: "/Applications/Test's \"quoted\" $HOME.app/Contents/Helpers/StrataReadOnlyScanner", leaseID: "ID")
        XCTAssertEqual(args.count, 6)
        XCTAssertTrue(args[3].contains("with administrator privileges"))
        XCTAssertTrue(args[3].contains("env -i PATH="))
        XCTAssertTrue(args[3].contains("'\\\\''"))
        XCTAssertFalse(args[3].contains("sudo"))
    }

    func testMissingHelperNeverRequestsAuthorization() {
        let scanner = AdministratorScan(run: { _, _, _ in XCTFail("Must not launch commands"); return .init(standardOutput: "", standardError: "", exitCode: -1, timedOut: false) })
        let (areas, report) = scanner.refine([area()], bundle: Bundle(for: Self.self))
        XCTAssertEqual(areas[0].allocatedBytes, 100)
        XCTAssertEqual(report.status, .unavailable)
    }

    private func fakeBundle() throws -> Bundle {
        let url = FileManager.default.temporaryDirectory.appending(path: "StrataAdminTests-\(UUID().uuidString).app")
        let helpers = url.appending(path: "Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.strata.admin", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: url.appending(path: "Contents/Info.plist"))
        XCTAssertTrue(FileManager.default.createFile(atPath: helpers.appending(path: "StrataReadOnlyScanner").path,
                                                     contents: Data(), attributes: [.posixPermissions: 0o700]))
        return try XCTUnwrap(Bundle(url: url))
    }

    func testAuthCancellationTimeoutAndMalformedOutputPreserveOrdinaryResult() throws {
        let bundle = try fakeBundle()
        for (output, expectedStatus) in [
            (CommandOutput(standardOutput: "", standardError: "User canceled. (-128)", exitCode: 1, timedOut: false), AdministratorScanReport.Status.cancelled),
            (.init(standardOutput: "", standardError: "", exitCode: -1, timedOut: true), .unavailable),
            (.init(standardOutput: "truncated", standardError: "", exitCode: 0, timedOut: false), .unavailable)
        ] {
            let scanner = AdministratorScan(run: { executable, _, _ in
                if executable.lastPathComponent == "codesign" { return .init(standardOutput: "", standardError: "", exitCode: 0, timedOut: false) }
                return output
            })
            let (areas, report) = scanner.refine([area()], bundle: bundle)
            XCTAssertEqual(areas[0].allocatedBytes, 100)
            XCTAssertEqual(report.status, expectedStatus)
        }
    }

    func testFailedSignatureDoesNotRequestAdminAuthorization() throws {
        let scanner = AdministratorScan(run: { executable, _, _ in
            XCTAssertEqual(executable.lastPathComponent, "codesign")
            return .init(standardOutput: "", standardError: "invalid signature", exitCode: 1, timedOut: false)
        })
        let (_, report) = scanner.refine([area()], bundle: try fakeBundle())
        XCTAssertEqual(report.status, .unavailable)
    }

    func testLivePackagedReadOnlyAdministratorScan() throws {
        guard let path = ProcessInfo.processInfo.environment["STRATA_ADMIN_BUNDLE"] else {
            throw XCTSkip("Opt-in macOS authorization and fixed-scope read-only scan")
        }
        let bundle = try XCTUnwrap(Bundle(path: path))
        let areas = ReadOnlyScanScope.paths.map { path in
            let ordinary = FileSystemScanner().measure(urls: [URL(fileURLWithPath: path)])
            return VolumeAreaUsage(name: ReadOnlyScanScope.displayPath(path), path: ReadOnlyScanScope.displayPath(path),
                symbol: "folder", allocatedBytes: ordinary.allocatedBytes,
                inaccessibleItemCount: ordinary.inaccessibleItemCount, inaccessiblePaths: ordinary.inaccessiblePaths)
        }
        let log = ScanLog(directory: URL(fileURLWithPath: "/private/tmp/strata-admin-validation"))
        let (merged, report) = ScanLogContext.$current.withValue(log) {
            AdministratorScan().refine(areas, bundle: bundle)
        }
        log.write("validation_comparison", ["ordinary": areas.map { ["path": $0.path, "bytes": $0.allocatedBytes, "errors": $0.inaccessibleItemCount] },
            "merged": merged.map { ["path": $0.path, "bytes": $0.allocatedBytes, "errors": $0.inaccessibleItemCount] }])
        log.finish(status: report.status.rawValue)
        print("Administrator validation: status=\(report.status.rawValue), additionalBytes=\(report.additionalBytes), improvedAreas=\(report.improvedAreas), log=\(log.url.path)")
        XCTAssertTrue(report.status == .completed || report.status == .partial)
        XCTAssertGreaterThanOrEqual(merged.reduce(Int64(0)) { $0 + $1.allocatedBytes }, areas.reduce(Int64(0)) { $0 + $1.allocatedBytes })
    }
}

final class ReadOnlyDirectoryScannerTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "StrataReadOnlyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testAllocatedBytesMatchExistingScannerWithLinksAndSparseFiles() throws {
        let root = try fixture()
        let outside = try fixture()
        try Data(repeating: 5, count: 32_768).write(to: outside.appending(path: "outside"))
        let file = root.appending(path: "file")
        try Data(repeating: 7, count: 8192).write(to: file)
        try FileManager.default.linkItem(at: file, to: root.appending(path: "hard-link"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "directory-link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "file-link"), withDestinationURL: file)
        let nested = root.appending(path: "nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data(repeating: 4, count: 12_288).write(to: nested.appending(path: "normal"))
        let sparse = nested.appending(path: "sparse")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 100_000_000)
        try handle.close()
        let actual = ReadOnlyDirectoryScanner().measure(path: root.path)
        let expected = FileSystemScanner().measure(urls: [root])
        XCTAssertTrue(actual.complete)
        XCTAssertEqual(actual.unreadableCount, 0)
        XCTAssertEqual(actual.bytes, expected.allocatedBytes)
        XCTAssertLessThan(actual.bytes, 100_000_000)
    }

    func testRootSymlinkIsNotFollowedAndMissingRootIsNotSuccess() throws {
        let root = try fixture()
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        for path in [link.path, root.appending(path: "absent").path] {
            let result = ReadOnlyDirectoryScanner().measure(path: path)
            XCTAssertEqual(result.bytes, 0)
            XCTAssertEqual(result.unreadableCount, 1)
        }
    }

    func testCancellationAndEntryLimitCannotProduceCompleteMeasurement() throws {
        let root = try fixture()
        try Data([1]).write(to: root.appending(path: "file"))
        XCTAssertFalse(ReadOnlyDirectoryScanner().measure(path: root.path, shouldStop: { true }).complete)
        XCTAssertFalse(ReadOnlyDirectoryScanner().measure(path: root.path, maxEntries: 0).complete)
    }

    func testFixedScopeExcludesUserDataAndExternalVolumes() {
        XCTAssertEqual(ReadOnlyScanScope.paths.count, 6)
        XCTAssertFalse(ReadOnlyScanScope.paths.contains { $0.contains("/Users") || $0.hasSuffix("/Volumes") })
        XCTAssertEqual(Set(ReadOnlyScanScope.paths).count, ReadOnlyScanScope.paths.count)
    }

    func testLeaseRejectsSymlinksAndStopsAfterUnlink() throws {
        XCTAssertNil(ReadOnlyScanLease(id: "../../arbitrary-path"))
        let id = UUID().uuidString
        let directory = URL(fileURLWithPath: "/private/tmp/strata-readonly-" + id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let leaseURL = directory.appending(path: "lease")
        XCTAssertTrue(FileManager.default.createFile(atPath: leaseURL.path, contents: Data(), attributes: [.posixPermissions: 0o600]))
        let lease = try XCTUnwrap(ReadOnlyScanLease(id: id))
        XCTAssertTrue(lease.isActive)
        try FileManager.default.removeItem(at: leaseURL)
        XCTAssertFalse(lease.isActive)
        try FileManager.default.createSymbolicLink(at: leaseURL, withDestinationURL: directory)
        XCTAssertNil(ReadOnlyScanLease(id: id))
    }
}
