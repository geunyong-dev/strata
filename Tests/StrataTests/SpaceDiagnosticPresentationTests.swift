import XCTest
@testable import Strata

final class SpaceDiagnosticPresentationTests: XCTestCase {
    private func snapshot(bytes: Int64 = 100, unreadable: Int = 0,
                          report: SpaceDiagnosticReport? = .init(), artifacts: [ProjectArtifact] = []) -> ScanSnapshot {
        ScanSnapshot(volume: .init(totalBytes: 1000, availableBytes: 500),
            volumeAreas: [.init(name: "사용자", path: "/Users", symbol: "folder", allocatedBytes: bytes,
                                inaccessibleItemCount: unreadable, inaccessiblePaths: [])],
            diskAccess: .init(state: .available, checkedPaths: [], deniedPaths: []),
            diagnostics: .init(docker: .init(state: .available, resources: []),
                xcode: .init(state: .available, runtimes: [], deviceCount: 0, unavailableDeviceCount: 0)),
            projectArtifacts: .init(scannedRoots: [], artifacts: artifacts, inaccessibleItemCount: 0),
            usages: [], startedAt: Date(), finishedAt: Date(), spaceDiagnostics: report)
    }

    func testGuidanceMatchesObservedStateWithoutClaimingReclaimableSpace() {
        XCTAssertTrue(SpaceDiagnosticPresentation(snapshot: snapshot(bytes: 600)).guidance.contains("측정값에 차이"))
        XCTAssertTrue(SpaceDiagnosticPresentation(snapshot: snapshot(unreadable: 1)).guidance.contains("보호 폴더 읽기는 확인"))
        XCTAssertTrue(SpaceDiagnosticPresentation(snapshot: snapshot(report: nil)).guidance.contains("추가 진단"))
        XCTAssertTrue(SpaceDiagnosticPresentation(snapshot: snapshot(report: .init(unavailable: ["test"]))).guidance.contains("일부 진단"))
        XCTAssertTrue(SpaceDiagnosticPresentation(snapshot: snapshot()).guidance.contains("직접 선택"))
    }

    @MainActor
    func testOnlySupportedCompleteCandidatesAreInitiallySelected() async {
        let definition = ProjectArtifactCatalog.definitions[0]
        let artifacts = [
            ProjectArtifact(definition: definition, path: "/fixture/unknown/node_modules", projectName: "unknown",
                allocatedBytes: 100, modifiedAt: nil, inaccessibleItemCount: 0),
            ProjectArtifact(definition: definition, path: "/fixture/confirmed/node_modules", projectName: "confirmed",
                allocatedBytes: 100, modifiedAt: nil, inaccessibleItemCount: 0,
                evidence: .init(isConfirmed: true, summary: "fixture")),
            ProjectArtifact(definition: definition, path: "/fixture/partial/node_modules", projectName: "partial",
                allocatedBytes: 100, modifiedAt: nil, inaccessibleItemCount: 1,
                evidence: .init(isConfirmed: true, summary: "fixture"))
        ]
        let value = snapshot(artifacts: artifacts)
        let model = DashboardViewModel(scanOperation: { _ in value })
        await model.scan()
        XCTAssertEqual(model.selectedCleanupActionIDs, ["project:/fixture/confirmed/node_modules"])
        XCTAssertEqual(model.cleanupActions.filter { $0.safety == .caution }.count, 2)
    }
}
