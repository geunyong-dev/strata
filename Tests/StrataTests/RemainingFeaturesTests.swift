import XCTest
@testable import Strata

final class RemainingFeaturesTests: XCTestCase {
    func testLiveReadOnlySpaceDiagnostics() throws {
        guard ProcessInfo.processInfo.environment["STRATA_LIVE_DIAGNOSTICS"] == "1" else {
            throw XCTSkip("Opt-in read-only diskutil integration check")
        }
        let report = SpaceDiagnosticAnalyzer().scan()
        XCTAssertTrue(report.unavailable.isEmpty, report.unavailable.joined(separator: "\n"))
        XCTAssertTrue(report.facts.contains { $0.contains("데이터 볼륨의 OS 보고 사용량") })
        XCTAssertTrue(report.facts.contains { $0.contains("데이터 볼륨 스냅샷:") })
        XCTAssertTrue(report.facts.contains { $0.contains("시스템 볼륨 스냅샷:") })
    }

    private actor ScanSequence {
        var count = 0
        let snapshot: ScanSnapshot
        init(_ snapshot: ScanSnapshot) { self.snapshot = snapshot }
        func next() async throws -> ScanSnapshot {
            count += 1
            if count == 1 { return snapshot }
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
    }

    @MainActor
    func testScopedSelectionAndCancelledRescanPreserveCompletedSnapshot() async {
        let definition = ProjectArtifactCatalog.definitions[0]
        let artifacts = ["/Users/me/node_modules", "/Library/demo/node_modules"].map {
            ProjectArtifact(definition: definition, path: $0, projectName: "test", allocatedBytes: 100,
                                modifiedAt: nil, inaccessibleItemCount: 0,
                                evidence: .init(isConfirmed: true, summary: "선택 동작 테스트용 근거"))
        }
        let snapshot = ScanSnapshot(volume: VolumeUsage(totalBytes: 1000, availableBytes: 500), volumeAreas: [],
            diskAccess: DiskAccessReport(state: .available, checkedPaths: [], deniedPaths: []),
            diagnostics: DeveloperDiagnostics(docker: DockerDiagnostic(state: .available, resources: []),
                xcode: XcodeDiagnostic(state: .available, runtimes: [], deviceCount: 0, unavailableDeviceCount: 0)),
            projectArtifacts: ProjectArtifactReport(scannedRoots: [], artifacts: artifacts, inaccessibleItemCount: 0),
            usages: [], startedAt: Date(), finishedAt: Date())
        let sequence = ScanSequence(snapshot)
        let model = DashboardViewModel(scanOperation: { _ in try await sequence.next() })
        await model.scan()
        XCTAssertEqual(model.selectedCleanupActionIDs.count, 2)
        model.setCleanupGroupSelected(.safe, selected: false, onlyIDs: ["project:/Users/me/node_modules"])
        XCTAssertEqual(model.selectedCleanupActionIDs, ["project:/Library/demo/node_modules"])
        let task = Task { await model.scan() }
        while !model.isScanning { await Task.yield() }
        model.cancelScan()
        await task.value
        guard case let .loaded(restored) = model.state else { return XCTFail("Previous snapshot lost") }
        XCTAssertEqual(restored.finishedAt, snapshot.finishedAt)
        XCTAssertEqual(model.selectedCleanupActionIDs, ["project:/Library/demo/node_modules"])
        XCTAssertFalse(model.canExecuteCleanup)
    }

    @MainActor
    func testHistoryAvailableBeforeScan() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CleanupHistoryStore(fileURL: root.appending(path: "history.json"))
        let run = CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
                                    availableBytesBefore: 10, availableBytesAfter: 20, results: [])
        try store.save([run])
        let model = DashboardViewModel(store: store)
        XCTAssertEqual(model.cleanupHistory.first?.id, run.id)
        guard case .idle = model.state else { return XCTFail("History must not require scan") }
    }
    private func action(_ path: String) -> CleanupAction {
        CleanupAction(id: path, kind: .projectArtifact(path: path), title: path, detail: "",
                      baselineBytes: 1, estimatedBytes: 1, safety: .safe, executionPreview: "")
    }

    func testScopeUsesPathBoundaryAndDataVolumeAlias() {
        XCTAssertTrue(CleanupScope.contains(action("/Users/me/project/.build"), area: "/Users"))
        XCTAssertFalse(CleanupScope.contains(action("/Users-other/project/.build"), area: "/Users"))
        XCTAssertTrue(CleanupScope.contains(action("/System/Volumes/Data/Users/me/.build"), area: "/Users"))
        XCTAssertFalse(CleanupScope.contains(action("/Library/project/.build"), area: "/Users"))
        let docker = CleanupAction(id: "docker", kind: .docker(resourceType: "Images"), title: "",
                                   detail: "", baselineBytes: 1, estimatedBytes: 1, safety: .caution, executionPreview: "")
        XCTAssertTrue(CleanupScope.isUnlocated(docker))
        XCTAssertFalse(CleanupScope.contains(docker, area: "/Users"))
    }

    @MainActor
    func testCancelReturnsToIdleWithoutPartialActions() async {
        let model = DashboardViewModel(scanOperation: { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        })
        let task = Task { await model.scan() }
        while !model.isScanning { await Task.yield() }
        model.cancelScan()
        await task.value
        guard case .idle = model.state else { return XCTFail("Cancelled scan must not publish a result") }
        XCTAssertNil(model.scanProgress)
        XCTAssertNotNil(model.scanNotice)
        XCTAssertFalse(model.isCancellingScan)
        XCTAssertTrue(model.cleanupActions.isEmpty)
        XCTAssertFalse(model.canExecuteCleanup)
    }

    func testCancelledFileScanDoesNotEnumerate() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return FileSystemScanner().measure(urls: [FileManager.default.temporaryDirectory])
        }
        let result = await task.value
        XCTAssertEqual(result.allocatedBytes, 0)
    }

    func testRunningCommandCanBeCancelled() async throws {
        let start = Date()
        let task = Task.detached {
            CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"])
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testHistorySortsAndLimitsToFiftyAndProtectsCorruption() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "history.json")
        let store = CleanupHistoryStore(fileURL: file)
        let runs = (0..<55).map { index in
            CleanupRunSummary(id: UUID(), startedAt: Date(timeIntervalSince1970: Double(index)),
                              finishedAt: Date(timeIntervalSince1970: Double(index)),
                              availableBytesBefore: 0, availableBytesAfter: 10, results: [])
        }
        try store.save(runs)
        let loaded = try store.loadChecked()
        XCTAssertEqual(loaded.count, 50)
        XCTAssertEqual(loaded.first?.id, runs.last?.id)
        XCTAssertEqual(loaded.last?.id, runs[5].id)
        let invalid = Data("invalid".utf8)
        try invalid.write(to: file)
        XCTAssertThrowsError(try store.loadChecked())
        XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: file), invalid)
    }

    func testSnapshotParserDistinguishesEmptyMissingAndFailed() throws {
        func output(_ object: [String: Any]) throws -> CommandOutput {
            let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            return CommandOutput(standardOutput: String(decoding: data, as: UTF8.self), standardError: "", exitCode: 0, timedOut: false)
        }
        let empty = try SpaceDiagnosticAnalyzer.decode(SpaceDiagnosticAnalyzer.SnapshotList.self, output: output(["Snapshots": []]))
        XCTAssertEqual(empty.Snapshots.count, 0)
        let nonempty = try SpaceDiagnosticAnalyzer.decode(SpaceDiagnosticAnalyzer.SnapshotList.self,
            output: output(["Snapshots": [["Name": "com.apple.os.update.test"]]]))
        XCTAssertEqual(nonempty.Snapshots.first?.Name, "com.apple.os.update.test")
        XCTAssertThrowsError(try SpaceDiagnosticAnalyzer.decode(SpaceDiagnosticAnalyzer.SnapshotList.self, output: output([:])))
        XCTAssertThrowsError(try SpaceDiagnosticAnalyzer.decode(SpaceDiagnosticAnalyzer.SnapshotList.self,
            output: CommandOutput(standardOutput: "", standardError: "denied", exitCode: 1, timedOut: false)))
    }
}
