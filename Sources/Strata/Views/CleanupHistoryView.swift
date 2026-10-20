import SwiftUI

struct CleanupHistoryView: View {
    let history: [CleanupRunSummary]
    var warning: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("정리 이력").font(.system(size: 24, weight: .bold))
                    Text("최근 \(history.count)회 · 최신순 · 최대 50회 보관")
                        .font(.system(size: 13)).foregroundStyle(StrataTheme.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Text("닫기").font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
                    .buttonStyle(StrataSurfaceButtonStyle()).keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13)).foregroundStyle(StrataTheme.errorText)
                    .fixedSize(horizontal: false, vertical: true).padding(16)
            }
            if history.isEmpty {
                ContentUnavailableView("아직 정리한 내역이 없습니다", systemImage: "clock.arrow.circlepath",
                    description: Text("정리를 실행하면 날짜별 처리 결과를 여기에서 확인할 수 있습니다."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(history) { run in
                            CleanupHistoryRunCard(run: run, initiallyExpanded: run.id == history.first?.id)
                        }
                    }.padding(24)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("휴지통으로 옮긴 파일은 비우기 전까지 공간을 차지합니다.")
                    Text("이력은 정리 당시의 측정값입니다. 이후 휴지통을 비워도 갱신되지 않습니다.")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12)).foregroundStyle(StrataTheme.secondary)
            .padding(.horizontal, 24).padding(.vertical, 16).background(StrataTheme.raised)
        }
        .frame(width: 760, height: 620)
        .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
    }
}

private struct CleanupHistoryRunCard: View {
    let run: CleanupRunSummary
    @State private var expanded: Bool

    init(run: CleanupRunSummary, initiallyExpanded: Bool) {
        self.run = run
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(run.finishedAt.formatted(.dateTime.year().month().day()))
                                .font(.system(size: 17, weight: .semibold))
                            Text("\(run.finishedAt.formatted(date: .omitted, time: .shortened)) 완료 · \(run.results.count)개 항목")
                                .font(.system(size: 13)).foregroundStyle(StrataTheme.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("디스크 여유 공간 변화").font(.system(size: 12)).foregroundStyle(StrataTheme.secondary)
                            Text(run.spaceChangeText)
                                .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                                .foregroundStyle((run.spaceChangeBytes ?? 0) > 0 ? StrataTheme.accentText : StrataTheme.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        badge(.succeeded, count: run.succeededCount)
                        badge(.failed, count: run.failedCount)
                        badge(.skipped, count: run.results.filter { $0.status == .skipped }.count)
                        Spacer()
                        Text(expanded ? "접기" : "상세 보기").font(.system(size: 12))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    if run.movedToTrashCount > 0 {
                        Label("휴지통 이동 \(run.movedToTrashCount)개 · 이동만으로 공간이 확보되지는 않습니다.", systemImage: "trash")
                            .font(.system(size: 13)).foregroundStyle(StrataTheme.infoText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "펼쳐짐" : "접힘")
            .accessibilityHint("날짜와 결과 영역 어디든 눌러 상세 내역을 펼치거나 접습니다.")
            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("처리 항목").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(run.results.count)개").font(.system(size: 12)).foregroundStyle(StrataTheme.secondary)
                    }.padding(.bottom, 4)
                    if run.results.isEmpty {
                        Text("상세 처리 항목이 없습니다.").font(.system(size: 13))
                            .foregroundStyle(StrataTheme.secondary).padding(.vertical, 14)
                    }
                    ForEach(Array(run.results.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: 12) {
                            Label(status(item.status), systemImage: symbol(item.status))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(color(item.status)).frame(width: 76, alignment: .leading)
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .background(surface(item.status), in: RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(item.title).font(.system(size: 14, weight: .semibold))
                                Text(item.message).font(.system(size: 13))
                                    .foregroundStyle(StrataTheme.secondary).lineSpacing(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }.padding(.vertical, 14)
                    }
                    Divider()
                    HStack(alignment: .top) {
                        Text("정리 전후 여유 공간 · 반올림")
                        Spacer()
                        Text("\(run.measuredCapacity(run.availableBytesBefore)?.storageFormatted ?? "확인 불가") → \(run.measuredCapacity(run.availableBytesAfter)?.storageFormatted ?? "확인 불가")").monospacedDigit()
                    }
                    .font(.system(size: 12)).foregroundStyle(StrataTheme.secondary).padding(.top, 12)
                    Text(run.spaceChangeExplanation)
                        .font(.system(size: 12)).foregroundStyle(StrataTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    Text("시작 \(run.startedAt.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 12)).foregroundStyle(StrataTheme.secondary).padding(.top, 6)
                }.padding(18).background(StrataTheme.sunken.opacity(0.35))
            }
        }
        .background(StrataTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(StrataTheme.line, lineWidth: 1))
    }

    private func badge(_ value: CleanupExecutionStatus, count: Int) -> some View {
        Label("\(status(value)) \(count)", systemImage: symbol(value))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(count == 0 ? StrataTheme.secondary : color(value))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(count == 0 ? StrataTheme.sunken : surface(value), in: RoundedRectangle(cornerRadius: 5))
    }
    private func status(_ value: CleanupExecutionStatus) -> String {
        switch value { case .succeeded: "성공"; case .failed: "실패"; case .skipped: "건너뜀" }
    }
    private func symbol(_ value: CleanupExecutionStatus) -> String {
        switch value { case .succeeded: "checkmark.circle"; case .failed: "exclamationmark.circle"; case .skipped: "minus.circle" }
    }
    private func color(_ value: CleanupExecutionStatus) -> Color {
        switch value { case .succeeded: StrataTheme.successText; case .failed: StrataTheme.errorText; case .skipped: StrataTheme.warningText }
    }
    private func surface(_ value: CleanupExecutionStatus) -> Color {
        switch value { case .succeeded: StrataTheme.successSurface; case .failed: StrataTheme.errorSurface; case .skipped: StrataTheme.warningSurface }
    }
}
