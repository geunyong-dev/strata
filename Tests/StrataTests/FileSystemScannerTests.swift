import XCTest
@testable import Strata

final class FileSystemScannerTests: XCTestCase {
    func testLinksDoNotSkipSiblingDirectoriesOrFollowExternalTargets() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let root = fixture.appending(path: "scan")
        let external = fixture.appending(path: "external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 65536).write(to: external.appending(path: "must-not-count"))
        var expected: Int64 = 0
        // Each bundle has a link and a sibling subtree; no dependence on lexical enumeration order.
        for index in 0..<12 {
            let bundle = root.appending(path: "Bundle\(index).framework")
            let contents = bundle.appending(path: "Versions/A")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let file = contents.appending(path: "payload")
            try Data(repeating: 1, count: 8192).write(to: file)
            var info = stat()
            XCTAssertEqual(lstat(file.path, &info), 0)
            expected += Int64(info.st_blocks) * 512
            try FileManager.default.createSymbolicLink(at: bundle.appending(path: "Current"), withDestinationURL: external)
            try FileManager.default.createSymbolicLink(at: bundle.appending(path: "FileLink"), withDestinationURL: external.appending(path: "must-not-count"))
            try FileManager.default.createSymbolicLink(at: bundle.appending(path: "Broken"), withDestinationURL: fixture.appending(path: "missing"))
        }
        let result = FileSystemScanner().measure(urls: [root])
        XCTAssertEqual(result.allocatedBytes, expected)
        XCTAssertEqual(result.inaccessibleItemCount, 0)
    }

    func testExcludingAFileDoesNotSkipSiblingSubtrees() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var excluded: [URL] = []
        var expected: Int64 = 0
        for index in 0..<12 {
            let parent = root.appending(path: "entry\(index)")
            let child = parent.appending(path: "keep/data")
            try FileManager.default.createDirectory(at: child.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: child)
            var info = stat(); XCTAssertEqual(lstat(child.path, &info), 0)
            expected += Int64(info.st_blocks) * 512
            let file = parent.appending(path: "exclude")
            try Data(repeating: 1, count: 8192).write(to: file)
            excluded.append(file)
        }
        XCTAssertEqual(FileSystemScanner().measure(urls: [root], excludedURLs: excluded).allocatedBytes, expected)
    }

    func testLiveApplicationsAgainstDu() throws {
        guard ProcessInfo.processInfo.environment["STRATA_LIVE_APPLICATIONS"] == "1" else {
            throw XCTSkip("Opt-in read-only /Applications comparison")
        }
        let measured = FileSystemScanner().measure(urls: [URL(fileURLWithPath: "/Applications")])
        let output = CommandRunner().run(executable: URL(fileURLWithPath: "/usr/bin/du"), arguments: ["-skx", "/Applications"], timeout: 60)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertFalse(output.timedOut)
        let kb = try XCTUnwrap(Int64(output.standardOutput.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""))
        print("Applications allocated bytes: Strata=\(measured.allocatedBytes), du=\(kb * 1024), unreadable=\(measured.inaccessibleItemCount)")
        XCTAssertEqual(measured.inaccessibleItemCount, 0)
        XCTAssertEqual(measured.allocatedBytes, kb * 1024)
    }

    func testProgressStartsEmptyAndEndsWithMeasuredBytes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 8192).write(to: root.appending(path: "sample"))
        var updates: [DirectoryScanProgress] = []
        let measurement = FileSystemScanner().measure(urls: [root], onProgress: { updates.append($0) })
        XCTAssertGreaterThanOrEqual(updates.count, 2)
        XCTAssertEqual(updates.first?.allocatedBytes, 0)
        XCTAssertEqual(updates.last?.allocatedBytes, measurement.allocatedBytes)
        XCTAssertEqual(updates.last?.visitedItemCount, 2)
        let reportedPath = try XCTUnwrap(updates.last?.currentPath)
        XCTAssertEqual(URL(fileURLWithPath: reportedPath).resolvingSymlinksInPath().path,
                       root.appending(path: "sample").resolvingSymlinksInPath().path)
        XCTAssertEqual(updates.map(\.allocatedBytes), updates.map(\.allocatedBytes).sorted())
    }

    func testProgressReportsCompletionForMissingRoot() {
        var updates: [DirectoryScanProgress] = []
        let measurement = FileSystemScanner().measure(
            urls: [FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)],
            onProgress: { updates.append($0) })
        XCTAssertEqual(measurement.allocatedBytes, 0)
        XCTAssertEqual(updates.last?.visitedItemCount, 0)
        XCTAssertEqual(updates.count, 2)
    }

    func testCountsAllocatedBytesAndDeduplicatesHardLinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appending(path: "original.bin")
        let linked = root.appending(path: "linked.bin")
        try Data(repeating: 1, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: linked)

        var fileInfo = stat()
        XCTAssertEqual(lstat(original.path, &fileInfo), 0)
        let expected = Int64(fileInfo.st_blocks) * 512

        let result = FileSystemScanner().measure(urls: [root])
        XCTAssertEqual(result.allocatedBytes, expected)
    }

    func testExcludedDirectoryIsNotCounted() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let excluded = root.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 8_192).write(to: excluded.appending(path: "history"))

        let result = FileSystemScanner().measure(urls: [root], excludedURLs: [excluded])
        XCTAssertEqual(result.allocatedBytes, 0)
    }

    func testCountsHiddenCacheFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hiddenFile = root.appending(path: ".cache-entry")
        try Data(repeating: 1, count: 8_192).write(to: hiddenFile)
        var fileInfo = stat()
        XCTAssertEqual(lstat(hiddenFile.path, &fileInfo), 0)

        let result = FileSystemScanner().measure(urls: [root])
        XCTAssertEqual(result.allocatedBytes, Int64(fileInfo.st_blocks) * 512)
    }

    func testCountsARegularFilePassedAsRoot() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 1, count: 8_192).write(to: file)
        var fileInfo = stat()
        XCTAssertEqual(lstat(file.path, &fileInfo), 0)

        let result = FileSystemScanner().measure(urls: [file])
        XCTAssertEqual(result.allocatedBytes, Int64(fileInfo.st_blocks) * 512)
    }

    func testDoesNotFollowASymbolicLinkPassedAsRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let target = root.appending(path: "target", directoryHint: .isDirectory)
        let link = root.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 8_192).write(to: target.appending(path: "data"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = FileSystemScanner().measure(urls: [link])
        XCTAssertEqual(result.allocatedBytes, 0)
    }
}
