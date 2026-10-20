import Foundation

enum ToolchainCatalog {
    static let definitions: [ToolchainDefinition] = [
        .init(
            id: "docker", name: "Docker", symbol: "shippingbox.fill",
            relativePaths: ["Library/Containers/com.docker.docker", ".docker"],
            safety: .caution, reclaimability: 0.55,
            explanation: "이미지, 빌드 캐시, 컨테이너 디스크는 빠르게 커집니다. 볼륨은 사용자 데이터일 수 있습니다.",
            cleanupHint: "Docker의 상세 사용량을 확인한 뒤 빌드 캐시만 정리"
        ),
        .init(
            id: "xcode", name: "Xcode", symbol: "hammer.fill",
            relativePaths: ["Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator"],
            safety: .caution, reclaimability: 0.45,
            explanation: "DerivedData는 재생성할 수 있지만 아카이브와 시뮬레이터 런타임은 다시 받아야 합니다.",
            cleanupHint: "DerivedData와 사용할 수 없는 시뮬레이터부터 검토"
        ),
        .init(
            id: "node", name: "Node.js", symbol: "cube.fill",
            relativePaths: [".npm", ".pnpm-store", ".yarn", "Library/Caches/Yarn", "Library/Caches/node-gyp"],
            safety: .safe, reclaimability: 0.80,
            explanation: "패키지 매니저 캐시는 필요할 때 다시 다운로드할 수 있습니다.",
            cleanupHint: "각 패키지 매니저의 공식 cache clean 명령 사용"
        ),
        .init(
            id: "gradle", name: "Gradle", symbol: "cup.and.saucer.fill",
            relativePaths: [".gradle/caches", ".gradle/wrapper/dists"],
            safety: .safe, reclaimability: 0.75,
            explanation: "의존성과 빌드 캐시는 다음 빌드에서 다시 생성됩니다.",
            cleanupHint: "오래된 Gradle 캐시와 배포판 검토"
        ),
        .init(
            id: "android", name: "Android", symbol: "apps.iphone",
            relativePaths: ["Library/Android/sdk", ".android/avd", ".android/cache"],
            safety: .caution, reclaimability: 0.35,
            explanation: "SDK와 AVD는 다시 다운로드할 수 있지만 에뮬레이터 내부 데이터가 포함될 수 있습니다.",
            cleanupHint: "사용하지 않는 SDK 이미지와 AVD를 Android 도구에서 제거"
        ),
        .init(
            id: "homebrew", name: "Homebrew", symbol: "mug.fill",
            relativePaths: ["Library/Caches/Homebrew"],
            safety: .safe, reclaimability: 0.85,
            explanation: "다운로드 캐시는 다시 받을 수 있습니다. 설치된 패키지 자체는 이 항목에 포함하지 않습니다.",
            cleanupHint: "brew cleanup의 dry-run 결과 검토"
        ),
        .init(
            id: "python", name: "Python", symbol: "chevron.left.forwardslash.chevron.right",
            relativePaths: ["Library/Caches/pip", ".cache/pip", ".cache/uv"],
            safety: .safe, reclaimability: 0.85,
            explanation: "pip와 uv의 다운로드·빌드 캐시입니다.",
            cleanupHint: "pip 또는 uv의 공식 cache 명령 사용"
        ),
        .init(
            id: "cocoapods", name: "CocoaPods", symbol: "square.stack.3d.up.fill",
            relativePaths: ["Library/Caches/CocoaPods", ".cocoapods/repos"],
            safety: .safe, reclaimability: 0.70,
            explanation: "사양 저장소와 다운로드 캐시는 다시 동기화할 수 있습니다.",
            cleanupHint: "오래된 CocoaPods 캐시 검토"
        ),
        .init(
            id: "browser-test", name: "Cypress · Electron", symbol: "testtube.2",
            relativePaths: ["Library/Caches/Cypress", "Library/Caches/electron", "Library/Caches/electron-builder"],
            safety: .safe, reclaimability: 0.90,
            explanation: "테스트 브라우저와 Electron 바이너리 캐시는 다시 다운로드됩니다.",
            cleanupHint: "사용하지 않는 버전의 바이너리 캐시 제거"
        )
    ]

    static let excludedRelativePaths = [
        ".claude", ".codex", ".gemini", ".cursor", ".ollama",
        "Library/Application Support/Claude"
    ]
}
