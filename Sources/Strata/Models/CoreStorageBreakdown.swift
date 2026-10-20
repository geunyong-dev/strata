import Foundation

/// Presentation-only accounting. Tool estimates are never added to filesystem areas.
struct CoreStorageBreakdown {
    struct Band: Identifiable {
        enum Kind { case free, unmeasured, systemVolumes, area, grouped }
        let id: String
        let name: String
        let bytes: Double
        let kind: Kind
        let areas: [VolumeAreaUsage]
        let texture: Int

        var formattedBytes: String {
            if areas.count == 1, let area = areas.first, area.isTrash {
                return area.inaccessibleItemCount > 0 ? "최소 \(area.allocatedBytes.storageFormatted)" : area.capacityText
            }
            return ByteCountFormatter.string(fromByteCount: Int64(min(bytes, Double(Int64.max / 2))), countStyle: .file)
        }
    }

    let bands: [Band]
    let total: Double
    let isMeasuredOnly: Bool
    let hasPhysicalFreeSpace: Bool

    init(volume: VolumeUsage, areas: [VolumeAreaUsage], isScanning: Bool = false,
         evidence: APFSContainerUsage? = nil) {
        let measured = areas.filter { $0.allocatedBytes > 0 }
            .sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes }
        let sum = measured.reduce(0.0) { $0 + Double($1.allocatedBytes) }
        let capacity = max(0, Double(volume.totalBytes))
        let free = Double(volume.displayedAvailableBytes)
        let accounting = StorageSpaceAccounting(volume: volume,
            measuredBytes: areas.reduce(Int64(0)) { $0 + max(0, $1.allocatedBytes) }, evidence: isScanning ? nil : evidence)
        hasPhysicalFreeSpace = volume.physicalAvailableBytes != nil
        // Shared extents, live changes and different measurement bases can disagree.
        // Do not shrink measurements to manufacture a disk-capacity partition.
        isMeasuredOnly = capacity <= 0 || sum > capacity - free
        total = isMeasuredOnly ? sum : capacity
        var result: [Band] = []
        if !isMeasuredOnly {
            if free > 0 {
                result.append(Band(id: "free", name: hasPhysicalFreeSpace ? "여유 공간" : "사용 가능 공간",
                                   bytes: free, kind: .free, areas: [], texture: 0))
            }
            let remainder = Double(accounting.unresolvedBytes)
            if remainder > 0 {
                result.append(Band(id: "unmeasured", name: isScanning ? "검사 대기·미분류" : "아직 설명되지 않은 공간", bytes: remainder,
                                   kind: .unmeasured, areas: [], texture: 4))
            }
            if accounting.knownVolumeBytes > 0 {
                result.append(Band(id: "system-volumes", name: "시스템·다른 볼륨", bytes: Double(accounting.knownVolumeBytes),
                                   kind: .systemVolumes, areas: [], texture: 3))
            }
        }
        // At most seven labels including free/unmeasured. Every grouped area remains selectable.
        // Reserve a visible band for Trash, even when it is smaller than the top areas.
        let pinned = measured.filter(\.isTrash)
        let others = measured.filter { !$0.isTrash }
        let areaBudget = min(5, 7 - result.count)
        let needsGrouping = measured.count > areaBudget
        let slots = needsGrouping ? areaBudget - 1 : areaBudget
        let visible = pinned + Array(others.prefix(max(0, slots - pinned.count)))
        for area in visible.sorted(by: { Self.order($0.path) < Self.order($1.path) }) {
            result.append(Band(id: area.path, name: area.name, bytes: Double(area.allocatedBytes),
                               kind: .area, areas: [area], texture: area.isTrash ? 3 : Self.texture(for: area.path)))
        }
        if needsGrouping {
            let visibleIDs = Set(visible.map(\.id))
            let remaining = measured.filter { !visibleIDs.contains($0.id) }
            result.append(Band(id: "grouped", name: "기타 \(remaining.count)개 영역",
                               bytes: remaining.reduce(0) { $0 + Double($1.allocatedBytes) },
                               kind: .grouped, areas: remaining, texture: 4))
        }
        bands = result
    }

    private static func order(_ path: String) -> String {
        let paths = ["/Users", "/Applications", "/Library", "/System", "/private"]
        return "\(paths.firstIndex(of: path) ?? 5)-\(path)"
    }

    static func texture(for path: String) -> Int {
        switch path {
        case "/Users": 0
        case "/Applications": 1
        case "/Library": 2
        case "/System": 3
        default: 4
        }
    }

    /// Nice-number intervals, in decimal bytes (matching file capacity labels).
    static func tickStep(total: Double, height: Double) -> Double {
        guard total > 0 else { return 1 }
        let target = total / max(2, min(6, floor(height / 64)))
        let power = pow(10, floor(log10(target)))
        let normalized = target / power
        return (normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10) * power
    }

    /// Move labels, never the data boundaries. Call with enough height for all rows.
    static func labelCenters(ideal: [Double], height: Double, rowHeight: Double = 40) -> [Double] {
        guard !ideal.isEmpty else { return [] }
        var centers: [Double] = []
        for point in ideal {
            centers.append(max(rowHeight / 2, point, (centers.last ?? -rowHeight / 2) + rowHeight))
        }
        centers[centers.count - 1] = min(centers.last!, height - rowHeight / 2)
        if centers.count > 1 {
            for i in stride(from: centers.count - 2, through: 0, by: -1) {
                centers[i] = min(centers[i], centers[i + 1] - rowHeight)
            }
        }
        return centers
    }
}
