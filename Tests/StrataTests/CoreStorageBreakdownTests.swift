import XCTest
import SwiftUI
@testable import Strata

final class CoreStorageBreakdownTests: XCTestCase {
    private func area(_ path: String, _ bytes: Int64, name: String? = nil) -> VolumeAreaUsage {
        VolumeAreaUsage(name: name ?? path, path: path, symbol: "folder", allocatedBytes: bytes,
                        inaccessibleItemCount: 0, inaccessiblePaths: [])
    }

    func testVolumeAndCoreUseSameCapacityBasis() {
        let volume = VolumeUsage(totalBytes: 500, availableBytes: 150, physicalAvailableBytes: 100)
        let data = CoreStorageBreakdown(volume: volume, areas: [area("/Users", 250)])
        XCTAssertEqual(volume.displayedAvailableBytes, 100)
        XCTAssertEqual(volume.usedBytes, 400)
        XCTAssertEqual(data.bands.first(where: { $0.kind == .free })?.bytes, Double(volume.displayedAvailableBytes))
        XCTAssertEqual(data.bands.first(where: { $0.kind == .unmeasured })?.bytes, Double(volume.usedBytes - 250))
        XCTAssertEqual(volume.usedFraction, 0.8)
    }

    func testFallbackAndInvalidCapacityAreClampedConsistently() {
        let fallback = VolumeUsage(totalBytes: 500, availableBytes: 200)
        XCTAssertEqual(fallback.displayedAvailableBytes, 200)
        XCTAssertEqual(fallback.availabilityTitle, "사용 가능")
        XCTAssertEqual(VolumeUsage(totalBytes: 100, availableBytes: 200).usedBytes, 0)
        XCTAssertEqual(VolumeUsage(totalBytes: 100, availableBytes: -20).displayedAvailableBytes, 0)
        XCTAssertEqual(Int64(0).storageFormatted, "0 KB")
    }

    func testFreeAndUnmeasuredAreSeparateAndSumToCapacity() {
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 500, availableBytes: 150, physicalAvailableBytes: 100),
                                        areas: [area("/Users", 300)])
        XCTAssertFalse(data.isMeasuredOnly)
        XCTAssertEqual(data.total, 500)
        XCTAssertEqual(data.bands.map(\.bytes), [100, 100, 300])
        XCTAssertEqual(data.bands[0].kind, .free)
        XCTAssertEqual(data.bands[1].kind, .unmeasured)
        XCTAssertEqual(data.bands.reduce(0) { $0 + $1.bytes }, data.total)
    }

    func testPartialScanDoesNotTreatUnscannedSpaceAsFree() {
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 500, availableBytes: 100),
                                        areas: [area("/Users", 50)], isScanning: true)
        XCTAssertEqual(data.bands.first?.bytes, 100)
        XCTAssertEqual(data.bands.first(where: { $0.kind == .unmeasured })?.bytes, 350)
        XCTAssertEqual(data.bands.first(where: { $0.kind == .unmeasured })?.name, "검사 대기·미분류")
        XCTAssertEqual(data.bands.reduce(0) { $0 + $1.bytes }, 500)
    }

    func testInconsistentMeasurementsNeverPretendToBePhysicalPartition() {
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 100, availableBytes: 40),
                                        areas: [area("/Users", 80)])
        XCTAssertTrue(data.isMeasuredOnly)
        XCTAssertEqual(data.total, 80)
        XCTAssertEqual(data.bands.count, 1)
        XCTAssertEqual(data.bands[0].bytes, 80)
    }

    func testUnknownCapacityUsesMeasuredOnlyAndEmptyIsFinite() {
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 0, availableBytes: 0), areas: [area("/Users", 10)])
        XCTAssertTrue(data.isMeasuredOnly)
        XCTAssertEqual(data.total, 10)
        let empty = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 0, availableBytes: 0), areas: [])
        XCTAssertEqual(empty.total, 0)
        XCTAssertTrue(empty.bands.isEmpty)
        XCTAssertTrue(CoreStorageBreakdown.tickStep(total: 0, height: 320).isFinite)
    }

    func testGroupingPreservesAllBytesAndSelectablePaths() {
        let areas = (1...20).map { area("/area\($0)", Int64($0)) }
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 500, availableBytes: 100), areas: areas)
        XCTAssertEqual(data.bands.count, 7)
        XCTAssertEqual(data.bands.last?.kind, .grouped)
        XCTAssertEqual(Set(data.bands.flatMap(\.areas).map(\.path)), Set(areas.map(\.path)))
        XCTAssertEqual(data.bands.reduce(0) { $0 + $1.bytes }, 500)
    }

    func testNoMinimumBandHeightDistortsTinyMeasurements() {
        let data = CoreStorageBreakdown(volume: VolumeUsage(totalBytes: 1000, availableBytes: 0),
                                        areas: [area("/Users", 999), area("/Library", 1)])
        XCTAssertEqual(data.bands.first(where: { $0.id == "/Library" })!.bytes / data.total, 0.001)
    }

    func testLabelCollisionResolutionStaysInsideChart() {
        for ideal in [[1.0, 2, 3, 4, 5, 6, 7], [310.0, 311, 312, 313, 314, 315, 316], [1.0, 120, 121, 122, 123, 280, 315]] {
            let centers = CoreStorageBreakdown.labelCenters(ideal: ideal, height: 316)
            XCTAssertGreaterThanOrEqual(centers.first!, 20)
            XCTAssertLessThanOrEqual(centers.last!, 296)
            for i in 1..<centers.count { XCTAssertGreaterThanOrEqual(centers[i] - centers[i - 1], 40) }
        }
    }

    func testTickDensityAdaptsToCapacityAndHeight() {
        for total in [500_000_000.0, 436_000_000_000, 8_000_000_000_000] {
            let step = CoreStorageBreakdown.tickStep(total: total, height: 316)
            XCTAssertGreaterThan(step, 0)
            XCTAssertLessThanOrEqual(ceil(total / step), 6)
        }
    }

    func testIdentityAndOrderingRemainStableWhenSizesChange() {
        let volume = VolumeUsage(totalBytes: 1000, availableBytes: 100)
        let first = CoreStorageBreakdown(volume: volume, areas: [area("/Users", 200), area("/Library", 100)])
        let second = CoreStorageBreakdown(volume: volume, areas: [area("/Users", 100), area("/Library", 200)])
        XCTAssertEqual(first.bands.map(\.id), second.bands.map(\.id))
        XCTAssertEqual(first.bands.map(\.texture), second.bands.map(\.texture))
    }

    @MainActor
    func testRenderCorePanelPreviews() throws {
        guard ProcessInfo.processInfo.environment["STRATA_RENDER_PREVIEWS"] == "1" else {
            throw XCTSkip("Opt-in local visual review: STRATA_RENDER_PREVIEWS=1 swift test")
        }
        let gb: Int64 = 1_000_000_000
        let areas = [area("/Users", 190 * gb, name: "사용자"), area("/Applications", 48 * gb, name: "응용 프로그램"),
                     area("/Library", 21 * gb, name: "공용 라이브러리"), area("/System", gb, name: "시스템 데이터"),
                     area("/private", gb / 2, name: "시스템 및 임시 데이터"), area("/opt", gb / 4), area("/usr", gb / 4)]
        func snapshot(_ volume: VolumeUsage) -> ScanSnapshot {
            ScanSnapshot(volume: volume, volumeAreas: areas,
                         diskAccess: DiskAccessReport(state: .limited, checkedPaths: [], deniedPaths: []),
                         diagnostics: DeveloperDiagnostics(docker: DockerDiagnostic(state: .available, resources: []),
                                                           xcode: XcodeDiagnostic(state: .available, runtimes: [], deviceCount: 0, unavailableDeviceCount: 0)),
                         projectArtifacts: ProjectArtifactReport(scannedRoots: [], artifacts: [], inaccessibleItemCount: 0),
                         usages: [], startedAt: Date(), finishedAt: Date())
        }
        let normal = snapshot(VolumeUsage(totalBytes: 436 * gb, availableBytes: 140 * gb, physicalAvailableBytes: 123 * gb))
        let mismatch = snapshot(VolumeUsage(totalBytes: 200 * gb, availableBytes: 100 * gb))
        let scenarios: [(String, ScanSnapshot?, ColorScheme)] = [("dark", normal, .dark), ("light", normal, .light),
                                                                 ("mismatch", mismatch, .dark), ("empty", nil, .dark)]
        let output = URL(fileURLWithPath: "/private/tmp/strata-core-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func render<V: View>(_ view: V, name: String, size: CGSize, scheme: ColorScheme) throws {
            // ImageRenderer omits native ScrollView/Menu content. Render the actual AppKit host instead.
            let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
            host.frame = CGRect(origin: .zero, size: size)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appending(path: "\(name).png"))
            window.contentView = nil
        }
        for (name, value, scheme) in scenarios {
            let view = CoreSamplePanel(snapshot: value, selectedPath: "/Library", hasAnimated: true,
                                       didAnimate: {}, select: { _ in })
                .frame(width: 220, height: 600).environment(\.colorScheme, scheme)
            try render(view, name: name, size: CGSize(width: 220, height: 600), scheme: scheme)
        }
        for scheme in [ColorScheme.dark, .light] {
            for (name, bytes, errors) in [("measured", gb / 2, 0), ("unavailable", Int64(0), 1), ("empty", Int64(0), 0)] {
                let trash = VolumeAreaUsage(name: "휴지통", path: "/Users/example/.Trash", symbol: "trash",
                    allocatedBytes: bytes, inaccessibleItemCount: errors, inaccessiblePaths: [], isTrash: true)
                let value = ScanSnapshot(volume: normal.volume, volumeAreas: normal.volumeAreas + [trash],
                    diskAccess: normal.diskAccess, diagnostics: normal.diagnostics, projectArtifacts: normal.projectArtifacts,
                    usages: normal.usages, startedAt: normal.startedAt, finishedAt: normal.finishedAt)
                let view = CoreSamplePanel(snapshot: value, selectedPath: trash.path, hasAnimated: true,
                    didAnimate: {}, select: { _ in }).frame(width: 220, height: 600)
                try render(view, name: "trash-\(name)-\(scheme == .dark ? "dark" : "light")",
                           size: CGSize(width: 220, height: 600), scheme: scheme)
            }
        }
        for scheme in [ColorScheme.dark, .light] {
            let welcome = VStack(spacing: 0) {
                StrataHeader(appearance: .constant("dark"), isBusy: false, scan: {}, showsScan: false)
                Divider()
                HStack(spacing: 0) {
                    CoreSamplePanel(snapshot: nil, selectedPath: nil, hasAnimated: false, didAnimate: {}, select: { _ in })
                    ScanWelcomeView(scan: {})
                }
            }
            .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
            .frame(width: 1040, height: 680)
            try render(welcome, name: scheme == .dark ? "welcome-dark" : "welcome-light",
                       size: CGSize(width: 1040, height: 680), scheme: scheme)
        }
        let actions = [
            CleanupAction(id: "build", kind: .docker(resourceType: "Build Cache"), title: "Docker 빌드 캐시",
                          detail: "미리보기 데이터", baselineBytes: 23 * gb, estimatedBytes: 23 * gb,
                          safety: .safe, executionPreview: "docker builder prune"),
            CleanupAction(id: "runtime", kind: .simulatorRuntime(identifier: "preview"), title: "iOS 시뮬레이터 런타임",
                          detail: "미리보기 데이터", baselineBytes: 12 * gb, estimatedBytes: 12 * gb,
                          safety: .caution, executionPreview: "미리보기"),
            CleanupAction(id: "volume", kind: .docker(resourceType: "Local Volumes"), title: "Docker 볼륨",
                          detail: "미리보기 데이터", baselineBytes: gb, estimatedBytes: gb,
                          safety: .dangerous, executionPreview: "실행 차단")
        ]
        let sampleRun = CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
            availableBytesBefore: 100 * gb, availableBytesAfter: 101 * gb,
            results: [
                .init(actionID: "example", title: "Strata · SwiftPM 빌드", status: .succeeded, message: "휴지통으로 이동했습니다. 다음 빌드에서 다시 생성됩니다."),
                .init(actionID: "failed", title: "사용하지 않는 Docker 이미지", status: .failed, message: "Docker 데몬에 연결할 수 없습니다. Docker 실행 상태를 확인한 뒤 다시 시도하세요."),
                .init(actionID: "skipped", title: "웹 프로젝트 · Node.js 의존성", status: .skipped, message: "검증 후 항목이 변경되어 건너뛰었습니다. 다시 스캔하고 확인해 주세요.")])
        var diagnosed = normal
        diagnosed.spaceDiagnostics = SpaceDiagnosticReport(facts: ["데이터 볼륨 스냅샷: 0개 확인", "같은 컨테이너의 다른 볼륨 · System: 13 GB"],
            unavailable: ["시스템 볼륨 스냅샷 확인 불가 (0개라는 의미가 아닙니다)."])
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            let interpretedVolume = VolumeUsage(totalBytes: 500 * gb, availableBytes: 110 * gb,
                physicalAvailableBytes: 100 * gb, volumeUUID: "fixture-data")
            let interpretedReport = SpaceDiagnosticReport(containerUsage: .init(containerID: "disk3", dataVolumeID: "disk3s5",
                dataVolumeUUID: "fixture-data", capacityBytes: 500 * gb, freeBytes: 100 * gb, dataUsedBytes: 360 * gb,
                otherVolumes: [
                    .init(id: "system", name: "Macintosh HD", roles: ["System"], usedBytes: 14 * gb),
                    .init(id: "boot", name: "Preboot", roles: ["Preboot"], usedBytes: 11 * gb),
                    .init(id: "recovery", name: "Recovery", roles: ["Recovery"], usedBytes: 2 * gb),
                    .init(id: "vm", name: "VM", roles: ["VM"], usedBytes: 8 * gb)]))
            let interpreted = ScanSnapshot(volume: interpretedVolume,
                volumeAreas: [area("/Users", 190 * gb, name: "사용자"),
                    area("/.Spotlight-V100", 59 * gb, name: "Spotlight 검색 데이터"),
                    area("/System", 50 * gb, name: "시스템 폴더"), area("/Library", 20 * gb, name: "공용 라이브러리"),
                    area("/Applications", 24 * gb, name: "앱 폴더"),
                    .init(name: "휴지통", path: "/Users/me/.Trash", symbol: "trash", allocatedBytes: 2 * gb,
                          inaccessibleItemCount: 0, inaccessiblePaths: [], isTrash: true)],
                diskAccess: normal.diskAccess, diagnostics: normal.diagnostics, projectArtifacts: normal.projectArtifacts,
                usages: [], startedAt: normal.startedAt, finishedAt: normal.finishedAt, spaceDiagnostics: interpretedReport)
            try render(CoreSamplePanel(snapshot: interpreted, selectedPath: nil, hasAnimated: true, didAnimate: {}, select: { _ in }),
                       name: "accounting-core-\(suffix)", size: CGSize(width: 220, height: 700), scheme: scheme)
            try render(SpaceDiagnosticsView(snapshot: interpreted).padding(24)
                .frame(width: 680, height: 330, alignment: .topLeading).background(StrataTheme.base),
                       name: "accounting-card-\(suffix)", size: CGSize(width: 680, height: 330), scheme: scheme)
            try render(SpaceDiagnosticDetailsView(snapshot: interpreted), name: "accounting-details-\(suffix)",
                       size: CGSize(width: 640, height: 660), scheme: scheme)
            try render(AdministratorScanView(start: {}), name: "administrator-scan-\(suffix)",
                       size: CGSize(width: 510, height: 530), scheme: scheme)
            try render(VolumeBasisView(usage: .init(totalBytes: 494_000_000_000, availableBytes: 120_000_000_000,
                physicalAvailableBytes: 107_000_000_000, importantAvailableBytes: 120_000_000_000)),
                name: "volume-basis-\(suffix)", size: CGSize(width: 420, height: 500), scheme: scheme)
            try render(MeasurementStatusView(permission: .available, unreadableCount: 223)
                .font(.system(size: 13)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(StrataTheme.raised), name: "measurement-status-\(suffix)",
                size: CGSize(width: 620, height: 100), scheme: scheme)
            for (name, state) in [("available", DiskAccessState.available), ("limited", DiskAccessState.limited)] {
                try render(PermissionOnboardingView(report: .init(state: state, checkedPaths: [], deniedPaths: []),
                    isChecking: false, recheckedAt: Date(), hasExistingScan: true, recheck: {}, proceed: {}),
                    name: "permission-\(name)-\(suffix)", size: CGSize(width: 596, height: 760), scheme: scheme)
            }
            try render(ScanActivityView(progress: nil, startedAt: Date().addingTimeInterval(-125), cancel: {})
                .foregroundStyle(StrataTheme.primary).background(StrataTheme.base), name: "scan-timer-\(suffix)",
                size: CGSize(width: 820, height: 500), scheme: scheme)
            try render(ScanDurationView(startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 125))
                .padding(20).background(StrataTheme.base), name: "scan-duration-\(suffix)",
                size: CGSize(width: 420, height: 100), scheme: scheme)
            try render(SpaceDiagnosticDetailsView(snapshot: diagnosed), name: "diagnostics-details-\(suffix)",
                       size: CGSize(width: 640, height: 660), scheme: scheme)
            try render(CleanupHistoryView(history: [sampleRun]), name: "history-\(suffix)",
                       size: CGSize(width: 760, height: 620), scheme: scheme)
            let decrease = CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
                availableBytesBefore: 120764948480, availableBytesAfter: 120764207104,
                results: [.init(actionID: "trash-example", title: "프로젝트 빌드 산출물", status: .succeeded,
                                message: "휴지통으로 이동했습니다: /example", method: .trash)], spaceMeasurementVersion: 1)
            let unknown = CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
                availableBytesBefore: nil, availableBytesAfter: nil, results: [], spaceMeasurementVersion: 1)
            try render(CleanupHistoryView(history: [decrease, unknown]), name: "history-change-\(suffix)",
                       size: CGSize(width: 760, height: 620), scheme: scheme)
            try render(ScrollView { SpaceDiagnosticsView(snapshot: diagnosed).padding(24) }
                .foregroundStyle(StrataTheme.primary).background(StrataTheme.base), name: "diagnostics-\(suffix)",
                size: CGSize(width: 760, height: 620), scheme: scheme)
            let local = CleanupAction(id: "local", kind: .projectArtifact(path: "/Users/example/project/.build"),
                title: "프로젝트 · SwiftPM 빌드", detail: "미리보기", baselineBytes: gb, estimatedBytes: gb,
                safety: .safe, executionPreview: "휴지통으로 이동", createdAt: Date(), modifiedAt: Date(), accessedAt: Date())
            try render(CleanupPlanView(actions: actions + [local], selectedIDs: ["local", "hidden"], selectedBytes: gb,
                results: [:], isRunning: false, isExecuting: false, canExecute: false, latestRun: nil,
                toggle: { _ in }, setGroupSelected: { _, _ in }, runDryRun: {}, executeCleanup: {}, selectedArea: "/Users")
                .foregroundStyle(StrataTheme.primary).background(StrataTheme.base), name: "scoped-\(suffix)",
                size: CGSize(width: 820, height: 720), scheme: scheme)
        }
        for scheme in [ColorScheme.dark, .light] {
            let view = VStack(spacing: 0) {
                StrataHeader(appearance: .constant("dark"), isBusy: false, scan: {})
                Divider()
                HStack(spacing: 0) {
                    CoreSamplePanel(snapshot: normal, selectedPath: "/Library", hasAnimated: true, didAnimate: {}, select: { _ in })
                    CleanupPlanView(actions: actions, selectedIDs: ["build"], selectedBytes: 23 * gb,
                                    results: [:], isRunning: false, isExecuting: false, canExecute: false,
                                    latestRun: nil, toggle: { _ in }, setGroupSelected: { _, _ in },
                                    runDryRun: {}, executeCleanup: {},
                                    overview: AnyView(VStack(alignment: .leading, spacing: 8) {
                                        Text("내 저장공간").font(.title2.bold())
                                        Text("정리 후보 용량 · 추정").font(.caption)
                                        Text("35 GB").font(.system(size: 34, weight: .semibold, design: .monospaced))
                                        VolumeCard(usage: normal.volume)
                                    }))

                }
            }
            .font(.system(size: 13)).foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
            .frame(width: 1040, height: 720)
            try render(view, name: scheme == .dark ? "cleanup-dark" : "cleanup-light",
                       size: CGSize(width: 1040, height: 720), scheme: scheme)
        }
        let progress = ScanProgress(startedAt: Date().addingTimeInterval(-45), phase: "저장공간 검사",
                                    currentPath: "/Users/example/Library/Caches", visitedItemCount: 124_832,
                                    completedAreaCount: 3, totalAreaCount: 8, volume: normal.volume,
                                    areas: [area("/Applications", 48 * gb, name: "응용 프로그램"),
                                            area("/Users", 65 * gb, name: "사용자")])
        let scanning = VStack(spacing: 0) {
            StrataHeader(appearance: .constant("dark"), isBusy: true, scan: {})
            Divider()
            HStack(spacing: 0) {
                CoreSamplePanel(snapshot: nil, progress: progress, selectedPath: nil, hasAnimated: true,
                                didAnimate: {}, select: { _ in })
                ScanActivityView(progress: progress)
            }
        }
        .font(.system(size: 13)).foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
        .frame(width: 1040, height: 720)
        try render(scanning, name: "scanning", size: CGSize(width: 1040, height: 720), scheme: .dark)
        for state in [DiskAccessState.limited, .available] {
            let permission = PermissionOnboardingView(
                report: DiskAccessReport(state: state, checkedPaths: [], deniedPaths: []),
                isChecking: false, recheck: {}, proceed: {})
            try render(permission, name: state == .limited ? "permission-limited" : "permission-available",
                       size: CGSize(width: 540, height: 540), scheme: .dark)
        }
        let emptyPlan = CleanupPlanView(actions: [], selectedIDs: [], selectedBytes: 0,
                                        results: [:], isRunning: false, isExecuting: false, canExecute: false,
                                        latestRun: nil, toggle: { _ in }, setGroupSelected: { _, _ in },
                                        runDryRun: {}, executeCleanup: {})
            .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
        try render(emptyPlan, name: "empty-plan", size: CGSize(width: 820, height: 600), scheme: .dark)
    }
}
