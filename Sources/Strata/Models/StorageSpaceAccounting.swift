import Foundation

struct APFSVolumeUsage: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let roles: [String]
    let usedBytes: Int64

    var displayName: String {
        if roles.contains("System") { return "macOS 운영체제" }
        if roles.contains("Preboot") { return "시동 지원 데이터" }
        if roles.contains("Recovery") { return "복구 환경" }
        if roles.contains("VM") { return "가상 메모리" }
        if roles.contains("Update") { return "시스템 업데이트" }
        return "다른 볼륨 · \(name)"
    }
}

/// Raw values from a single `diskutil apfs list` response, never parsed from labels.
struct APFSContainerUsage: Codable, Sendable {
    let containerID: String
    let dataVolumeID: String
    let dataVolumeUUID: String
    let capacityBytes: Int64
    let freeBytes: Int64
    let dataUsedBytes: Int64
    let otherVolumes: [APFSVolumeUsage]
}

struct StorageSpaceAccounting: Sendable {
    enum Status: String, Sendable { case separated, unavailable, inconsistent }
    let status: Status
    let rawGapBytes: Int64
    let knownVolumeBytes: Int64
    let unresolvedBytes: Int64
    let volumes: [APFSVolumeUsage]

    init(volume: VolumeUsage, measuredBytes: Int64, evidence: APFSContainerUsage?) {
        let measured = max(0, measuredBytes)
        let gap = max(0, volume.usedBytes - measured)
        rawGapBytes = gap
        var accepted: Int64? = nil
        var state: Status = measured > volume.usedBytes ? .inconsistent : .unavailable
        if let evidence, let uuid = volume.volumeUUID,
           !uuid.isEmpty, uuid.caseInsensitiveCompare(evidence.dataVolumeUUID) == .orderedSame,
           let physicalFree = volume.physicalAvailableBytes, physicalFree >= 0, physicalFree <= volume.totalBytes,
           volume.totalBytes == evidence.capacityBytes {
            state = .inconsistent
            let capacity = evidence.capacityBytes
            // Do not clamp a disagreeing OS volume total into the available gap.
            // Shared blocks, changing files, quotas and mismatched scopes can disagree.
            if capacity > 0, evidence.freeBytes >= 0, evidence.freeBytes <= capacity,
               evidence.dataUsedBytes >= measured, evidence.dataUsedBytes <= capacity,
               !evidence.dataVolumeID.isEmpty, !evidence.containerID.isEmpty,
               Set(evidence.otherVolumes.map(\.id)).count == evidence.otherVolumes.count,
               evidence.otherVolumes.allSatisfy({ !$0.id.isEmpty && $0.id != evidence.dataVolumeID && $0.usedBytes >= 0 && $0.usedBytes <= capacity }) {
                var sum: Int64 = 0
                var valid = true
                for other in evidence.otherVolumes {
                    let (next, overflow) = sum.addingReportingOverflow(other.usedBytes)
                    if overflow || next > capacity { valid = false; break }
                    sum = next
                }
                if valid, evidence.dataUsedBytes <= capacity - evidence.freeBytes,
                   sum <= capacity - evidence.freeBytes - evidence.dataUsedBytes,
                   sum <= gap, evidence.dataUsedBytes <= volume.usedBytes - sum {
                    accepted = sum
                    state = .separated
                }
            }
        }
        status = state
        knownVolumeBytes = accepted ?? 0
        unresolvedBytes = gap - (accepted ?? 0)
        volumes = accepted != nil ? (evidence?.otherVolumes ?? []).filter { $0.usedBytes > 0 } : []
    }
}
