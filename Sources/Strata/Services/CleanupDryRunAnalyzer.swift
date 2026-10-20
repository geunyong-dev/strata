import Foundation

actor CleanupDryRunAnalyzer {
    private let runner = CommandRunner()
    private let scanner = FileSystemScanner()
    private let diagnosticAnalyzer = DeveloperDiagnosticAnalyzer()

    func preview(_ actions: [CleanupAction]) -> [String: DryRunResult] {
        var results: [String: DryRunResult] = [:]
        let dockerDiagnostic = actions.contains { action in
            if case .docker = action.kind { return true }
            return false
        } ? diagnosticAnalyzer.scanDocker() : nil

        for action in actions {
            let result: DryRunResult
            switch action.kind {
            case let .docker(resourceType):
                result = previewDocker(action, resourceType: resourceType, diagnostic: dockerDiagnostic)
            case let .simulatorRuntime(identifier):
                result = previewRuntime(action, identifier: identifier)
            case let .projectArtifact(path):
                result = previewProjectArtifact(action, path: path)
            }
            results[action.id] = result
        }
        return results
    }

    private func previewDocker(
        _ action: CleanupAction,
        resourceType: String,
        diagnostic: DockerDiagnostic?
    ) -> DryRunResult {
        guard let diagnostic else {
            return result(action, .failed, nil, "Docker 진단 결과가 없습니다.")
        }
        guard diagnostic.state == .available else {
            return result(action, .unavailable, nil, diagnosticMessage(diagnostic.state))
        }
        guard let resource = diagnostic.resources.first(where: { $0.type == resourceType }) else {
            return result(action, .changed, 0, "대상이 더 이상 존재하지 않습니다.")
        }
        let status: DryRunStatus = materiallyChanged(action.baselineBytes, resource.reclaimableBytes)
            ? .changed : .verified
        return result(
            action,
            status,
            resource.reclaimableBytes,
            "docker system df로 현재 회수 가능량을 다시 확인했습니다."
        )
    }

    private func previewRuntime(_ action: CleanupAction, identifier: String) -> DryRunResult {
        let output = runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "runtime", "delete", identifier, "--dry-run"]
        )
        if output.timedOut {
            return result(action, .failed, nil, "시뮬레이터 상태 확인이 시간 제한을 초과했습니다.")
        }
        let combined = output.standardOutput + output.standardError
        guard output.exitCode == 0, combined.contains("Would delete") else {
            let message = combined.split(whereSeparator: \.isNewline).first.map(String.init)
                ?? "런타임 상태를 확인하지 못했습니다."
            return result(action, .unavailable, nil, message)
        }
        return result(action, .verified, action.estimatedBytes, combined.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func previewProjectArtifact(_ action: CleanupAction, path: String) -> DryRunResult {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: path) else {
            return result(action, .changed, 0, "폴더가 더 이상 존재하지 않습니다.")
        }
        if let definitionID = action.confirmedArtifactDefinitionID,
           !ArtifactEvidence.inspect(url, definitionID: definitionID).isConfirmed {
            return result(action, .changed, nil, "프로젝트 판정 근거가 변경되었습니다. 다시 스캔해 주세요.")
        }
        let measurement = scanner.measure(urls: [url])
        if measurement.inaccessibleItemCount > 0 {
            return result(action, .unavailable, measurement.allocatedBytes, "읽지 못한 항목이 있어 검증하지 못했습니다. 접근 권한을 확인해 주세요.")
        }
        let status: DryRunStatus = materiallyChanged(action.baselineBytes, measurement.allocatedBytes)
            ? .changed : .verified
        let message = "현재 할당 용량을 다시 측정했습니다. 파일은 변경하지 않았습니다."
        return result(action, status, measurement.allocatedBytes, message)
    }

    private func materiallyChanged(_ expected: Int64, _ current: Int64) -> Bool {
        let threshold = max(Int64(1_000_000), Int64(Double(max(expected, 1)) * 0.05))
        return abs(expected - current) > threshold
    }

    private func result(
        _ action: CleanupAction,
        _ status: DryRunStatus,
        _ currentBytes: Int64?,
        _ message: String
    ) -> DryRunResult {
        DryRunResult(actionID: action.id, status: status, currentBytes: currentBytes, message: message)
    }

    private func diagnosticMessage(_ state: DiagnosticState) -> String {
        switch state {
        case .available: "Docker 사용량을 확인했습니다."
        case let .unavailable(message), let .failed(message): message
        }
    }
}
