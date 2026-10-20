import Foundation
import SwiftUI

enum SafetyLevel: String, CaseIterable, Codable, Sendable {
    case safe
    case caution
    case dangerous

    var title: String {
        switch self {
        case .safe: "안전"
        case .caution: "주의"
        case .dangerous: "위험"
        }
    }

    var detail: String {
        switch self {
        case .safe: "다시 생성할 수 있는 캐시"
        case .caution: "다시 다운로드하거나 빌드해야 함"
        case .dangerous: "사용자 데이터가 사라질 수 있음"
        }
    }

    var color: Color {
        switch self {
        case .safe, .caution: StrataTheme.secondary
        case .dangerous: StrataTheme.irreversible
        }
    }

    var symbol: String {
        switch self {
        case .safe: "arrow.triangle.2.circlepath"
        case .caution: "arrow.down.circle"
        case .dangerous: "exclamationmark.triangle.fill"
        }
    }
}

struct ToolchainDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let relativePaths: [String]
    let safety: SafetyLevel
    let reclaimability: Double
    let explanation: String
    let cleanupHint: String
}

struct ToolchainUsage: Identifiable, Sendable {
    let definition: ToolchainDefinition
    let allocatedBytes: Int64
    let scannedPaths: [String]
    let inaccessibleItemCount: Int
    let scanDuration: Duration

    var id: String { definition.id }
    var estimatedReclaimableBytes: Int64 {
        Int64(Double(allocatedBytes) * definition.reclaimability)
    }
}

struct VolumeUsage: Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    // Unlike important-usage capacity, this excludes space macOS may purge later.
    var physicalAvailableBytes: Int64? = nil
    var importantAvailableBytes: Int64? = nil
    var volumeUUID: String? = nil

    var displayedAvailableBytes: Int64 { min(max(0, totalBytes), max(0, physicalAvailableBytes ?? availableBytes)) }
    var availabilityTitle: String { physicalAvailableBytes == nil ? "사용 가능" : "여유" }
    var usedBytes: Int64 { max(0, totalBytes - displayedAvailableBytes) }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

struct VolumeAreaUsage: Identifiable, Sendable {
    let name: String
    let path: String
    let symbol: String
    let allocatedBytes: Int64
    let inaccessibleItemCount: Int
    let inaccessiblePaths: [String]
    var isTrash: Bool = false
    var measurementNote: String? = nil

    var id: String { path }
    var systemDataExplanation: String? {
        switch path {
        case "/.Spotlight-V100": "파일과 앱을 빠르게 찾기 위해 macOS가 관리하는 검색 데이터입니다. 이 용량 전체가 삭제 가능한 공간이라는 뜻은 아닙니다."
        case "/.DocumentRevisions-V100": "macOS가 문서의 이전 상태를 보관하는 공간입니다. 변경 이력을 복원할 때 사용될 수 있습니다."
        case "/.fseventsd": "macOS가 파일과 폴더의 변경을 추적하는 기록입니다. 정리 후보로 자동 선택하지 않습니다."
        default: nil
        }
    }
    var capacityText: String {
        if isTrash && inaccessibleItemCount > 0 {
            return allocatedBytes > 0 ? "최소 \(allocatedBytes.storageFormatted) · 일부 측정" : "측정 불가"
        }
        return allocatedBytes.storageFormatted
    }
}

enum DiskAccessState: Sendable {
    case available
    case limited
    case unknown

    var title: String {
        switch self {
        case .available: "전체 디스크 접근 가능"
        case .limited: "일부 폴더 접근 제한"
        case .unknown: "접근 권한 확인 필요"
        }
    }

    var explanation: String {
        switch self {
        case .available: "확인 가능한 보호 폴더를 모두 읽을 수 있습니다."
        case .limited: "macOS가 일부 폴더를 차단해 실제 사용량보다 작게 표시될 수 있습니다."
        case .unknown: "보호 폴더가 없거나 현재 환경에서 권한 상태를 판별하지 못했습니다."
        }
    }
}

struct DiskAccessReport: Sendable {
    let state: DiskAccessState
    let checkedPaths: [String]
    let deniedPaths: [String]
}

enum DiagnosticState: Sendable, Equatable {
    case available
    case unavailable(String)
    case failed(String)
}

struct DockerResourceUsage: Identifiable, Sendable {
    let type: String
    let totalCount: Int
    let activeCount: Int
    let sizeBytes: Int64
    let reclaimableBytes: Int64

    var id: String { type }
}

struct DockerDiagnostic: Sendable {
    let state: DiagnosticState
    let resources: [DockerResourceUsage]

    var totalBytes: Int64 { resources.reduce(0) { $0 + $1.sizeBytes } }
    var reclaimableBytes: Int64 { resources.reduce(0) { $0 + $1.reclaimableBytes } }
}

struct SimulatorRuntimeUsage: Identifiable, Sendable {
    let id: String
    let platform: String
    let version: String
    let build: String
    let sizeBytes: Int64
    let state: String
    let isDeletable: Bool
    let lastUsedAt: Date?

    func isCleanupCandidate(referenceDate: Date = Date()) -> Bool {
        guard isDeletable else { return false }
        guard let lastUsedAt else { return true }
        return lastUsedAt < Calendar.current.date(byAdding: .day, value: -90, to: referenceDate) ?? referenceDate
    }
}

struct XcodeDiagnostic: Sendable {
    let state: DiagnosticState
    let runtimes: [SimulatorRuntimeUsage]
    let deviceCount: Int
    let unavailableDeviceCount: Int

    var runtimeBytes: Int64 { runtimes.reduce(0) { $0 + $1.sizeBytes } }
    var cleanupCandidateBytes: Int64 {
        runtimes.filter { $0.isCleanupCandidate() }.reduce(0) { $0 + $1.sizeBytes }
    }
}

struct DeveloperDiagnostics: Sendable {
    let docker: DockerDiagnostic
    let xcode: XcodeDiagnostic
}

struct ProjectArtifactDefinition: Identifiable, Sendable {
    let id: String
    let name: String
    let directoryNames: Set<String>
    let symbol: String
    let safety: SafetyLevel
    let reclaimability: Double
    let explanation: String
}

struct ProjectArtifact: Identifiable, Sendable {
    let definition: ProjectArtifactDefinition
    let path: String
    let projectName: String
    let allocatedBytes: Int64
    let modifiedAt: Date?
    let inaccessibleItemCount: Int

    var id: String { path }
    var createdAt: Date? = nil
    var accessedAt: Date? = nil
    var evidence: ArtifactEvidence = .unconfirmed
    var safety: SafetyLevel {
        definition.safety == .safe && (!evidence.isConfirmed || inaccessibleItemCount > 0) ? .caution : definition.safety
    }
    var assessment: String {
        evidence.summary + (inaccessibleItemCount > 0 ? "\n읽지 못한 항목이 있어 직접 확인해야 합니다." : "")
    }
    var estimatedReclaimableBytes: Int64 {
        Int64(Double(allocatedBytes) * definition.reclaimability)
    }
}

struct ProjectArtifactReport: Sendable {
    let scannedRoots: [String]
    let artifacts: [ProjectArtifact]
    let inaccessibleItemCount: Int

    var totalBytes: Int64 { artifacts.reduce(0) { $0 + $1.allocatedBytes } }
    var estimatedReclaimableBytes: Int64 {
        artifacts.reduce(0) { $0 + $1.estimatedReclaimableBytes }
    }
}

enum CleanupActionKind: Sendable, Hashable {
    case docker(resourceType: String)
    case simulatorRuntime(identifier: String)
    case projectArtifact(path: String)
}

struct CleanupAction: Identifiable, Sendable {
    let id: String
    let kind: CleanupActionKind
    let title: String
    let detail: String
    let baselineBytes: Int64
    let estimatedBytes: Int64
    let safety: SafetyLevel
    let executionPreview: String
    var createdAt: Date? = nil
    var modifiedAt: Date? = nil
    var accessedAt: Date? = nil
    var lastUsedAt: Date? = nil
    var candidateEvidence: String? = nil
    var confirmedArtifactDefinitionID: String? = nil
}

enum DryRunStatus: Sendable, Equatable {
    case verified
    case changed
    case unavailable
    case failed
}

struct DryRunResult: Sendable {
    let actionID: String
    let status: DryRunStatus
    let currentBytes: Int64?
    let message: String
}

enum CleanupExecutionStatus: String, Sendable, Equatable, Codable {
    case succeeded
    case skipped
    case failed
}

enum CleanupExecutionMethod: String, Sendable, Codable {
    case trash
    case toolCleanup
}

struct CleanupExecutionItemResult: Identifiable, Sendable, Codable {
    let actionID: String
    let title: String
    let status: CleanupExecutionStatus
    let message: String
    var method: CleanupExecutionMethod? = nil

    var id: String { actionID }
    var wasMovedToTrash: Bool {
        guard status == .succeeded else { return false }
        if let method { return method == .trash }
        // Older records did not store a structured method; only recognize the exact success prefix.
        return message.hasPrefix("휴지통으로 이동했습니다")
    }
}

struct CleanupRunSummary: Identifiable, Sendable, Codable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let availableBytesBefore: Int64?
    let availableBytesAfter: Int64?
    let results: [CleanupExecutionItemResult]
    var spaceMeasurementVersion: Int? = nil

    func measuredCapacity(_ bytes: Int64?) -> Int64? {
        guard let bytes, bytes >= 0 else { return nil }
        // Legacy code used zero for read errors, so a legacy zero is ambiguous.
        guard spaceMeasurementVersion != nil || bytes > 0 else { return nil }
        return bytes
    }

    var spaceChangeBytes: Int64? {
        guard let before = measuredCapacity(availableBytesBefore),
              let after = measuredCapacity(availableBytesAfter) else { return nil }
        return after - before
    }

    var spaceChangeText: String {
        guard let change = spaceChangeBytes else { return "측정 불가" }
        if change == 0 { return "변화 없음" }
        return "\(change > 0 ? "+" : "−")\(abs(change).storageFormatted)"
    }

    var spaceChangeExplanation: String {
        guard let change = spaceChangeBytes else {
            if spaceMeasurementVersion == nil {
                return "전후 측정값을 확인할 수 없습니다. 이전 기록의 0은 측정 실패와 구분할 수 없습니다."
            }
            return "정리 전후 중 하나 이상의 여유 공간 측정에 실패했습니다. 처리 성공 여부와는 별개입니다."
        }
        if change < 0 { return "정리 직후 디스크 여유 공간이 감소했습니다. 다른 앱의 활동 등이 포함되며 정리 실패를 뜻하지 않습니다." }
        if change == 0 { return "정리 직후 디스크 여유 공간에 변화가 없었습니다. 처리 성공 여부와는 별개입니다." }
        return "정리 직후의 디스크 전체 변화이며, 이 작업만으로 확보한 용량은 아닙니다."
    }

    var movedToTrashCount: Int { results.filter(\.wasMovedToTrash).count }
    var succeededCount: Int { results.filter { $0.status == .succeeded }.count }
    var failedCount: Int { results.filter { $0.status == .failed }.count }
}

struct ScanSnapshot: Sendable {
    let volume: VolumeUsage
    let volumeAreas: [VolumeAreaUsage]
    let diskAccess: DiskAccessReport
    let diagnostics: DeveloperDiagnostics
    let projectArtifacts: ProjectArtifactReport
    let usages: [ToolchainUsage]
    let startedAt: Date
    let finishedAt: Date

    var identifiedBytes: Int64 { usages.reduce(0) { $0 + $1.allocatedBytes } }
    var spaceDiagnostics: SpaceDiagnosticReport? = nil
    var administratorScan: AdministratorScanReport? = nil
    var estimatedReclaimableBytes: Int64 {
        usages.reduce(0) { $0 + $1.estimatedReclaimableBytes }
            + projectArtifacts.estimatedReclaimableBytes
    }
    var scannedVolumeBytes: Int64 {
        volumeAreas.reduce(0) { $0 + $1.allocatedBytes }
    }
    var unaccountedBytes: Int64 {
        spaceAccounting.unresolvedBytes
    }
    var spaceAccounting: StorageSpaceAccounting {
        StorageSpaceAccounting(volume: volume, measuredBytes: scannedVolumeBytes, evidence: spaceDiagnostics?.containerUsage)
    }
}

extension Int64 {
    var storageFormatted: String {
        if self == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
