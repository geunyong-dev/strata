import Foundation

struct CleanupPlanBuilder: Sendable {
    func makeActions(
        diagnostics: DeveloperDiagnostics,
        projectArtifacts: ProjectArtifactReport
    ) -> [CleanupAction] {
        var actions = dockerActions(diagnostics.docker)
        actions.append(contentsOf: runtimeActions(diagnostics.xcode))
        actions.append(contentsOf: projectActions(projectArtifacts))
        return actions.sorted { lhs, rhs in
            if lhs.safety != rhs.safety {
                return safetyOrder(lhs.safety) < safetyOrder(rhs.safety)
            }
            return lhs.estimatedBytes > rhs.estimatedBytes
        }
    }

    private func dockerActions(_ diagnostic: DockerDiagnostic) -> [CleanupAction] {
        guard diagnostic.state == .available else { return [] }
        return diagnostic.resources.compactMap { resource in
            guard resource.reclaimableBytes > 0 else { return nil }
            let configuration: (title: String, safety: SafetyLevel, command: String)
            switch resource.type {
            case "Build Cache":
                configuration = ("Docker 빌드 캐시", .safe, "docker builder prune -a")
            case "Images":
                configuration = ("사용하지 않는 Docker 이미지", .caution, "docker image prune -a")
            case "Containers":
                configuration = ("중지된 Docker 컨테이너", .caution, "docker container prune")
            case "Local Volumes":
                configuration = ("사용하지 않는 Docker 볼륨", .dangerous, "docker volume prune")
            default:
                return nil
            }
            return CleanupAction(
                id: "docker:\(resource.type)",
                kind: .docker(resourceType: resource.type),
                title: configuration.title,
                detail: "전체 \(resource.totalCount)개 · 사용 중 \(resource.activeCount)개",
                baselineBytes: resource.reclaimableBytes,
                estimatedBytes: resource.reclaimableBytes,
                safety: configuration.safety,
                executionPreview: configuration.command
            )
        }
    }

    private func runtimeActions(_ diagnostic: XcodeDiagnostic) -> [CleanupAction] {
        guard diagnostic.state == .available else { return [] }
        return diagnostic.runtimes.filter { $0.isCleanupCandidate() }.map { runtime in
            CleanupAction(
                id: "simulator:\(runtime.id)",
                kind: .simulatorRuntime(identifier: runtime.id),
                title: "\(runtime.platform) \(runtime.version) 런타임",
                detail: runtime.lastUsedAt.map {
                    "마지막 사용 \($0.formatted(date: .abbreviated, time: .omitted))"
                } ?? "사용 기록 없음",
                baselineBytes: runtime.sizeBytes,
                estimatedBytes: runtime.sizeBytes,
                safety: .caution,
                executionPreview: "xcrun simctl runtime delete \(runtime.id)",
                lastUsedAt: runtime.lastUsedAt
            )
        }
    }

    private func projectActions(_ report: ProjectArtifactReport) -> [CleanupAction] {
        report.artifacts.filter { $0.allocatedBytes > 0 }.map { artifact in
            CleanupAction(
                id: "project:\(artifact.path)",
                kind: .projectArtifact(path: artifact.path),
                title: "\(artifact.projectName) · \(artifact.definition.name)",
                detail: artifact.path,
                baselineBytes: artifact.allocatedBytes,
                estimatedBytes: artifact.estimatedReclaimableBytes,
                safety: artifact.safety,
                executionPreview: "휴지통으로 이동: \(artifact.path)",
                createdAt: artifact.createdAt,
                modifiedAt: artifact.modifiedAt,
                accessedAt: artifact.accessedAt,
                candidateEvidence: artifact.assessment,
                confirmedArtifactDefinitionID: artifact.evidence.isConfirmed ? artifact.definition.id : nil
            )
        }
    }

    private func safetyOrder(_ safety: SafetyLevel) -> Int {
        switch safety {
        case .safe: 0
        case .caution: 1
        case .dangerous: 2
        }
    }
}
