import AppKit
import SwiftUI

struct VolumeCard: View {
    let usage: VolumeUsage
    @State private var showingBasis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("전체 저장공간").font(.headline)
                Button { showingBasis = true } label: {
                    Image(systemName: "info.circle").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(StrataTheme.accentText)
                .accessibilityLabel("용량 계산 기준 보기")
                .popover(isPresented: $showingBasis) { VolumeBasisView(usage: usage) }
                Spacer()
                Text("\(usage.displayedAvailableBytes.storageFormatted) \(usage.availabilityTitle)")
                    .fontWeight(.semibold)
            }
            ProgressView(value: usage.usedFraction).tint(StrataTheme.lichen)
            HStack {
                Text("\(usage.usedBytes.storageFormatted) 사용")
                Spacer()
                Text("전체 \(usage.totalBytes.storageFormatted)")
            }
            .font(.caption).foregroundStyle(StrataTheme.secondary)
        }
        .padding(16).strataCard()
    }
}

struct UsageRow: View {
    let usage: ToolchainUsage
    let maxBytes: Int64
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: usage.definition.symbol)
                        .frame(width: 34, height: 34)
                        .background(StrataTheme.glacier.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(usage.definition.name).fontWeight(.semibold)
                            SafetyBadge(level: usage.definition.safety)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(StrataTheme.glacier.opacity(0.16))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(StrataTheme.glacier)
                                        .frame(width: proxy.size.width * fraction)
                                }
                        }
                        .frame(height: 7)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(usage.allocatedBytes.storageFormatted).fontWeight(.semibold)
                        Text("약 \(usage.estimatedReclaimableBytes.storageFormatted) 회수 가능")
                            .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(StrataTheme.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(usage.definition.explanation)
                    Label(usage.definition.cleanupHint, systemImage: "lightbulb")
                        .foregroundStyle(StrataTheme.secondary)
                    if !usage.scannedPaths.isEmpty {
                        Text(usage.scannedPaths.joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .foregroundStyle(StrataTheme.tertiary)
                            .textSelection(.enabled)
                    }
                    if usage.inaccessibleItemCount > 0 {
                        Label("측정하지 못한 경로 \(usage.inaccessibleItemCount)개", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                }
                .font(.callout)
                .padding(.leading, 48)
                .transition(.identity)
            }
        }
        .padding(.vertical, 12)
    }

    private var fraction: Double {
        guard maxBytes > 0 else { return 0 }
        return min(1, Double(usage.allocatedBytes) / Double(maxBytes))
    }
}

struct DiskAccessCard: View {
    let report: DiskAccessReport

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 5) {
                Text(report.state.title).font(.headline)
                Text(report.state.explanation)
                    .font(.callout).foregroundStyle(StrataTheme.secondary)
                if !report.deniedPaths.isEmpty {
                    InspectionDetails(detail: report.deniedPaths.joined(separator: "\n"))
                }
            }
            Spacer()
            if report.state != .available {
                Button("시스템 설정 열기") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(18)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        .overlay {
            RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.18))
        }
    }

    private var icon: String {
        switch report.state {
        case .available: "checkmark.shield.fill"
        case .limited: "lock.trianglebadge.exclamationmark.fill"
        case .unknown: "questionmark.diamond.fill"
        }
    }

    private var color: Color {
        switch report.state {
        case .available: StrataTheme.successText
        case .limited: StrataTheme.warningText
        case .unknown: StrataTheme.infoText
        }
    }
}

struct VolumeAreaRow: View {
    let area: VolumeAreaUsage
    let maxBytes: Int64
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: area.symbol)
                        .foregroundStyle(StrataTheme.infoText)
                        .frame(width: 34, height: 34)
                        .background(StrataTheme.slate.opacity(0.11), in: RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(area.name).fontWeight(.semibold)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(StrataTheme.slate.opacity(0.13))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(StrataTheme.slate)
                                        .frame(width: proxy.size.width * fraction)
                                }
                        }
                        .frame(height: 7)
                    }
                    Spacer()
                    Text(area.capacityText).fontWeight(.semibold)
                    if area.inaccessibleItemCount > 0 {
                        Image(systemName: "lock.fill").foregroundStyle(StrataTheme.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(StrataTheme.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(area.path).font(.caption.monospaced()).textSelection(.enabled)
                    if let explanation = area.systemDataExplanation {
                        Text(explanation).foregroundStyle(StrataTheme.infoText)
                    }
                    Text("실제 할당 용량: \(area.capacityText)")
                    if let note = area.measurementNote { Text(note).foregroundStyle(StrataTheme.secondary) }
                    if area.inaccessibleItemCount > 0 {
                        Label("측정하지 못한 경로 \(area.inaccessibleItemCount)개", systemImage: "exclamationmark.circle")
                            .foregroundStyle(StrataTheme.secondary)
                        if !area.inaccessiblePaths.isEmpty {
                            Text(area.inaccessiblePaths.joined(separator: "\n"))
                                .font(.caption.monospaced())
                                .foregroundStyle(StrataTheme.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Label("접근 제한 없이 분석됨", systemImage: "checkmark.circle")
                            .foregroundStyle(StrataTheme.secondary)
                    }
                }
                .font(.callout)
                .padding(.leading, 48)
            }
        }
        .padding(.vertical, 11)
    }

    private var fraction: Double {
        guard maxBytes > 0 else { return 0 }
        return min(1, Double(area.allocatedBytes) / Double(maxBytes))
    }
}

struct DeveloperDiagnosticsView: View {
    let diagnostics: DeveloperDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("도구별 정밀 진단").font(.title2.bold())
                Text("개발 도구가 쌓아둔 공간과 다시 사용할 때 필요한 작업을 살펴보세요.")
                    .foregroundStyle(StrataTheme.secondary)
            }
            dockerCard
            xcodeCard
        }
    }

    private var dockerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            diagnosticHeader(
                title: "Docker",
                symbol: "shippingbox.fill",
                state: diagnostics.docker.state
            )
            switch diagnostics.docker.state {
            case .available:
                HStack(spacing: 24) {
                    diagnosticMetric("전체", diagnostics.docker.totalBytes.storageFormatted)
                    diagnosticMetric("회수 가능", diagnostics.docker.reclaimableBytes.storageFormatted)
                    Spacer()
                }
                ForEach(diagnostics.docker.resources) { resource in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(localizedDockerType(resource.type)).fontWeight(.medium)
                            Text("전체 \(resource.totalCount) · 사용 중 \(resource.activeCount)")
                                .font(.caption).foregroundStyle(StrataTheme.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(resource.sizeBytes.storageFormatted)
                            Text("\(resource.reclaimableBytes.storageFormatted) 회수 가능")
                                .font(.caption).foregroundStyle(StrataTheme.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            case let .unavailable(message), let .failed(message):
                diagnosticMessage(message)
            }
        }
        .diagnosticCard()
    }

    private var xcodeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            diagnosticHeader(
                title: "Xcode Simulator",
                symbol: "hammer.fill",
                state: diagnostics.xcode.state
            )
            switch diagnostics.xcode.state {
            case .available:
                HStack(spacing: 24) {
                    diagnosticMetric("런타임", diagnostics.xcode.runtimeBytes.storageFormatted)
                    diagnosticMetric("90일 미사용 후보", diagnostics.xcode.cleanupCandidateBytes.storageFormatted)
                    diagnosticMetric("시뮬레이터 기기", "\(diagnostics.xcode.deviceCount)개")
                    Spacer()
                }
                if diagnostics.xcode.unavailableDeviceCount > 0 {
                    Label("사용할 수 없는 기기 \(diagnostics.xcode.unavailableDeviceCount)개", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(StrataTheme.secondary)
                }
                ForEach(diagnostics.xcode.runtimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(runtime.platform) \(runtime.version)").fontWeight(.medium)
                                if runtime.isCleanupCandidate() {
                                    Label(runtime.lastUsedAt == nil ? "사용 기록 없음" : "90일 이상 미사용", systemImage: "clock.arrow.circlepath")
                                        .font(.caption2.bold())
                                        .help("사용 기록을 기준으로 한 표시입니다. 삭제 안전도를 보장하지 않습니다.")
                                        .foregroundStyle(StrataTheme.secondary)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(StrataTheme.secondary.opacity(0.12), in: Capsule())
                                }
                            }
                            Text("빌드 \(runtime.build) · \(runtime.state)")
                                .font(.caption).foregroundStyle(StrataTheme.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(runtime.sizeBytes.storageFormatted)
                            if let lastUsedAt = runtime.lastUsedAt {
                                Text("마지막 사용 \(lastUsedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(StrataTheme.secondary)
                            } else {
                                Text("사용 기록 없음").font(.caption).foregroundStyle(StrataTheme.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            case let .unavailable(message), let .failed(message):
                diagnosticMessage(message)
            }
        }
        .diagnosticCard()
    }

    private func diagnosticHeader(title: String, symbol: String, state: DiagnosticState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2).foregroundStyle(StrataTheme.accentText)
                .frame(width: 38, height: 38)
                .background(StrataTheme.glacier.opacity(0.11), in: RoundedRectangle(cornerRadius: 4))
            Text(title).font(.headline)
            Spacer()
            switch state {
            case .available:
                Label("연결됨", systemImage: "checkmark.circle.fill").foregroundStyle(StrataTheme.secondary)
            case .unavailable:
                Label("설치되지 않음", systemImage: "minus.circle.fill").foregroundStyle(StrataTheme.secondary)
            case .failed:
                Label("진단 실패", systemImage: "exclamationmark.triangle.fill").foregroundStyle(StrataTheme.secondary)
            }
        }
        .font(.callout)
    }

    private func diagnosticMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(StrataTheme.secondary)
        }
    }

    private func diagnosticMessage(_ message: String) -> some View {
        Text(message).font(.callout).foregroundStyle(StrataTheme.secondary).textSelection(.enabled)
    }

    private func localizedDockerType(_ type: String) -> String {
        switch type {
        case "Images": "이미지"
        case "Containers": "컨테이너"
        case "Local Volumes": "로컬 볼륨"
        case "Build Cache": "빌드 캐시"
        default: type
        }
    }
}

struct ProjectArtifactsView: View {
    let report: ProjectArtifactReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("프로젝트 빌드 산출물").font(.title2.bold())
                    Spacer()
                    if report.inaccessibleItemCount > 0 {
                        Label("접근 실패 \(report.inaccessibleItemCount)", systemImage: "lock.fill")
                            .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                }
                Text("프로젝트 관련 정리 후보입니다. 각 항목의 판정 근거를 확인해 주세요.")
                    .foregroundStyle(StrataTheme.secondary)
            }

            HStack(spacing: 24) {
                projectMetric("발견", "\(report.artifacts.count)개")
                projectMetric("사용 공간", report.totalBytes.storageFormatted)
                projectMetric("예상 회수 가능", report.estimatedReclaimableBytes.storageFormatted)
                Spacer()
            }

            if report.scannedRoots.isEmpty {
                ContentUnavailableView(
                    "프로젝트 폴더를 찾지 못했습니다",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Documents/workspace, Developer, Projects, Code, src 또는 workspace 폴더를 확인합니다.")
                )
                .frame(maxWidth: .infinity)
            } else if report.artifacts.isEmpty {
                ContentUnavailableView(
                    "빌드 산출물이 없습니다",
                    systemImage: "checkmark.circle",
                    description: Text(report.scannedRoots.joined(separator: "\n"))
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(report.artifacts.prefix(50)) { artifact in
                    HStack(spacing: 12) {
                        Image(systemName: artifact.definition.symbol)
                            .foregroundStyle(StrataTheme.amber)
                            .frame(width: 32, height: 32)
                            .background(StrataTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(artifact.projectName).fontWeight(.medium)
                                Text(artifact.definition.name).foregroundStyle(StrataTheme.secondary)
                                SafetyBadge(level: artifact.safety)
                            }
                            InspectionDetails(detail: artifact.path + "\n" + artifact.assessment)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(artifact.allocatedBytes.storageFormatted).fontWeight(.semibold)
                            if let modifiedAt = artifact.modifiedAt {
                                Text(modifiedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(StrataTheme.secondary)
                            }
                        }
                    }
                    .help(artifact.definition.explanation)
                    Divider()
                }
                if report.artifacts.count > 50 {
                    Text("가장 큰 항목 50개만 표시합니다. 나머지 \(report.artifacts.count - 50)개도 합계에는 포함됩니다.")
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                }
            }

            if !report.scannedRoots.isEmpty {
                InspectionDetails(detail: "검색 위치: \(report.scannedRoots.joined(separator: ", "))")
            }
        }
        .padding(20)
        .strataCard()
    }

    private func projectMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(StrataTheme.secondary)
        }
    }
}

struct CleanupPlanView: View {
    let actions: [CleanupAction]
    let selectedIDs: Set<String>
    let selectedBytes: Int64
    let results: [String: DryRunResult]
    let isRunning: Bool
    let isExecuting: Bool
    let canExecute: Bool
    let latestRun: CleanupRunSummary?
    let toggle: (String) -> Void
    let setGroupSelected: ([String], Bool) -> Void
    let runDryRun: () -> Void
    let executeCleanup: () -> Void
    var overview: AnyView = AnyView(EmptyView())
    var scrollTarget: String? = nil
    var selectedArea: String? = nil
    private var scopedActions: [CleanupAction] {
        guard let selectedArea else { return actions }
        return actions.filter { CleanupScope.contains($0, area: selectedArea) }
    }
    private var unlocatedActions: [CleanupAction] {
        selectedArea == nil ? [] : actions.filter(CleanupScope.isUnlocated)
    }
    private var hiddenSelectionCount: Int {
        let visible = Set((scopedActions + unlocatedActions).map(\.id))
        return selectedIDs.subtracting(visible).count
    }
    @State private var expandedDetails = Set<String>()
    @State private var isShowingConfirmation = false
    @State private var confirmationText = ""
    @State private var collapsedGroups = Set<String>()
    @FocusState private var isConfirmationFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        overview.id("overview")
                        planContent
                    }.padding(StrataLayout.contentInset)
                }
                .onChange(of: scrollTarget) { _, _ in reader.scrollTo("overview", anchor: .top) }
            }
            Divider()
            actionBar
        }
        .sheet(isPresented: $isShowingConfirmation) { confirmationSheet }
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedIDs.isEmpty ? "정리할 항목을 선택하세요" : "\(selectedIDs.count)개 선택 · 약 \(selectedBytes.storageFormatted)")
                    .fontWeight(.semibold)
                Text("예상 용량입니다. 휴지통 이동만으로 여유 공간이 늘지는 않습니다.")
                    .font(.caption).foregroundStyle(StrataTheme.secondary)
                if hiddenSelectionCount > 0 {
                    Text("다른 영역의 선택 \(hiddenSelectionCount)개 포함 · 전체 공간 보기에서 확인하세요.")
                        .font(.caption).foregroundStyle(StrataTheme.accentText)
                }
            }
            Spacer(minLength: 8)
            Button(action: runDryRun) {
                Label(isRunning ? "확인 중…" : "먼저 확인", systemImage: "checkmark.shield")
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(StrataSurfaceButtonStyle())
            .disabled(isRunning || isExecuting || selectedIDs.isEmpty)
            Button {
                confirmationText = ""
                isShowingConfirmation = true
            } label: {
                Text(isExecuting ? "정리 중…" : "선택 항목 정리")
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(StrataPrimaryButtonStyle())
            .disabled(isRunning || isExecuting || !canExecute)
        }
        .padding(.horizontal, StrataLayout.contentInset).padding(.vertical, 16)
        .background(StrataTheme.raised)
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("정리할 항목").font(.title2.bold())
                    Text("행 어디든 눌러 선택하세요. 먼저 확인은 파일을 지우지 않습니다.")
                        .foregroundStyle(StrataTheme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(scopedActions.count)개 후보").font(.title3.bold())
                    Text(selectedArea == nil ? "전체 정리 목록" : "선택 영역의 후보").font(.caption).foregroundStyle(StrataTheme.secondary)
                }
            }

            Label("먼저 상태를 확인한 뒤, 정리할 내용을 직접 승인합니다.", systemImage: "lock.shield.fill")
                .font(.callout).foregroundStyle(StrataTheme.accentText)

            if scopedActions.isEmpty {
                ContentUnavailableView(
                    "발견된 정리 후보가 없습니다",
                    systemImage: "checkmark.circle",
                    description: Text(selectedArea == nil ? "정리 가능한 후보가 발견되지 않았습니다." : "이 영역의 경로와 연결된 후보가 없습니다. 위치 미확인 후보는 아래 별도로 표시합니다.")
                )
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    Spacer()
                    Text("\(scopedActions.filter { selectedIDs.contains($0.id) }.count) / \(scopedActions.count)개 선택")
                        .font(.callout).foregroundStyle(StrataTheme.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(SafetyLevel.allCases, id: \.rawValue) { level in
                        let groupedActions = scopedActions.filter { $0.safety == level }
                        if !groupedActions.isEmpty {
                            cleanupGroup(level, actions: groupedActions)
                        }
                    }
                }


            }

            if !unlocatedActions.isEmpty {
                Text("위치 미확인 · Mac 전체 후보").font(.headline)
                Text("아래 도구의 저장 위치는 선택 영역과 연결하지 않았습니다.")
                    .font(.caption).foregroundStyle(StrataTheme.secondary)
                ForEach(SafetyLevel.allCases, id: \.rawValue) { level in
                    let group = unlocatedActions.filter { $0.safety == level }
                    if !group.isEmpty { cleanupGroup(level, actions: group) }
                }
            }
            if let latestRun {
                cleanupRunSummary(latestRun)
            }
        }
    }

    private func cleanupGroup(_ level: SafetyLevel, actions groupedActions: [CleanupAction]) -> some View {
        let count = groupedActions.filter { selectedIDs.contains($0.id) }.count
        let allSelected = count == groupedActions.count
        let groupKey = level.rawValue + (groupedActions.allSatisfy(CleanupScope.isUnlocated) ? ":global" : ":local")
        let collapsed = collapsedGroups.contains(groupKey)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { setGroupSelected(groupedActions.map(\.id), !allSelected) } label: {
                    HStack(spacing: 10) {
                        SafetyBadge(level: level)
                        Text("\(count) / \(groupedActions.count)개 선택")
                            .foregroundStyle(StrataTheme.secondary)
                        Spacer()
                        Text(allSelected ? "전체 해제" : "전체 선택")
                            .font(.caption.weight(.medium))
                        Image(systemName: allSelected ? "checkmark" : (count > 0 ? "minus" : "plus"))
                            .font(.system(size: 10, weight: .semibold)).frame(width: 12)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StrataSurfaceButtonStyle(selected: allSelected))
                .disabled(isRunning || isExecuting)
                .accessibilityLabel("\(level.title) 항목 \(allSelected ? "전체 해제" : "전체 선택")")
                .accessibilityValue("\(groupedActions.count)개 중 \(count)개 선택")

                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        if collapsed { collapsedGroups.remove(groupKey) }
                        else { collapsedGroups.insert(groupKey) }
                    }
                } label: {
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(StrataSurfaceButtonStyle())
                .accessibilityLabel("\(level.title) 항목 \(collapsed ? "펼치기" : "접기")")
                .accessibilityValue(collapsed ? "접힘" : "펼쳐짐")
                .help(collapsed ? "그룹 펼치기" : "그룹 접기")
            }
            if !collapsed {
                LazyVStack(spacing: 8) {
                    ForEach(groupedActions) { action in
                        cleanupActionRow(action)
                        Divider()
                    }
                }
            }
        }
    }

    private func cleanupActionRow(_ action: CleanupAction) -> some View {
        let selected = selectedIDs.contains(action.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
            Button { toggle(action.id) } label: {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? StrataTheme.accentText : StrataTheme.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title).fontWeight(.semibold)
                        Text(action.consequence).font(.callout).foregroundStyle(StrataTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        cleanupDates(action)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(action.estimatedBytes.storageFormatted).fontWeight(.semibold).monospacedDigit()
                        HStack(spacing: 4) {
                            if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                            Text(selected ? "선택됨" : "선택")
                        }
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRunning || isExecuting)
            .accessibilityLabel("\(action.title), \(action.estimatedBytes.storageFormatted), \(action.safety.title)")
            .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            .accessibilityHint("눌러서 선택 상태를 변경합니다. 정리는 실행하지 않습니다.")
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button {
                if expandedDetails.contains(action.id) { expandedDetails.remove(action.id) }
                else { expandedDetails.insert(action.id) }
            } label: {
                Image(systemName: expandedDetails.contains(action.id) ? "chevron.up" : "info.circle")
                    .frame(width: 40, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action.title) 상세 정보")
            }
            if expandedDetails.contains(action.id) {
                VStack(alignment: .leading, spacing: 8) {
                    if let evidence = action.candidateEvidence {
                        Text(evidence).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(action.detail).font(.caption).textSelection(.enabled)
                    InspectionDetails(detail: action.consequence, command: action.executionPreview)
                }.padding(.leading, 48).padding(.trailing, 14).padding(.bottom, 12)
            }

            if let result = results[action.id] {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: resultSymbol(result.status)).foregroundStyle(resultColor(result.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resultTitle(result.status)).fontWeight(.medium)
                        Text(result.message).font(.caption).foregroundStyle(StrataTheme.secondary)
                        if let currentBytes = result.currentBytes {
                            Text("현재 확인값: \(currentBytes.storageFormatted)")
                                .font(.caption).foregroundStyle(StrataTheme.secondary)
                        }
                    }
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .background(selected ? StrataTheme.accentSurface : Color.clear)
    }

    private func cleanupDates(_ action: CleanupAction) -> some View {
        let isFolder: Bool = if case .projectArtifact = action.kind { true } else { false }
        let note = isFolder
            ? "폴더 자체의 날짜 · 최근 접근은 실제 사용과 다르며 스캔·백업 등으로 바뀔 수 있습니다. 내부 파일의 마지막 활동을 뜻하지 않습니다."
            : "제공되는 사용 기록만 표시합니다. 확인 불가는 사용한 적이 없다는 뜻이 아닙니다."
        return VStack(alignment: .leading, spacing: 3) {
            dateLabel("생성", action.createdAt)
            dateLabel("수정", action.modifiedAt)
            dateLabel(isFolder ? "최근 접근" : "마지막 사용", isFolder ? action.accessedAt : action.lastUsedAt)
            Text(note).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption).foregroundStyle(StrataTheme.secondary)
        .help(note)
    }

    private func dateLabel(_ title: String, _ date: Date?) -> some View {
        Text("\(title) · \(date.map { $0.formatted(date: .numeric, time: .shortened) } ?? "확인 불가")")
            .monospacedDigit()
    }

    private func resultTitle(_ status: DryRunStatus) -> String {
        switch status {
        case .verified: "상태 확인 완료"
        case .changed: "스캔 이후 변경됨"
        case .unavailable: "현재 확인 불가"
        case .failed: "상태 확인 실패"
        }
    }

    private func resultSymbol(_ status: DryRunStatus) -> String {
        switch status {
        case .verified: "checkmark.circle.fill"
        case .changed: "arrow.triangle.2.circlepath.circle.fill"
        case .unavailable: "questionmark.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func resultColor(_ status: DryRunStatus) -> Color {
        switch status {
        case .verified: StrataTheme.successText
        case .changed: StrataTheme.warningText
        case .unavailable: StrataTheme.infoText
        case .failed: StrataTheme.errorText
        }
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: immediateActions.isEmpty ? "trash" : "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(immediateActions.isEmpty ? StrataTheme.primary : StrataTheme.irreversible)
            Text(immediateActions.isEmpty
                 ? "\(executableActions.count)개 항목을 휴지통으로 옮깁니다"
                 : "\(immediateActions.count)개 작업에서 데이터가 즉시 제거됩니다")
                .font(.system(size: 22, weight: .semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(executableActions) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title).fontWeight(.semibold)
                            Text(action.consequence).foregroundStyle(StrataTheme.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            Text("휴지통에 옮긴 파일은 휴지통을 비워야 공간이 늘어납니다. 다시 받아야 하는 파일의 다운로드 시간은 측정되지 않았습니다.")
                .font(.caption).foregroundStyle(StrataTheme.secondary)
            if selectedDangerousCount > 0 {
                Label("선택된 위험 작업 \(selectedDangerousCount)개는 실행하지 않습니다.", systemImage: "hand.raised.fill")
                    .foregroundStyle(StrataTheme.irreversible)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("계속하려면 ‘정리’를 입력하세요.").fontWeight(.medium)
                TextField("정리", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isConfirmationFocused)
            }
            HStack {
                Button("취소", role: .cancel) { isShowingConfirmation = false }
                Spacer()
                Button(immediateActions.isEmpty ? "휴지통으로 이동" : "선택한 \(executableActions.count)개 항목 정리", role: .destructive) {
                    isShowingConfirmation = false
                    executeCleanup()
                }
                .disabled(confirmationText != "정리" || executableActions.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
        .foregroundStyle(StrataTheme.primary)
        .background(StrataTheme.raised)
        .transaction { $0.animation = nil }
        .interactiveDismissDisabled(isExecuting)
        .onAppear {
            isConfirmationFocused = true
        }
    }

    private var executableActions: [CleanupAction] {
        actions.filter {
            selectedIDs.contains($0.id)
                && $0.safety != .dangerous
                && results[$0.id]?.status == .verified
        }
    }

    private var immediateActions: [CleanupAction] {
        executableActions.filter(\.removesImmediately)
    }

    private var selectedDangerousCount: Int {
        actions.filter { selectedIDs.contains($0.id) && $0.safety == .dangerous }.count
    }

    private func cleanupRunSummary(_ summary: CleanupRunSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("최근 정리 결과", systemImage: "clock.badge.checkmark.fill")
                    .font(.headline)
                Spacer()
                Text("여유 공간 변화 \(summary.spaceChangeText)")
                    .fontWeight(.semibold).foregroundStyle(StrataTheme.secondary)
            }
            Text("성공 \(summary.succeededCount) · 실패 \(summary.failedCount) · \(summary.finishedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(StrataTheme.secondary)
            if summary.movedToTrashCount > 0 {
                Label("휴지통 이동 \(summary.movedToTrashCount)개", systemImage: "trash")
                    .font(.callout).foregroundStyle(StrataTheme.infoText)
            }
            Text(summary.spaceChangeExplanation).font(.caption).foregroundStyle(StrataTheme.secondary)
            Text("휴지통 이동만으로는 공간이 비워지지 않습니다. 여유 공간 변화에는 다른 앱의 활동도 포함될 수 있습니다.")
                .font(.caption).foregroundStyle(StrataTheme.secondary)
            ForEach(summary.results) { result in
                HStack(alignment: .top) {
                    Image(systemName: executionSymbol(result.status))
                        .foregroundStyle(executionColor(result.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).fontWeight(.medium)
                        InspectionDetails(detail: result.message)
                    }
                }
            }
        }
        .padding(14)
        .background(StrataTheme.infoSurface, in: RoundedRectangle(cornerRadius: 4))
    }

    private func executionSymbol(_ status: CleanupExecutionStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .skipped: "forward.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private func executionColor(_ status: CleanupExecutionStatus) -> Color {
        switch status {
        case .succeeded: StrataTheme.successText
        case .skipped: StrataTheme.warningText
        case .failed: StrataTheme.errorText
        }
    }
}

private extension View {
    func diagnosticCard() -> some View {
        padding(18)
            .strataCard()
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        Label(level.title, systemImage: level.symbol)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(level.color)
            .background(level.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .help(level.detail)
    }
}
