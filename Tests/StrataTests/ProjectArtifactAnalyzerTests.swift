import XCTest
import Darwin
@testable import Strata

final class ProjectArtifactAnalyzerTests: XCTestCase {
    func testSymlinkDoesNotHideSiblingProjectOrFollowExternalCandidate() throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let external = fixture.appending(path: "external/node_modules")
        let root = fixture.appending(path: "scan")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        for index in 0..<8 {
            let parent = root.appending(path: "group\(index)")
            let candidate = parent.appending(path: "project/node_modules")
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: candidate.appending(path: "data"))
            try FileManager.default.createSymbolicLink(at: parent.appending(path: "link"), withDestinationURL: external)
        }
        let report = ProjectArtifactAnalyzer().scan(roots: [root])
        XCTAssertEqual(report.artifacts.count, 8)
        XCTAssertTrue(report.artifacts.allSatisfy { $0.path.hasSuffix("project/node_modules") && $0.allocatedBytes > 0 })
    }

    func testCapturesFolderDatesBeforeMeasuringContents() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "project/node_modules")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: folder.appending(path: "data"))
        let timestamps = [timespec(tv_sec: 1_600_000_000, tv_nsec: 0),
                          timespec(tv_sec: 1_610_000_000, tv_nsec: 0)]
        XCTAssertEqual(folder.path.withCString { utimensat(AT_FDCWD, $0, timestamps, 0) }, 0)
        let artifact = try XCTUnwrap(ProjectArtifactAnalyzer().scan(roots: [root]).artifacts.first)
        XCTAssertNotNil(artifact.createdAt)
        XCTAssertEqual(artifact.modifiedAt, Date(timeIntervalSince1970: 1_610_000_000))
        XCTAssertEqual(artifact.accessedAt, Date(timeIntervalSince1970: 1_600_000_000))
    }

    func testFindsArtifactsSkipsIgnoredFoldersAndAvoidsNestedCandidates() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appending(path: "web-app", directoryHint: .isDirectory)
        let nodeModules = project.appending(path: "node_modules", directoryHint: .isDirectory)
        let nestedNodeModules = nodeModules
            .appending(path: "dependency", directoryHint: .isDirectory)
            .appending(path: "node_modules", directoryHint: .isDirectory)
        let next = project.appending(path: ".next", directoryHint: .isDirectory)
        let ignored = project.appending(path: ".git/node_modules", directoryHint: .isDirectory)

        for directory in [nestedNodeModules, next, ignored] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8_192).write(to: directory.appending(path: "data"))
        }

        let report = ProjectArtifactAnalyzer().scan(roots: [root])

        XCTAssertEqual(report.artifacts.count, 2)
        XCTAssertEqual(Set(report.artifacts.map(\.definition.id)), ["node-modules", "next"])
        XCTAssertFalse(report.artifacts.contains { $0.path.hasPrefix(ignored.path) })
        XCTAssertEqual(report.artifacts.first { $0.definition.id == "node-modules" }?.projectName, "web-app")
    }

    func testReportsNoRootsWithoutSearchingHomeDirectory() {
        let report = ProjectArtifactAnalyzer().scan(roots: [])
        XCTAssertTrue(report.scannedRoots.isEmpty)
        XCTAssertTrue(report.artifacts.isEmpty)
    }
}
