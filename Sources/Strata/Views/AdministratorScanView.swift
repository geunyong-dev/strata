import SwiftUI

struct AdministratorScanView: View {
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("시스템 영역 정밀 검사", systemImage: "externaldrive.badge.checkmark")
                .font(.system(size: 23, weight: .semibold)).foregroundStyle(StrataTheme.accentText)
            Text("일반 검사에서 읽지 못한 시스템 영역을 관리자 권한으로 다시 측정합니다.")
                .font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                Label("파일 용량과 폴더 목록만 확인합니다", systemImage: "eye")
                Label("삭제하거나 시스템 권한을 바꾸지 않습니다", systemImage: "lock.shield")
                Label("백그라운드 상주 프로그램을 설치하지 않습니다", systemImage: "checkmark.circle")
            }.font(.system(size: 14)).padding(18).frame(maxWidth: .infinity, alignment: .leading).strataCard()
            Text("일반 검사 후 macOS 관리자 인증창이 열립니다. 추가 검사는 최대 약 3분이며, 일부 보호 영역은 여전히 읽지 못할 수 있습니다.")
                .font(.system(size: 14)).foregroundStyle(StrataTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("인증을 취소하면 일반 검사 결과를 유지합니다. 검사 중단 시 추가 검사도 종료 요청되며, 시스템 응답이 지연되면 종료까지 시간이 걸릴 수 있습니다.")
                .font(.system(size: 13)).foregroundStyle(StrataTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("정밀 검사 시작") { dismiss(); start() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28).frame(width: 510)
        .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
    }
}
