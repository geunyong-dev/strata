import SwiftUI

struct SpaceDiagnosticsView: View {
    let snapshot: ScanSnapshot
    @State private var showingDetails = false
    private var accounting: StorageSpaceAccounting { snapshot.spaceAccounting }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if accounting.status == .separated {
                amountRow("시스템·다른 볼륨", value: accounting.knownVolumeBytes.storageFormatted,
                          symbol: "internaldrive", color: StrataTheme.infoText)
                Divider()
            }
            amountRow("아직 설명되지 않은 공간",
                      value: accounting.status == .inconsistent ? "비교 보류" : accounting.unresolvedBytes.storageFormatted,
                      symbol: "questionmark.circle", color: StrataTheme.warningText)
            if accounting.status == .unavailable {
                Text("시스템 볼륨을 구분할 정보가 부족해, 기존 측정 차이를 그대로 표시합니다.")
                    .foregroundStyle(StrataTheme.secondary)
            }
            Text("시스템 공간과 측정 차이는 삭제 가능한 용량이 아닙니다.")
                .foregroundStyle(StrataTheme.secondary)
            Label(SpaceDiagnosticPresentation(snapshot: snapshot).guidance, systemImage: "info.circle")
                .foregroundStyle(StrataTheme.infoText)
            Button("자세히 알아보기") { showingDetails = true }
                .buttonStyle(.plain).foregroundStyle(StrataTheme.accentText)
                .padding(.vertical, 6)
        }
        .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
        .padding(18).background(StrataTheme.raised, in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showingDetails) { SpaceDiagnosticDetailsView(snapshot: snapshot) }
    }

    private func amountRow(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
            Spacer()
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
    }
}

struct SpaceDiagnosticPresentation {
    let snapshot: ScanSnapshot
    var unreadableCount: Int { snapshot.volumeAreas.reduce(0) { $0 + $1.inaccessibleItemCount } }
    var guidance: String {
        if snapshot.spaceAccounting.status == .inconsistent {
            return "측정값에 차이가 있습니다. 잠시 후 다시 스캔해 주세요."
        }
        if unreadableCount > 0 {
            return snapshot.diskAccess.state == .available
                ? "보호 폴더 읽기는 확인됐지만 일부 경로를 측정하지 못했습니다. 자세한 원인은 로그에 기록됩니다."
                : "읽지 못한 항목이 있습니다. 접근 권한을 확인한 뒤 다시 스캔해 주세요."
        }
        if snapshot.spaceDiagnostics == nil { return "다시 스캔하면 추가 진단을 확인할 수 있습니다." }
        if snapshot.spaceDiagnostics?.unavailable.isEmpty == false {
            return "일부 진단 정보를 확인하지 못했습니다. 잠시 후 다시 스캔해 주세요."
        }
        return "정리가 필요하면 ‘정리할 항목’에서 후보를 살펴보고 직접 선택해 주세요."
    }
}

struct SpaceDiagnosticDetailsView: View {
    let snapshot: ScanSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("시스템·미분류 공간 이해하기").font(.system(size: 24, weight: .semibold))
                    Text("이번 스캔에서 확인한 공간과 남은 측정 차이")
                        .font(.system(size: 15)).foregroundStyle(StrataTheme.secondary)
                }
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if snapshot.spaceAccounting.status == .separated {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("확인된 시스템·다른 볼륨").font(.system(size: 18, weight: .semibold))
                            ForEach(snapshot.spaceAccounting.volumes) { volume in
                                HStack {
                                    Text(volume.displayName)
                                    Spacer()
                                    Text(volume.usedBytes.storageFormatted).monospacedDigit()
                                }
                            }
                            Divider()
                            HStack {
                                Text("합계").fontWeight(.semibold)
                                Spacer()
                                Text(snapshot.spaceAccounting.knownVolumeBytes.storageFormatted).fontWeight(.semibold)
                            }
                        }.padding(18).background(StrataTheme.infoSurface, in: RoundedRectangle(cornerRadius: 10))
                        section("아직 설명되지 않은 공간 · \(snapshot.unaccountedBytes.storageFormatted)",
                                text: "파일로 측정한 공간과 위 볼륨을 구분하고도 남는 차이입니다. 접근 제한, 복원 기록, 파일 시스템 관리 정보 등이 영향을 줄 수 있습니다. 삭제 가능 용량을 뜻하지 않습니다.")
                    } else {
                        section("아직 나누지 못한 공간", text: snapshot.spaceAccounting.status == .inconsistent
                            ? "볼륨 정보와 파일 측정값이 맞지 않아 분류를 보류했습니다. 수치를 줄이거나 억지로 맞추지 않았습니다."
                            : "Mac의 사용량과 폴더 측정 합계 사이의 차이입니다. 같은 디스크의 볼륨 정보가 확인되면 시스템 공간을 따로 구분합니다.")
                    }
                    section("지금 무엇을 하면 되나요?", text: SpaceDiagnosticPresentation(snapshot: snapshot).guidance)
                    section("왜 차이가 생기나요?", text: "읽을 수 없는 파일, macOS가 보관하는 복원용 기록, 여러 파일이 함께 사용하는 저장 공간 등이 영향을 줄 수 있습니다. 스캔 중 파일이 바뀌어도 차이가 생깁니다.")
                    Label("Strata는 이 진단에서 시스템 파일이나 복원 기록을 삭제하지 않습니다.", systemImage: "shield")
                        .foregroundStyle(StrataTheme.infoText).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StrataTheme.infoSurface, in: RoundedRectangle(cornerRadius: 10))
                    DisclosureGroup("기술적인 측정 근거", isExpanded: $showsEvidence) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("읽지 못한 항목: \(SpaceDiagnosticPresentation(snapshot: snapshot).unreadableCount)개. 권한 제한뿐 아니라 파일 변경이나 읽기 오류도 포함합니다.")
                            Text("분리 전 차이: \(snapshot.spaceAccounting.rawGapBytes.storageFormatted) · 별도 볼륨 반영: \(snapshot.spaceAccounting.knownVolumeBytes.storageFormatted)")
                            if snapshot.spaceAccounting.status == .inconsistent {
                                Text("측정 기준이 일치하지 않아 별도 볼륨을 합산하지 않았습니다. 0 KB가 표시되더라도 정확한 일치를 뜻하지 않습니다.")
                            }
                            if let report = snapshot.spaceDiagnostics {
                                if !report.facts.isEmpty {
                                    Text("확인한 정보").fontWeight(.semibold)
                                    ForEach(Array(report.facts.enumerated()), id: \.offset) { _, fact in
                                        Text(fact).frame(maxWidth: .infinity, alignment: .leading)
                                        Divider()
                                    }
                                }
                                if !report.unavailable.isEmpty {
                                    Text("확인하지 못한 정보").fontWeight(.semibold)
                                    ForEach(Array(report.unavailable.enumerated()), id: \.offset) { _, message in Text(message) }
                                }
                                Text("\(report.checkedAt.formatted(date: .numeric, time: .shortened)) · 읽기 전용 진단")
                                    .foregroundStyle(StrataTheme.secondary)
                            } else { Text("추가 진단 결과가 없습니다.") }
                            Text("같은 데이터 볼륨 식별자와 컨테이너 용량, 보통 여유 공간 기준, 각 용량 합계가 맞는 경우에만 OS가 보고한 별도 볼륨을 구분합니다. 파일 측정에 이미 포함된 데이터 볼륨과 다른 컨테이너는 더하지 않습니다. 스냅샷 개수로 용량을 추정하지 않으며, 표시된 값은 회수 가능한 용량이 아닙니다.")
                            Link("Apple의 스냅샷 안내 보기", destination: URL(string: "https://support.apple.com/guide/disk-utility/dskuf82354dc/mac")!)
                        }.padding(.top, 14).textSelection(.enabled)
                    }.disclosureGroupStyle(FullWidthDisclosureStyle())
                }.padding(24)
            }
        }
        .font(.system(size: 15)).foregroundStyle(StrataTheme.primary)
        .lineSpacing(5).background(StrataTheme.base)
        .frame(width: 640, height: 660)
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
