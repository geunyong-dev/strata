import Foundation

enum ProjectArtifactCatalog {
    static let definitions: [ProjectArtifactDefinition] = [
        .init(
            id: "node-modules", name: "Node.js 의존성", directoryNames: ["node_modules"],
            symbol: "shippingbox.fill", safety: .safe, reclaimability: 1,
            explanation: "package-lock, pnpm-lock 또는 yarn.lock을 이용해 다시 설치할 수 있습니다."
        ),
        .init(
            id: "next", name: "Next.js 빌드", directoryNames: [".next"],
            symbol: "globe", safety: .safe, reclaimability: 1,
            explanation: "다음 빌드에서 다시 생성되는 Next.js 산출물입니다."
        ),
        .init(
            id: "rust-target", name: "Rust 빌드", directoryNames: ["target"],
            symbol: "gearshape.2.fill", safety: .safe, reclaimability: 1,
            explanation: "Cargo가 다음 빌드에서 다시 생성하는 바이너리와 중간 산출물입니다."
        ),
        .init(
            id: "swift-build", name: "SwiftPM 빌드", directoryNames: [".build"],
            symbol: "swift", safety: .safe, reclaimability: 1,
            explanation: "Swift Package Manager가 다음 빌드에서 다시 생성하는 산출물입니다."
        ),
        .init(
            id: "python-venv", name: "Python 가상환경", directoryNames: [".venv", "venv"],
            symbol: "chevron.left.forwardslash.chevron.right", safety: .caution, reclaimability: 0.9,
            explanation: "의존성 선언이 최신인지 확인한 뒤 다시 만들 수 있는 가상환경입니다."
        ),
        .init(
            id: "build", name: "빌드 산출물", directoryNames: ["build", "dist", "out"],
            symbol: "hammer.fill", safety: .caution, reclaimability: 0.85,
            explanation: "일반적인 빌드 폴더지만 수동으로 저장한 결과물이 없는지 확인해야 합니다."
        ),
        .init(
            id: "cocoapods", name: "CocoaPods 의존성", directoryNames: ["Pods"],
            symbol: "square.stack.3d.up.fill", safety: .caution, reclaimability: 0.95,
            explanation: "Podfile.lock을 이용해 다시 설치할 수 있는 의존성입니다."
        ),
        .init(
            id: "project-cache", name: "프로젝트 캐시", directoryNames: [".turbo", ".parcel-cache", ".gradle", "coverage"],
            symbol: "bolt.horizontal.circle.fill", safety: .safe, reclaimability: 1,
            explanation: "빌드 및 테스트 도구가 다시 생성하는 프로젝트 단위 캐시입니다."
        )
    ]

    static let ignoredDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".claude", ".codex", ".gemini", ".cursor", ".ollama"
    ]
}
