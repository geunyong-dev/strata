import XCTest
@testable import Strata

final class ArtifactEvidenceTests: XCTestCase {
    private func fixture(_ files: [String: String], body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, content) in files {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: file)
        }
        try body(root)
    }

    func testNameAloneIsCautionAndPlanIncludesReason() throws {
        try fixture(["node_modules/data": "data", ".next/data": "data", "build/data": "data", "coverage/data": "data"]) { root in
            let report = ProjectArtifactAnalyzer().scan(roots: [root])
            XCTAssertEqual(report.artifacts.count, 4)
            XCTAssertTrue(report.artifacts.allSatisfy { !$0.evidence.isConfirmed && $0.safety == .caution })
            let diagnostics = DeveloperDiagnostics(docker: .init(state: .available, resources: []),
                xcode: .init(state: .available, runtimes: [], deviceCount: 0, unavailableDeviceCount: 0))
            let actions = CleanupPlanBuilder().makeActions(diagnostics: diagnostics, projectArtifacts: report)
            XCTAssertTrue(actions.allSatisfy { $0.safety == .caution && $0.candidateEvidence?.contains("기본 선택하지") == true })
        }
    }

    func testNodeNeedsValidManifestAndLockfileAndNextNeedsDependency() throws {
        try fixture(["package.json": "{\"dependencies\":{\"next\":\"15\"}}", "package-lock.json": "{}",
                     "node_modules/data": "data", ".next/data": "data"]) { root in
            let report = ProjectArtifactAnalyzer().scan(roots: [root])
            XCTAssertTrue(report.artifacts.allSatisfy { $0.evidence.isConfirmed && $0.safety == .safe })
            try Data("invalid json".utf8).write(to: root.appending(path: "package.json"))
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: "node_modules"), definitionID: "node-modules").isConfirmed)
            try Data("{}".utf8).write(to: root.appending(path: "package.json"))
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: ".next"), definitionID: "next").isConfirmed)
            try FileManager.default.removeItem(at: root.appending(path: "package-lock.json"))
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: "node_modules"), definitionID: "node-modules").isConfirmed)
        }
    }

    func testGenericOutputsStayUnconfirmedEvenWithProjectManifest() throws {
        try fixture(["package.json": "{}", "build/data": "data", "dist/data": "data", ".turbo/data": "data"]) { root in
            let report = ProjectArtifactAnalyzer().scan(roots: [root])
            XCTAssertEqual(report.artifacts.count, 3)
            XCTAssertTrue(report.artifacts.allSatisfy { $0.safety == .caution && $0.assessment.contains("확정하지 못해") })
        }
    }

    func testSwiftAndRustRequireInternalToolMarkerAndPartialReadDowngrades() throws {
        try fixture(["Package.swift": "// swift-tools-version: 6.2", ".build/data": "data",
                     "Cargo.toml": "[package]", "target/.rustc_info.json": "{}"]) { root in
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: ".build"), definitionID: "swift-build").isConfirmed)
            try Data("{}".utf8).write(to: root.appending(path: ".build/workspace-state.json"))
            let report = ProjectArtifactAnalyzer().scan(roots: [root])
            XCTAssertTrue(report.artifacts.allSatisfy { $0.evidence.isConfirmed })
            let artifact = try XCTUnwrap(report.artifacts.first)
            let partial = ProjectArtifact(definition: artifact.definition, path: artifact.path, projectName: "partial",
                allocatedBytes: 10, modifiedAt: nil, inaccessibleItemCount: 1, evidence: artifact.evidence)
            XCTAssertEqual(partial.safety, .caution)
        }
    }

    func testManifestSymlinksAndOversizedJSONAreNotTrusted() throws {
        try fixture(["real.json": "{}", "package-lock.json": "{}", "node_modules/data": "data"]) { root in
            let manifest = root.appending(path: "package.json")
            try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: root.appending(path: "real.json"))
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: "node_modules"), definitionID: "node-modules").isConfirmed)
            try FileManager.default.removeItem(at: manifest)
            try Data(repeating: 32, count: 1_048_577).write(to: manifest)
            XCTAssertFalse(ArtifactEvidence.inspect(root.appending(path: "node_modules"), definitionID: "node-modules").isConfirmed)
        }
    }

    func testChangedEvidenceBlocksDryRunWithoutDeletingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "node_modules")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: folder.appending(path: "data"))
        let action = CleanupAction(id: "test", kind: .projectArtifact(path: folder.path), title: "test", detail: folder.path,
            baselineBytes: 4, estimatedBytes: 4, safety: .safe, executionPreview: "",
            confirmedArtifactDefinitionID: "node-modules")
        let results = await CleanupDryRunAnalyzer().preview([action])
        XCTAssertEqual(results[action.id]?.status, .changed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "data").path))
    }
}
