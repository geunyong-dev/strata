import Foundation

struct SpaceDiagnosticReport: Sendable {
    var facts: [String] = []
    var unavailable: [String] = []
    var checkedAt = Date()
    var containerUsage: APFSContainerUsage? = nil
}

// Only fixed, read-only diskutil verbs are used. No snapshot deletion or thinning.
struct SpaceDiagnosticAnalyzer: Sendable {
    struct VolumeInfo: Decodable {
        let APFSContainerReference: String?
        let DeviceIdentifier: String?
        let CapacityInUse: Int64?
        var VolumeUUID: String? = nil
    }
    struct ContainerList: Decodable {
        let Containers: [Container]
    }
    struct Container: Decodable {
        let ContainerReference: String
        let CapacityCeiling: Int64
        let CapacityFree: Int64
        let Volumes: [Volume]
    }
    struct Volume: Decodable {
        let DeviceIdentifier: String
        let Name: String?
        let CapacityInUse: Int64
        let Roles: [String]?
        var APFSVolumeUUID: String? = nil
    }
    struct SnapshotList: Decodable {
        let Snapshots: [Snapshot]
    }
    struct Snapshot: Decodable {
        let Name: String?
    }

    static func decode<T: Decodable>(_ type: T.Type, output: CommandOutput) throws -> T {
        guard output.exitCode == 0, !output.timedOut, !output.cancelled else {
            throw DiagnosticError.commandFailed
        }
        return try PropertyListDecoder().decode(type, from: Data(output.standardOutput.utf8))
    }
    enum DiagnosticError: Error { case commandFailed }

    func scan() -> SpaceDiagnosticReport {
        let runner = CommandRunner()
        func run(_ arguments: [String]) -> CommandOutput {
            runner.run(executable: URL(fileURLWithPath: "/usr/sbin/diskutil"), arguments: arguments, timeout: 8)
        }
        var report = SpaceDiagnosticReport()
        let dataPath = "/System/Volumes/Data"
        do {
            let info = try Self.decode(VolumeInfo.self, output: run(["info", "-plist", dataPath]))
            if let bytes = info.CapacityInUse {
                report.facts.append("데이터 볼륨의 OS 보고 사용량: \(bytes.storageFormatted)")
            }
            if let reference = info.APFSContainerReference, let device = info.DeviceIdentifier {
                let list = try Self.decode(ContainerList.self, output: run(["apfs", "list", "-plist"]))
                if let container = list.Containers.first(where: { $0.ContainerReference == reference }) {
                    report.containerUsage = Self.containerUsage(info: info, container: container)
                    report.facts.append("같은 APFS 컨테이너: 전체 \(container.CapacityCeiling.storageFormatted) · 여유 \(container.CapacityFree.storageFormatted)")
                    for volume in container.Volumes where volume.DeviceIdentifier != device {
                        report.facts.append("같은 컨테이너의 다른 볼륨 · \(volume.Name ?? volume.DeviceIdentifier) [\((volume.Roles ?? []).joined(separator: ", "))]: \(volume.CapacityInUse.storageFormatted)")
                    }
                } else { report.unavailable.append("데이터 볼륨의 APFS 컨테이너를 연결하지 못했습니다.") }
            } else { report.unavailable.append("APFS 컨테이너 정보를 제공하지 않는 볼륨입니다.") }
        } catch { report.unavailable.append("볼륨·컨테이너 정보 확인 불가: 권한, 응답 지연 또는 지원되지 않는 출력입니다.") }

        for (title, path) in [("데이터", dataPath), ("시스템", "/")] {
            if Task.isCancelled { break }
            do {
                let snapshots = try Self.decode(SnapshotList.self, output: run(["apfs", "listSnapshots", "-plist", path]))
                report.facts.append("\(title) 볼륨 스냅샷: \(snapshots.Snapshots.count)개 확인")
                for snapshot in snapshots.Snapshots.prefix(20) {
                    report.facts.append("\(title) 스냅샷 · \(snapshot.Name ?? "이름 미제공")")
                }
                if snapshots.Snapshots.count > 20 { report.facts.append("스냅샷 이름은 최근순이 아닌 출력 순서로 20개까지만 표시합니다.") }
            } catch { report.unavailable.append("\(title) 볼륨 스냅샷 확인 불가 (0개라는 의미가 아닙니다).") }
        }
        report.checkedAt = Date()
        return report
    }

    static func containerUsage(info: VolumeInfo, container: Container) -> APFSContainerUsage? {
        guard info.APFSContainerReference == container.ContainerReference,
              let device = info.DeviceIdentifier, let uuid = info.VolumeUUID,
              let data = container.Volumes.first(where: { $0.DeviceIdentifier == device }),
              data.APFSVolumeUUID?.caseInsensitiveCompare(uuid) == .orderedSame,
              data.Roles?.contains("Data") == true,
              Set(container.Volumes.map(\.DeviceIdentifier)).count == container.Volumes.count else { return nil }
        return .init(containerID: container.ContainerReference, dataVolumeID: device, dataVolumeUUID: uuid,
            capacityBytes: container.CapacityCeiling, freeBytes: container.CapacityFree,
            dataUsedBytes: data.CapacityInUse,
            otherVolumes: container.Volumes.filter { $0.DeviceIdentifier != device }.map {
                .init(id: $0.DeviceIdentifier, name: $0.Name ?? $0.DeviceIdentifier,
                      roles: $0.Roles ?? [], usedBytes: $0.CapacityInUse)
            })
    }
}
