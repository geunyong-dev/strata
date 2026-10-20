import XCTest
@testable import Strata

final class CleanupPlanTests: XCTestCase {
    func testBuildsRiskRatedActionsFromDiagnosticsAndArtifacts() {
        let recordedDate = Date(timeIntervalSince1970: 1_600_000_000)
        let docker = DockerDiagnostic(
            state: .available,
            resources: [
                .init(type: "Build Cache", totalCount: 4, activeCount: 0, sizeBytes: 2_000, reclaimableBytes: 2_000),
                .init(type: "Local Volumes", totalCount: 1, activeCount: 0, sizeBytes: 3_000, reclaimableBytes: 3_000)
            ]
        )
        let runtime = SimulatorRuntimeUsage(
            id: "runtime-id", platform: "iOS", version: "18.0", build: "build",
            sizeBytes: 4_000, state: "Ready", isDeletable: true, lastUsedAt: recordedDate
        )
        let artifactDefinition = ProjectArtifactDefinition(
            id: "node-modules", name: "Node.js 의존성", directoryNames: ["node_modules"],
            symbol: "shippingbox", safety: .safe, reclaimability: 1, explanation: "test"
        )
        let artifact = ProjectArtifact(
            definition: artifactDefinition, path: "/tmp/project/node_modules", projectName: "project",
            allocatedBytes: 5_000, modifiedAt: recordedDate, inaccessibleItemCount: 0,
            createdAt: recordedDate.addingTimeInterval(-100), accessedAt: recordedDate.addingTimeInterval(100)
        )
        let diagnostics = DeveloperDiagnostics(
            docker: docker,
            xcode: XcodeDiagnostic(
                state: .available, runtimes: [runtime], deviceCount: 0, unavailableDeviceCount: 0
            )
        )
        let report = ProjectArtifactReport(
            scannedRoots: ["/tmp/project"], artifacts: [artifact], inaccessibleItemCount: 0
        )

        let actions = CleanupPlanBuilder().makeActions(diagnostics: diagnostics, projectArtifacts: report)

        XCTAssertEqual(actions.count, 4)
        XCTAssertEqual(actions.first?.safety, .safe)
        XCTAssertEqual(actions.first { $0.id == "docker:Local Volumes" }?.safety, .dangerous)
        XCTAssertEqual(actions.first { $0.id == "simulator:runtime-id" }?.safety, .caution)
        let project = actions.first { $0.id == "project:\(artifact.path)" }
        XCTAssertEqual(project?.createdAt, artifact.createdAt)
        XCTAssertEqual(project?.modifiedAt, artifact.modifiedAt)
        XCTAssertEqual(project?.accessedAt, artifact.accessedAt)
        XCTAssertNil(project?.lastUsedAt)
        XCTAssertEqual(actions.first { $0.id == "simulator:runtime-id" }?.lastUsedAt, recordedDate)
        XCTAssertNil(actions.first { $0.id == "docker:Build Cache" }?.createdAt)
        XCTAssertNil(actions.first { $0.id == "docker:Build Cache" }?.lastUsedAt)
    }

    func testProjectArtifactDryRunOnlyRemeasuresFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "artifact")
        try Data(repeating: 1, count: 8_192).write(to: file)
        let expected = FileSystemScanner().measure(urls: [directory]).allocatedBytes
        let action = CleanupAction(
            id: "project:\(directory.path)",
            kind: .projectArtifact(path: directory.path),
            title: "Test", detail: directory.path, baselineBytes: expected, estimatedBytes: expected,
            safety: .safe, executionPreview: "휴지통으로 이동: \(directory.path)"
        )

        let results = await CleanupDryRunAnalyzer().preview([action])

        XCTAssertEqual(results[action.id]?.status, .verified)
        XCTAssertEqual(results[action.id]?.currentBytes, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupTargetValidatorRequiresKnownFolderInsideAllowedRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let allowed = root.appending(path: "project/node_modules", directoryHint: .isDirectory)
        let unknown = root.appending(path: "project/source", directoryHint: .isDirectory)
        let symlink = root.appending(path: "project-link", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: allowed)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertTrue(CleanupTargetValidator.isAllowedProjectArtifact(allowed, allowedRoots: [root]))
        XCTAssertFalse(CleanupTargetValidator.isAllowedProjectArtifact(unknown, allowedRoots: [root]))
        XCTAssertFalse(CleanupTargetValidator.isAllowedProjectArtifact(symlink, allowedRoots: [root]))
    }

    func testExecutorNeverRunsDangerousAction() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let artifact = root.appending(path: "node_modules", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: artifact.appending(path: "data"))
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = FileSystemScanner().measure(urls: [artifact]).allocatedBytes
        let action = CleanupAction(
            id: "danger-test",
            kind: .projectArtifact(path: artifact.path),
            title: "Danger", detail: artifact.path,
            baselineBytes: bytes, estimatedBytes: bytes,
            safety: .dangerous, executionPreview: "not executed"
        )

        let summary = await CleanupExecutor().execute([action], allowedProjectRoots: [root.path])

        XCTAssertEqual(summary.results.first?.status, .skipped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.path))
    }

    func testCleanupHistoryStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CleanupHistoryStore(fileURL: root.appending(path: "history.json"))
        let summary = CleanupRunSummary(
            id: UUID(), startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 101),
            availableBytesBefore: 1_000, availableBytesAfter: 2_000,
            results: [
                .init(actionID: "action", title: "Test", status: .succeeded, message: "Done")
            ]
        )

        try store.save([summary])
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, summary.id)
        XCTAssertEqual(loaded[0].spaceChangeBytes, 1_000)
        XCTAssertEqual(loaded[0].results.first?.status, .succeeded)
    }
}
