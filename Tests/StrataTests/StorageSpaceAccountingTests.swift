import XCTest
@testable import Strata

final class StorageSpaceAccountingTests: XCTestCase {
    private var volume: VolumeUsage {
        .init(totalBytes: 500, availableBytes: 120, physicalAvailableBytes: 100, volumeUUID: "data-uuid")
    }
    private func evidence(capacity: Int64 = 500, free: Int64 = 100, data: Int64 = 350,
                          uuid: String = "DATA-UUID", siblings: [APFSVolumeUsage]? = nil) -> APFSContainerUsage {
        .init(containerID: "disk3", dataVolumeID: "disk3s5", dataVolumeUUID: uuid,
              capacityBytes: capacity, freeBytes: free, dataUsedBytes: data,
              otherVolumes: siblings ?? [
                .init(id: "disk3s1", name: "Macintosh HD", roles: ["System"], usedBytes: 20),
                .init(id: "disk3s2", name: "Preboot", roles: ["Preboot"], usedBytes: 10),
                .init(id: "disk3s6", name: "VM", roles: ["VM"], usedBytes: 5)])
    }
    private func area(_ path: String, _ bytes: Int64, trash: Bool = false) -> VolumeAreaUsage {
        .init(name: path, path: path, symbol: "folder", allocatedBytes: bytes,
              inaccessibleItemCount: 0, inaccessiblePaths: [], isTrash: trash)
    }

    func testSeparatesKnownVolumeUsageWithoutChangingDiskUsageOrFileSum() {
        let result = StorageSpaceAccounting(volume: volume, measuredBytes: 300, evidence: evidence())
        XCTAssertEqual(result.status, .separated)
        XCTAssertEqual(result.rawGapBytes, 100)
        XCTAssertEqual(result.knownVolumeBytes, 35)
        XCTAssertEqual(result.unresolvedBytes, 65)
        XCTAssertEqual(300 + result.knownVolumeBytes + result.unresolvedBytes + volume.displayedAvailableBytes, volume.totalBytes)
        XCTAssertEqual(result.volumes.map(\.displayName), ["macOS 운영체제", "시동 지원 데이터", "가상 메모리"])
    }

    func testMissingIdentityDifferentDiskAndImportantOnlyCapacityNeverSubtract() {
        var missing = volume; missing.volumeUUID = nil
        var importantOnly = volume; importantOnly.physicalAvailableBytes = nil
        var invalidFree = volume; invalidFree.physicalAvailableBytes = -1
        for (input, proof) in [(missing, evidence()), (importantOnly, evidence()), (invalidFree, evidence()),
                               (volume, evidence(uuid: "other-disk")), (volume, evidence(capacity: 1000))] {
            let result = StorageSpaceAccounting(volume: input, measuredBytes: 300, evidence: proof)
            XCTAssertEqual(result.status, .unavailable)
            XCTAssertEqual(result.knownVolumeBytes, 0)
            XCTAssertEqual(result.unresolvedBytes, input.usedBytes - 300)
        }
        XCTAssertEqual(StorageSpaceAccounting(volume: volume, measuredBytes: 300, evidence: nil).unresolvedBytes, 100)
    }

    func testInconsistentNegativeAndDuplicateValuesDoNotClampIntoGap() {
        for proof in [evidence(data: 290), evidence(data: 390), evidence(free: -1),
                      evidence(siblings: [.init(id: "x", name: "x", roles: [], usedBytes: -1)]),
                      evidence(siblings: [.init(id: "x", name: "x", roles: [], usedBytes: 110)]),
                      evidence(siblings: [.init(id: "disk3s5", name: "data", roles: ["Data"], usedBytes: 1)]),
                      evidence(siblings: [.init(id: "x", name: "x", roles: [], usedBytes: 10),
                                          .init(id: "x", name: "x", roles: [], usedBytes: 10)])] {
            let result = StorageSpaceAccounting(volume: volume, measuredBytes: 300, evidence: proof)
            XCTAssertEqual(result.status, .inconsistent)
            XCTAssertEqual(result.knownVolumeBytes, 0)
            XCTAssertEqual(result.unresolvedBytes, 100)
        }
        let overshoot = StorageSpaceAccounting(volume: volume, measuredBytes: 450, evidence: evidence())
        XCTAssertEqual(overshoot.status, .inconsistent)
        XCTAssertEqual(overshoot.knownVolumeBytes, 0)
    }

    func testExtremeNumbersCannotOverflowEvidenceSum() {
        let maximum = VolumeUsage(totalBytes: Int64.max, availableBytes: 0, physicalAvailableBytes: 0, volumeUUID: "DATA-UUID")
        let proof = evidence(capacity: Int64.max, free: 0, data: 0, siblings: [
            .init(id: "1", name: "1", roles: [], usedBytes: Int64.max),
            .init(id: "2", name: "2", roles: [], usedBytes: Int64.max)])
        XCTAssertEqual(StorageSpaceAccounting(volume: maximum, measuredBytes: 0, evidence: proof).status, .inconsistent)
    }

    func testCoreKeepsAtMostSevenBandsPreservesTrashAndAllAreaPaths() {
        let areas = (1...10).map { area("/area\($0)", Int64($0)) } + [area("/Users/me/.Trash", 1, trash: true)]
        let data = CoreStorageBreakdown(volume: volume, areas: areas, evidence: evidence())
        XCTAssertEqual(data.bands.count, 7)
        XCTAssertEqual(data.bands.first(where: { $0.kind == .systemVolumes })?.bytes, 35)
        XCTAssertTrue(data.bands.contains { $0.kind == .area && $0.areas.first?.isTrash == true })
        XCTAssertEqual(Set(data.bands.flatMap(\.areas).map(\.path)), Set(areas.map(\.path)))
        XCTAssertEqual(data.bands.reduce(0) { $0 + $1.bytes }, 500)
        XCTAssertFalse(data.bands.first(where: { $0.kind == .systemVolumes })!.areas.contains { $0.isTrash })
        let scanning = CoreStorageBreakdown(volume: volume, areas: areas, isScanning: true, evidence: evidence())
        XCTAssertFalse(scanning.bands.contains { $0.kind == .systemVolumes })
    }

    func testFriendlySystemNamesKeepOriginalPathsAndSafetyExplanation() {
        XCTAssertEqual(StorageAnalyzer.areaPresentation(for: ".Spotlight-V100").name, "Spotlight 검색 데이터")
        XCTAssertEqual(StorageAnalyzer.areaPresentation(for: ".DocumentRevisions-V100").name, "문서 변경 이력")
        XCTAssertEqual(StorageAnalyzer.areaPresentation(for: ".fseventsd").name, "파일 변경 기록")
        let spotlight = area("/.Spotlight-V100", 58)
        XCTAssertTrue(spotlight.systemDataExplanation!.contains("삭제 가능한 공간이라는 뜻은 아닙니다"))
        XCTAssertEqual(spotlight.id, "/.Spotlight-V100")
    }

    func testParserSelectsMatchingDataVolumeAndExcludesItFromSiblings() {
        let info = SpaceDiagnosticAnalyzer.VolumeInfo(APFSContainerReference: "disk3", DeviceIdentifier: "disk3s5",
                                                      CapacityInUse: 999, VolumeUUID: "data-uuid")
        let container = SpaceDiagnosticAnalyzer.Container(ContainerReference: "disk3", CapacityCeiling: 500, CapacityFree: 100,
            Volumes: [
                .init(DeviceIdentifier: "disk3s5", Name: "Data", CapacityInUse: 350, Roles: ["Data"], APFSVolumeUUID: "data-uuid"),
                .init(DeviceIdentifier: "disk3s1", Name: "System", CapacityInUse: 20, Roles: ["System"])])
        let parsed = SpaceDiagnosticAnalyzer.containerUsage(info: info, container: container)
        XCTAssertEqual(parsed?.dataUsedBytes, 350, "Use the same container sample, not an earlier info sample")
        XCTAssertEqual(parsed?.otherVolumes.count, 1)
        XCTAssertEqual(parsed?.otherVolumes.first?.id, "disk3s1")
        let otherContainer = SpaceDiagnosticAnalyzer.Container(ContainerReference: "disk99", CapacityCeiling: 500, CapacityFree: 100, Volumes: container.Volumes)
        XCTAssertNil(SpaceDiagnosticAnalyzer.containerUsage(info: info, container: otherContainer))
    }

    func testLiveVolumeIdentityAndStructuredAccounting() throws {
        guard ProcessInfo.processInfo.environment["STRATA_LIVE_DIAGNOSTICS"] == "1" else {
            throw XCTSkip("Opt-in read-only volume accounting")
        }
        let report = SpaceDiagnosticAnalyzer().scan()
        let proof = try XCTUnwrap(report.containerUsage)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try home.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let live = VolumeUsage(totalBytes: Int64(values.volumeTotalCapacity ?? 0), availableBytes: 0,
            physicalAvailableBytes: values.volumeAvailableCapacity.map(Int64.init), volumeUUID: values.volumeUUIDString)
        XCTAssertEqual(live.volumeUUID?.lowercased(), proof.dataVolumeUUID.lowercased())
        let result = StorageSpaceAccounting(volume: live, measuredBytes: 0, evidence: proof)
        XCTAssertEqual(result.status, .separated)
        XCTAssertGreaterThan(result.knownVolumeBytes, 0)
        print("APFS accounting validated: knownVolumeBytes=\(result.knownVolumeBytes), dataVolume=\(proof.dataVolumeID)")
    }

    func testStructuredAccountingLogsPreserveOriginalGapAndAreJSONSerializable() throws {
        let snapshot = ScanSnapshot(volume: volume, volumeAreas: [area("/Users", 300)],
            diskAccess: .init(state: .available, checkedPaths: [], deniedPaths: []),
            diagnostics: .init(docker: .init(state: .available, resources: []),
                xcode: .init(state: .available, runtimes: [], deviceCount: 0, unavailableDeviceCount: 0)),
            projectArtifacts: .init(scannedRoots: [], artifacts: [], inaccessibleItemCount: 0),
            usages: [], startedAt: Date(), finishedAt: Date(),
            spaceDiagnostics: .init(containerUsage: evidence()))
        let fields = ScanLog.accountingFields(snapshot)
        XCTAssertEqual(fields["rawGapBytes"] as? Int64, 100)
        XCTAssertEqual(fields["knownVolumeBytes"] as? Int64, 35)
        XCTAssertEqual(fields["unresolvedBytes"] as? Int64, 65)
        XCTAssertEqual(snapshot.unaccountedBytes, 65)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(fields))
        XCTAssertNotNil(fields["containerUsage"])
        let directory = FileManager.default.temporaryDirectory.appending(path: "StrataAccountingLogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = ScanLog(directory: directory)
        log.summary(snapshot)
        log.finish(status: "completed")
        XCTAssertNil(log.warning)
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
        let objects = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(objects.first?["schemaVersion"] as? Int, 3)
        XCTAssertEqual(objects.first(where: { $0["event"] as? String == "summary" })?["unclassifiedBytes"] as? Int, 65)
    }
}
