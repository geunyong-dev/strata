import AppKit
import SwiftUI

struct PermissionOnboardingView: View {
    let report: DiskAccessReport?
    let isChecking: Bool
    var recheckedAt: Date? = nil
    var hasExistingScan = false
    let recheck: () -> Void
    let proceed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 36)).foregroundStyle(StrataTheme.accentText)
            Text("정확히 재려면 디스크를 볼 수 있어야 합니다").font(.title2.bold())
            Text("전체 디스크 접근 권한을 허용하면 보호된 폴더도 검사할 수 있습니다. 허용하지 않으면 일부 파일을 읽지 못해 미분류 공간이 커질 수 있습니다.")
            Text("시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 Strata를 추가하고 켜주세요. 목록에 없으면 + 버튼에서 실행 중인 앱을 선택하세요.")
                .foregroundStyle(StrataTheme.secondary)
            HStack {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("권한 설정 열기").padding(.horizontal, 12).padding(.vertical, 8)
                }.buttonStyle(.bordered)
                Button("앱 위치 보기") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if isChecking { ProgressView().controlSize(.small) }
                    Label(isChecking ? "읽기 권한 확인 중…" : recheckedAt != nil ? "재확인 완료" : "현재 확인 결과",
                          systemImage: report?.state == .available ? "checkmark.shield" : "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                }
                if !isChecking {
                    Text(PermissionFeedback.resultText(report?.state)).font(.system(size: 14))
                    if let recheckedAt {
                        Text("마지막 재확인 \(recheckedAt.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 13)).foregroundStyle(StrataTheme.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .foregroundStyle(report?.state == .available ? StrataTheme.successText : StrataTheme.warningText)
            .background(report?.state == .available ? StrataTheme.successSurface : StrataTheme.warningSurface,
                        in: RoundedRectangle(cornerRadius: 10))
            if hasExistingScan {
                Text("권한 재확인은 기존 검사 결과를 바꾸지 않습니다. 계속을 누른 뒤 저장공간을 다시 스캔해 주세요.")
                    .font(.system(size: 14)).foregroundStyle(StrataTheme.infoText)
            }
            if report?.state != .available {
                Text("권한을 허용했는데도 같다면 실행 중인 Strata를 추가했는지 확인하고, 앱을 완전히 종료한 뒤 다시 열어 주세요.")
                    .font(.system(size: 14)).foregroundStyle(StrataTheme.secondary)
            }
            HStack {
                Button(isChecking ? "확인 중…" : "권한 다시 확인", action: recheck).disabled(isChecking)
                Spacer()
                Button(action: proceed) {
                    Text(report?.state == .available ? "확인 완료 · 계속" : "제한된 상태로 계속")
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                    .buttonStyle(StrataPrimaryButtonStyle())
                    .disabled(isChecking)
            }
            Text("일부 보호 폴더의 읽기 가능 여부를 확인한 결과이며, 모든 파일의 접근을 보장하지 않습니다.")
                .font(.caption).foregroundStyle(StrataTheme.secondary)
        }
        .padding(28).frame(width: 540)
        .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
        .interactiveDismissDisabled()
    }
}

enum PermissionFeedback {
    static func resultText(_ state: DiskAccessState?) -> String {
        switch state {
        case .available: "확인한 보호 폴더를 읽을 수 있습니다. 계속 진행해 주세요."
        case .limited: "다시 확인이 필요한 보호 폴더가 있습니다. 읽기 접근이 제한되어 있습니다."
        case .unknown: "읽기 가능 여부를 확인할 수 있는 보호 폴더가 없어 권한 상태를 판단하지 못했습니다."
        case nil: "아직 확인 결과가 없습니다. 권한 다시 확인을 눌러 주세요."
        }
    }

    static func needsRescan(recheckedAt: Date?, scanFinishedAt: Date?) -> Bool {
        guard let recheckedAt, let scanFinishedAt else { return false }
        return recheckedAt > scanFinishedAt
    }
}
