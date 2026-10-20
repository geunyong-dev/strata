import SwiftUI

struct ScanWelcomeView: View {
    let scan: () -> Void
    @State private var hovering = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(StrataTheme.accentText)
                    .frame(width: 64, height: 64)
                    .background(StrataTheme.accentSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text("저장공간 정리,\n먼저 스캔부터 시작하세요.")
                    .font(.system(size: 30, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("무엇이 공간을 차지하는지 확인하고,\n정리할 항목은 결과를 본 뒤 직접 고르세요.")
                    .font(.system(size: 15)).lineSpacing(4)
                    .foregroundStyle(StrataTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Button(action: scan) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                        Text("저장공간 스캔 시작")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .foregroundStyle(StrataTheme.actionForeground)
                    .background(hovering ? StrataTheme.actionHover : StrataTheme.actionFill, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { hovering = $0 }
                .accessibilityHint("저장공간을 읽기 전용으로 검사합니다. 파일을 삭제하지 않습니다.")
                Label("파일 삭제 없음 · 외부 전송 없음", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(StrataTheme.secondary)
            }
            .frame(maxWidth: 420)

            HStack(alignment: .top, spacing: 24) {
                step("01", "공간 측정", "사용량을 실시간으로 확인")
                step("02", "결과 살펴보기", "큰 영역과 정리 후보 확인")
                step("03", "직접 선택", "승인한 항목만 정리")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(StrataTheme.secondary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(StrataTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
