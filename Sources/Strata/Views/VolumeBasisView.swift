import SwiftUI

struct VolumeBasisView: View {
    let usage: VolumeUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("용량이 다르게 보이는 이유").font(.system(size: 20, weight: .semibold))
            metric("현재 비어 있는 공간", value: usage.physicalAvailableBytes)
            metric("macOS가 보고한 사용 가능 공간", value: usage.importantAvailableBytes)
            Text(usage.physicalAvailableBytes != nil
                 ? "Strata의 사용량과 코어 시료는 현재 비어 있는 공간을 기준으로 계산합니다."
                 : "현재 빈 공간을 확인하지 못해 macOS가 보고한 사용 가능 공간을 대신 사용했습니다.")
            Text("사용 가능 공간에는 macOS가 필요할 때 비울 수 있는 공간이 포함될 수 있습니다. 설정 화면과 기준·확인 시점이 달라 숫자가 다를 수 있습니다.")
                .foregroundStyle(StrataTheme.secondary)
            Divider()
            Text("코어 시료는 폴더별 측정입니다.").fontWeight(.semibold)
            Text("‘앱 폴더’와 ‘시스템 폴더’는 실제 경로의 용량입니다. macOS 설정의 ‘응용 프로그램’·‘시스템 데이터’ 분류와는 다릅니다.")
                .foregroundStyle(StrataTheme.secondary)
        }
        .font(.system(size: 15)).lineSpacing(4).textSelection(.enabled)
        .padding(24).frame(width: 420)
        .foregroundStyle(StrataTheme.primary).background(StrataTheme.base)
    }

    private func metric(_ title: String, value: Int64?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value?.storageFormatted ?? "확인 불가").fontWeight(.semibold).monospacedDigit()
        }
    }
}
