import Foundation

struct ScanProgress: Sendable {
    let startedAt: Date
    var updatedAt: Date = Date()
    var phase: String = "디스크 정보 확인"
    var currentPath: String = ""
    var visitedItemCount: Int = 0
    var completedAreaCount: Int = 0
    var totalAreaCount: Int = 0
    var volume: VolumeUsage
    var areas: [VolumeAreaUsage] = []

    var measuredBytes: Int64 { areas.reduce(0) { $0 + $1.allocatedBytes } }
}
