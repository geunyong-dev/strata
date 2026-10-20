import Foundation
import Darwin

actor CleanupExecutor {
    private let runner = CommandRunner()
    private let dryRunAnalyzer = CleanupDryRunAnalyzer()

    func execute(
        _ actions: [CleanupAction],
        allowedProjectRoots: [String]
    ) async -> CleanupRunSummary {
        let startedAt = Date()
        let availableBefore = availableVolumeBytes()
        let freshDryRun = await dryRunAnalyzer.preview(actions)
        var results: [CleanupExecutionItemResult] = []

        for action in actions {
            if action.safety == .dangerous {
                results.append(item(action, .skipped, "위험 작업은 Strata에서 자동 실행하지 않습니다."))
                continue
            }
            guard freshDryRun[action.id]?.status == .verified else {
                results.append(item(action, .skipped, "실행 직전 상태 확인을 통과하지 못했습니다."))
                continue
            }

            switch action.kind {
            case let .docker(resourceType):
                results.append(executeDocker(action, resourceType: resourceType))
            case let .simulatorRuntime(identifier):
                results.append(executeRuntime(action, identifier: identifier))
            case let .projectArtifact(path):
                results.append(executeProjectArtifact(
                    action,
                    path: path,
                    allowedProjectRoots: allowedProjectRoots
                ))
            }
        }

        return CleanupRunSummary(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: Date(),
            availableBytesBefore: availableBefore,
            availableBytesAfter: availableVolumeBytes(),
            results: results,
            spaceMeasurementVersion: 1
        )
    }

    private func executeDocker(
        _ action: CleanupAction,
        resourceType: String
    ) -> CleanupExecutionItemResult {
        guard let docker = dockerExecutable() else {
            return item(action, .failed, "Docker CLI를 찾을 수 없습니다.")
        }
        let arguments: [String]
        switch resourceType {
        case "Build Cache": arguments = ["builder", "prune", "-a", "--force"]
        case "Images": arguments = ["image", "prune", "-a", "--force"]
        case "Containers": arguments = ["container", "prune", "--force"]
        case "Local Volumes":
            return item(action, .skipped, "Docker 볼륨은 자동 정리 대상이 아닙니다.")
        default:
            return item(action, .failed, "허용되지 않은 Docker 작업입니다.")
        }

        let output = runner.run(executable: docker, arguments: arguments, timeout: 120)
        if output.timedOut {
            return item(action, .failed, "Docker 정리가 120초 시간 제한을 초과했습니다.")
        }
        guard output.exitCode == 0 else {
            return item(action, .failed, firstOutputLine(output, fallback: "Docker 정리에 실패했습니다."))
        }
        return item(action, .succeeded, firstOutputLine(output, fallback: "Docker 정리를 완료했습니다."))
    }

    private func executeRuntime(
        _ action: CleanupAction,
        identifier: String
    ) -> CleanupExecutionItemResult {
        guard UUID(uuidString: identifier) != nil else {
            return item(action, .failed, "유효하지 않은 Simulator 런타임 식별자입니다.")
        }
        let output = runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "runtime", "delete", identifier],
            timeout: 120
        )
        if output.timedOut {
            return item(action, .failed, "Simulator 정리가 120초 시간 제한을 초과했습니다.")
        }
        guard output.exitCode == 0 else {
            return item(action, .failed, firstOutputLine(output, fallback: "Simulator 런타임 삭제에 실패했습니다."))
        }
        return item(action, .succeeded, firstOutputLine(output, fallback: "Simulator 런타임을 제거했습니다."))
    }

    private func executeProjectArtifact(
        _ action: CleanupAction,
        path: String,
        allowedProjectRoots: [String]
    ) -> CleanupExecutionItemResult {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard CleanupTargetValidator.isAllowedProjectArtifact(
            url,
            allowedRoots: allowedProjectRoots.map { URL(fileURLWithPath: $0, isDirectory: true) }
        ) else {
            return item(action, .failed, "허용된 프로젝트 산출물 경로가 아닙니다.")
        }

        do {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            let destination = (resultingURL as URL?)?.path ?? "휴지통"
            return item(action, .succeeded, "휴지통으로 이동했습니다: \(destination)")
        } catch {
            return item(action, .failed, error.localizedDescription)
        }
    }

    private func availableVolumeBytes() -> Int64? {
        var home = FileManager.default.homeDirectoryForCurrentUser
        home.removeAllCachedResourceValues()
        let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityKey
        ])
        return values?.volumeAvailableCapacity.map { Int64($0) }
    }

    private func dockerExecutable() -> URL? {
        [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ].first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    private func firstOutputLine(_ output: CommandOutput, fallback: String) -> String {
        let combined = output.standardOutput + output.standardError
        return combined.split(whereSeparator: \.isNewline).first.map(String.init) ?? fallback
    }

    private func item(
        _ action: CleanupAction,
        _ status: CleanupExecutionStatus,
        _ message: String
    ) -> CleanupExecutionItemResult {
        CleanupExecutionItemResult(
            actionID: action.id,
            title: action.title,
            status: status,
            message: message,
            method: { if case .projectArtifact = action.kind { .trash } else { .toolCleanup } }()
        )
    }
}

enum CleanupTargetValidator {
    static func isAllowedProjectArtifact(_ url: URL, allowedRoots: [URL]) -> Bool {
        var value = stat()
        let statResult = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &value)
        }
        guard statResult == 0, (value.st_mode & S_IFMT) == S_IFDIR else { return false }

        let directoryName = url.lastPathComponent
        guard ProjectArtifactCatalog.definitions.contains(where: {
            $0.directoryNames.contains(directoryName)
        }) else { return false }

        let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return allowedRoots.contains { root in
            let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
            return canonicalPath.hasPrefix(canonicalRoot + "/")
        }
    }
}
