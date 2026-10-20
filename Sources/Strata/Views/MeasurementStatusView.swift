import SwiftUI

struct MeasurementStatusView: View {
    let permission: DiskAccessState?
    let unreadableCount: Int
    var needsRescan = false

    nonisolated static func permissionText(_ state: DiskAccessState?) -> String {
        switch state {
        case .available: "보호 폴더 읽기 확인됨"
        case .limited: "일부 보호 폴더 접근 제한"
        default: "보호 폴더 읽기 확인 필요"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(Self.permissionText(permission), systemImage: permission == .available ? "checkmark.shield" : "lock.fill")
                .foregroundStyle(permission == .available ? StrataTheme.successText : StrataTheme.warningText)
            if unreadableCount > 0 {
                Label("일부 항목 측정 불가 · \(unreadableCount)개 경로", systemImage: "exclamationmark.circle")
                    .foregroundStyle(StrataTheme.warningText)
                    .help("시스템 영역의 접근 제한이나 읽기 오류가 포함됩니다. 전체 디스크 접근 권한 미승인을 뜻하지 않습니다.")
            }
            if needsRescan {
                Text("권한 재확인 완료 · 기존 결과는 다시 스캔해야 갱신됩니다")
                    .foregroundStyle(StrataTheme.infoText)
            }
        }
    }
}
