import AppKit
import SwiftUI

struct InspectionDetails: View {
    let detail: String
    var command: String? = nil

    var body: some View {
        DisclosureGroup("자세히 보기") {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail).font(.caption.monospaced()).textSelection(.enabled)
                if let command {
                    DisclosureGroup("작업 방식 보기") {
                        HStack(alignment: .top) {
                            Text(command).font(.caption.monospaced()).textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            } label: { Label("복사", systemImage: "doc.on.doc") }
                            .accessibilityLabel("작업 내용 복사")
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.top, 8)
        }
        .font(.caption)
        .foregroundStyle(StrataTheme.secondary)
    }
}

extension CleanupAction {
    var consequence: String {
        switch kind {
        case .projectArtifact:
            "휴지통으로 옮깁니다. 비우기 전까지 복원할 수 있습니다."
        case .simulatorRuntime:
            "런타임을 제거합니다. 다시 사용하려면 다운로드해야 합니다."
        case let .docker(resourceType):
            switch resourceType {
            case "Build Cache": "캐시를 제거합니다. 다음 빌드가 더 오래 걸릴 수 있습니다."
            case "Images": "사용하지 않는 이미지를 제거합니다. 로컬 전용 이미지는 복원이 어려울 수 있습니다."
            case "Containers": "중지된 컨테이너와 내부 변경 사항이 사라집니다. 되돌릴 수 없습니다."
            default: "데이터가 사라질 수 있어 앱에서 실행하지 않습니다."
            }
        }
    }

    var removesImmediately: Bool {
        if case .projectArtifact = kind { return false }
        return true
    }
}
