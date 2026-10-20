import SwiftUI

struct DashboardView: View {
    @State private var model = DashboardViewModel()
    @State private var selectedAreaPath: String?
    @State private var hasAnimatedCore = false
    @State private var lastSnapshot: ScanSnapshot?
    @State private var accessReport: DiskAccessReport?
    @State private var showingPermission = false
    @State private var showingHistory = false
    @State private var showingAdministratorScan = false
    @State private var checkingPermission = false
    @State private var permissionRecheckedAt: Date?
    @AppStorage("strata.permissionReviewed") private var permissionReviewed = false
    @AppStorage("strata.appearance") private var appearance = "dark"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: ScanSnapshot? {
        if case let .loaded(value) = model.state { return value }
        return nil
    }

    private var busy: Bool { model.isScanning || model.isRunningDryRun || model.isExecutingCleanup }
    private var isIdle: Bool { if case .idle = model.state { true } else { false } }

    var body: some View {
        VStack(spacing: 0) {
            StrataHeader(appearance: $appearance, isBusy: busy, scan: requestScan, showsScan: !isIdle)
            Divider()
            HStack(spacing: 0) {
                CoreSamplePanel(
                    snapshot: model.isScanning ? nil : snapshot ?? lastSnapshot,
                    progress: model.scanProgress, selectedPath: selectedAreaPath,
                    hasAnimated: hasAnimatedCore, didAnimate: { hasAnimatedCore = true }
                ) { selectedAreaPath = $0 }
                VStack(spacing: 0) {
                    accessStatus
                    if let warning = model.scanLogWarning {
                        Text(warning).font(.callout).foregroundStyle(StrataTheme.warningText).padding(10)
                    }
                    if let notice = model.scanNotice {
                        Text(notice).font(.caption).padding(10)
                    }
                    Group {
                        switch model.state {
                        case .idle:
                            ScanWelcomeView(scan: requestScan)
                        case .scanning:
                            ScanActivityView(progress: model.scanProgress, startedAt: model.scanStartedAt,
                                             isCancelling: model.isCancellingScan, cancel: model.cancelScan)
                        case let .loaded(snapshot):
                            results(snapshot)
                        case let .failed(message):
                            ContentUnavailableView("스캔 실패", systemImage: "exclamationmark.triangle", description: Text(message))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .font(.system(size: 13)).monospacedDigit()
        .foregroundStyle(StrataTheme.primary).tint(StrataTheme.accentText)
        .background(StrataTheme.base)
        .preferredColorScheme(appearance == "system" ? nil : (appearance == "light" ? .light : .dark))
        .transaction { if reduceMotion { $0.animation = nil } }
        .onChange(of: snapshot?.finishedAt) { _, _ in
            if let snapshot { lastSnapshot = snapshot }
        }
        .task {
            await refreshAccess()
            if !permissionReviewed {
                if accessReport?.state == .available { permissionReviewed = true }
                else { showingPermission = true }
            }
        }
        .sheet(isPresented: $showingPermission) {
            PermissionOnboardingView(report: accessReport, isChecking: checkingPermission,
                recheckedAt: permissionRecheckedAt, hasExistingScan: snapshot != nil,
                recheck: { Task { await refreshAccess(isRecheck: true) } },
                proceed: { permissionReviewed = true; showingPermission = false })
        }
        .sheet(isPresented: $showingHistory) {
            CleanupHistoryView(history: model.cleanupHistory, warning: model.historyWarning)
        }
        .sheet(isPresented: $showingAdministratorScan) {
            AdministratorScanView { Task { await model.scan(includeAdministrator: true) } }
        }
        .navigationTitle("Strata").frame(minWidth: 1040, minHeight: 680)
    }

    private var accessStatus: some View {
        let needsRescan = PermissionFeedback.needsRescan(recheckedAt: permissionRecheckedAt, scanFinishedAt: snapshot?.finishedAt)
        let report = needsRescan ? accessReport : snapshot?.diskAccess ?? accessReport
        let unreadableCount = snapshot?.volumeAreas.reduce(0) { $0 + $1.inaccessibleItemCount } ?? 0
        return HStack(spacing: 8) {
            MeasurementStatusView(permission: report?.state, unreadableCount: unreadableCount, needsRescan: needsRescan)
            Spacer()
            if unreadableCount > 0 {
                Button { showingAdministratorScan = true } label: {
                    Label("정밀 검사", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered).disabled(busy)
                .help("관리자 승인 후 시스템 영역을 읽기 전용으로 다시 측정합니다.")
            }
            Button("정리 이력") { showingHistory = true }.buttonStyle(.plain)
            Button("권한 확인") { showingPermission = true }
                .buttonStyle(.plain).disabled(busy)
        }
        .font(.caption).foregroundStyle(StrataTheme.secondary)
        .padding(.horizontal, StrataLayout.contentInset).padding(.vertical, 10)
        .background(StrataTheme.raised)
    }

    private func requestScan() {
        guard !busy else { return }
        if !permissionReviewed && accessReport?.state != .available { showingPermission = true; return }
        Task { await model.scan() }
    }

    private func refreshAccess(isRecheck: Bool = false) async {
        guard !checkingPermission else { return }
        checkingPermission = true
        accessReport = await Task.detached { PermissionInspector().inspect() }.value
        if isRecheck { permissionRecheckedAt = Date() }
        checkingPermission = false
    }

    private func results(_ snapshot: ScanSnapshot) -> some View {
        CleanupPlanView(
            actions: model.cleanupActions, selectedIDs: model.selectedCleanupActionIDs,
            selectedBytes: model.selectedCleanupBytes, results: model.dryRunResults,
            isRunning: model.isRunningDryRun, isExecuting: model.isExecutingCleanup,
            canExecute: model.canExecuteCleanup, latestRun: model.cleanupHistory.first,
            toggle: model.toggleCleanupAction, setGroupSelected: { ids, selected in
                for level in SafetyLevel.allCases {
                    model.setCleanupGroupSelected(level, selected: selected, onlyIDs: Set(ids))
                }
            },
            runDryRun: { Task { await model.runDryRun() } },
            executeCleanup: { Task { await model.executeCleanup() } },
            overview: AnyView(overview(snapshot)), scrollTarget: selectedAreaPath, selectedArea: selectedAreaPath)
    }

    private func overview(_ snapshot: ScanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedAreaPath == nil ? "내 저장공간" : "선택한 영역").font(.system(size: 22, weight: .semibold))
                Spacer()
                if selectedAreaPath != nil {
                    Button("전체 공간 보기") { selectedAreaPath = nil }.buttonStyle(.plain)
                }
            }
            ScanDurationView(startedAt: snapshot.startedAt, finishedAt: snapshot.finishedAt)
            if let admin = snapshot.administratorScan {
                VStack(alignment: .leading, spacing: 6) {
                    Label(admin.message, systemImage: admin.status == .completed ? "checkmark.shield" : "info.circle")
                    if admin.status == .partial {
                        Text("추가로 확인한 공간 \(admin.additionalBytes.storageFormatted)")
                    }
                    Text("추가 측정량은 삭제 가능한 용량이 아닙니다. 남은 접근 제한은 전체 디스크 접근 미승인을 뜻하지 않습니다.")
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                }
                .font(.callout).foregroundStyle(StrataTheme.infoText)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).strataCard()
            }
            if let area = snapshot.volumeAreas.first(where: { $0.path == selectedAreaPath }) {
                VolumeAreaRow(area: area, maxBytes: area.allocatedBytes)
                Text(area.systemDataExplanation ?? (area.isTrash
                     ? "현재 사용자 휴지통입니다. 사용자 영역에서 분리해 중복 없이 측정하며, 휴지통 비우기는 실행하지 않습니다."
                     : "이 영역에 경로가 속한 정리 후보를 표시합니다. 위치 미확인 도구는 별도 목록으로 표시합니다."))
                    .font(.caption).foregroundStyle(StrataTheme.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("정리 후보 용량 · 추정").font(.callout).foregroundStyle(StrataTheme.secondary)
                    Text(model.cleanupActions.filter { $0.safety != .dangerous }.reduce(Int64(0)) { $0 + $1.estimatedBytes }.storageFormatted)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    Text("아래 목록에서 고르세요. 실제 확보 공간은 정리 방법에 따라 달라집니다.")
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                }
                VolumeCard(usage: snapshot.volume)
            }
            Text("\(snapshot.finishedAt.formatted(date: .abbreviated, time: .shortened)) 측정 · 정리 후 다시 스캔해 결과를 확인하세요.")
                .font(.caption).foregroundStyle(StrataTheme.secondary)
            DisclosureGroup("시스템·미분류 공간") {
                SpaceDiagnosticsView(snapshot: snapshot).padding(.top, 8)
            }.disclosureGroupStyle(FullWidthDisclosureStyle())
            DisclosureGroup("공간 사용 내역과 측정 근거") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("파일로 확인한 공간 \(snapshot.scannedVolumeBytes.storageFormatted)")
                        Spacer()
                        Text(snapshot.spaceAccounting.status == .inconsistent
                             ? "측정 차이 · 비교 보류" : "남은 측정 차이 \(snapshot.unaccountedBytes.storageFormatted)")
                    }.font(.caption)
                    if snapshot.spaceAccounting.status == .separated {
                        Text("별도 볼륨으로 확인한 공간 \(snapshot.spaceAccounting.knownVolumeBytes.storageFormatted) · 파일 합계와 중복 없이 구분")
                            .font(.callout).foregroundStyle(StrataTheme.infoText)
                    }
                    ForEach(snapshot.volumeAreas) { area in
                        VolumeAreaRow(area: area, maxBytes: snapshot.volumeAreas.first?.allocatedBytes ?? 0)
                        Divider()
                    }
                    DeveloperDiagnosticsView(diagnostics: snapshot.diagnostics)
                    ProjectArtifactsView(report: snapshot.projectArtifacts)
                    ForEach(snapshot.usages.filter { $0.allocatedBytes > 0 }) { usage in
                        UsageRow(usage: usage, maxBytes: snapshot.usages.first?.allocatedBytes ?? 0)
                    }
                    Text("영역과 도구별 용량은 겹칠 수 있어 서로 더하지 않습니다. 미분류 공간에는 접근 제한·스냅샷·공유 블록 등의 측정 차이가 영향을 줄 수 있습니다.")
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                }.padding(.top, 12)
            }
            .disclosureGroupStyle(FullWidthDisclosureStyle())
        }
    }
}

struct FullWidthDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "펼쳐짐" : "접힘")
            .accessibilityHint(configuration.isExpanded ? "눌러서 접기" : "눌러서 펼치기")

            if configuration.isExpanded {
                configuration.content
                    .disclosureGroupStyle(.automatic)
            }
        }
    }
}
