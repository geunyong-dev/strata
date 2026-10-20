import SwiftUI

struct ScanActivityView: View {
    let progress: ScanProgress?
    var startedAt: Date? = nil
    var isCancelling = false
    var cancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress?.phase ?? "스캔 준비 중").font(.system(size: 22, weight: .semibold))
                    Text(progress?.phase == "관리자 정밀 검사"
                         ? "일반 검사 결과를 유지한 채 추가 검사 중입니다. 완료 후 코어 시료에 반영합니다."
                         : "측정되는 내용을 왼쪽 코어 시료에 반영하고 있습니다.")
                        .foregroundStyle(StrataTheme.secondary)
                }
                Spacer()
                if let cancel {
                    Button(isCancelling ? "중단 중…" : "스캔 중단", action: cancel)
                        .disabled(isCancelling)
                }
            }
            if let start = startedAt ?? progress?.startedAt {
                ScanDurationView(startedAt: start)
            }
            if let progress {
                HStack(spacing: 32) {
                    metric("현재까지 측정", progress.measuredBytes.storageFormatted)
                    metric("볼륨 검사 항목", progress.visitedItemCount.formatted())
                    metric("완료한 측정 영역", "\(progress.completedAreaCount) / \(progress.totalAreaCount)")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("현재 작업").font(.caption).foregroundStyle(StrataTheme.secondary)
                    Text(progress.currentPath.isEmpty ? "검사 위치 확인 중…" : progress.currentPath)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(3).truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let idle = max(0, Int(context.date.timeIntervalSince(progress.updatedAt)))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("마지막 진행 갱신 \(idle)초 전")
                            if idle >= 15 {
                                Text("새 결과를 기다리고 있습니다. 파일 시스템이나 개발 도구의 응답이 지연될 수 있습니다.")
                            }
                        }
                        .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                }
                .padding(20).strataCard()
            }
            Spacer()
        }
        .padding(StrataLayout.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(StrataTheme.secondary)
            Text(value).font(.system(size: 20, weight: .medium, design: .monospaced))
        }
    }
}
