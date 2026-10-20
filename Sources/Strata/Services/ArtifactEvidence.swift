import Foundation
import Darwin

struct ArtifactEvidence: Sendable {
    let isConfirmed: Bool
    let summary: String

    static let unconfirmed = ArtifactEvidence(isConfirmed: false,
        summary: "폴더 이름만 일치합니다. 다시 만들 수 있는 항목인지 확인되지 않아 기본 선택하지 않습니다.")

    /// Nearby regular files provide supporting evidence, never a guarantee that all contents are disposable.
    static func inspect(_ url: URL, definitionID: String) -> ArtifactEvidence {
        let parent = url.deletingLastPathComponent()
        func file(_ name: String, inside base: URL? = nil) -> Bool {
            var info = stat()
            return (base ?? parent).appending(path: name).path.withCString { lstat($0, &info) } == 0
                && info.st_mode & S_IFMT == S_IFREG && info.st_size > 0
        }
        // Bound reads and reject symbolic links rather than following arbitrary manifest paths.
        func package() -> [String: Any]? {
            let manifest = parent.appending(path: "package.json")
            let descriptor = manifest.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
            guard descriptor >= 0 else { return nil }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_size > 0, info.st_size <= 1_048_576 else { return nil }
            var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
            let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard count == bytes.count else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any]
        }
        func confirmed(_ files: String) -> ArtifactEvidence {
            .init(isConfirmed: true, summary: "판정 근거: \(files). 도구 관련 폴더로 판단했습니다. 직접 넣은 파일은 없는지 확인해 주세요.")
        }
        switch definitionID {
        case "node-modules":
            if package() != nil, let lock = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb"].first(where: { file($0) }) {
                return confirmed("상위 폴더의 package.json 및 \(lock)")
            }
        case "next":
            if let manifest = package(),
               ["dependencies", "devDependencies"].contains(where: { (manifest[$0] as? [String: Any])?["next"] is String }) {
                return confirmed("상위 package.json의 Next.js 의존성")
            }
        case "rust-target":
            if file("Cargo.toml") && file(".rustc_info.json", inside: url) {
                return confirmed("상위 Cargo.toml 및 내부 .rustc_info.json")
            }
        case "swift-build":
            if file("Package.swift") && file("workspace-state.json", inside: url) {
                return confirmed("상위 Package.swift 및 내부 workspace-state.json")
            }
        case "python-venv":
            if file("pyvenv.cfg", inside: url) {
                return .init(isConfirmed: false, summary: "내부 pyvenv.cfg로 가상환경임을 확인했습니다. 의존성을 다시 설치할 수 있는지는 직접 확인해야 합니다.")
            }
        case "cocoapods":
            if file("Podfile") && file("Podfile.lock") && file("Manifest.lock", inside: url) {
                return confirmed("상위 Podfile·Podfile.lock 및 내부 Manifest.lock")
            }
        case "build", "project-cache":
            let markers = ["package.json", "Package.swift", "Cargo.toml", "pyproject.toml", "build.gradle", "build.gradle.kts", "pom.xml"]
                .filter { file($0) }
            if !markers.isEmpty {
                return .init(isConfirmed: false, summary: "주변 프로젝트 파일: \(markers.joined(separator: ", ")). 이 폴더가 자동 생성된 것인지는 확정하지 못해 기본 선택하지 않습니다.")
            }
        default: break
        }
        return .unconfirmed
    }
}
