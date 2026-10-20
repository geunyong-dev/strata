import Foundation

/// Task-local context follows this scan and its child tasks, not unrelated app work.
enum ScanLogContext {
    @TaskLocal static var current: ScanLog?

    static func error(path: String, operation: String, error: NSError) {
        current?.write("read_error", ["path": path, "operation": operation,
            "domain": error.domain, "code": error.code,
            "underlyingDomain": (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain ?? "",
            "underlyingCode": (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code ?? 0])
    }

    static func posix(path: String, operation: String, code: Int32) {
        error(path: path, operation: operation, error: NSError(domain: NSPOSIXErrorDomain, code: Int(code)))
    }
}

/// Synchronous, bounded JSONL writes preserve useful evidence even if the app exits mid-scan.
final class ScanLog: @unchecked Sendable {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Strata")
    }
    let url: URL
    private let lock = NSLock()
    private var handle: FileHandle?
    private var failure: String?
    private var count = 0
    private var omitted = 0
    private var lastProgress = Date.distantPast
    private var phase = ""
    private let eventLimit: Int

    var warning: String? {
        lock.lock(); defer { lock.unlock() }
        return failure.map { "스캔 로그 저장 실패: \($0)" }
    }

    init(directory: URL = ScanLog.directory, startedAt: Date = Date(), eventLimit: Int = 10_000) {
        self.eventLimit = eventLimit
        let stamp = ISO8601DateFormatter().string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        url = directory.appending(path: "scan-\(stamp)-\(UUID().uuidString).jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: url)
        } catch { failure = error.localizedDescription }
        write("started", ["schemaVersion": 3, "startedAt": startedAt.timeIntervalSince1970,
            "appPath": Bundle.main.bundleURL.path,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "os": ProcessInfo.processInfo.operatingSystemVersionString])
    }

    func write(_ event: String, _ fields: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        guard count < eventLimit || event == "finished" || event == "summary" else { omitted += 1; return }
        append(event, fields)
    }

    private func append(_ event: String, _ fields: [String: Any]) {
        guard let handle, failure == nil else { return }
        var record = fields
        record["event"] = event
        record["time"] = Date().timeIntervalSince1970
        do {
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            data.append(0x0A)
            try handle.write(contentsOf: data)
            count += 1
        } catch { failure = error.localizedDescription }
    }

    func progress(_ progress: ScanProgress) {
        lock.lock(); defer { lock.unlock() }
        guard phase != progress.phase || Date().timeIntervalSince(lastProgress) >= 5 else { return }
        phase = progress.phase
        lastProgress = Date()
        guard count < eventLimit else { omitted += 1; return }
        append("progress", ["phase": progress.phase, "path": progress.currentPath,
            "measuredBytes": progress.measuredBytes, "visitedItems": progress.visitedItemCount,
            "completedAreas": progress.completedAreaCount, "totalAreas": progress.totalAreaCount])
    }

    func summary(_ snapshot: ScanSnapshot) {
        if let admin = snapshot.administratorScan {
            write("administrator_summary", ["status": admin.status.rawValue, "additionalBytes": admin.additionalBytes,
                "improvedAreas": admin.improvedAreas, "message": admin.message])
        }
        write("summary", ["durationSeconds": max(0, snapshot.finishedAt.timeIntervalSince(snapshot.startedAt)),
            "totalBytes": snapshot.volume.totalBytes, "usedBytes": snapshot.volume.usedBytes,
            "capacity": Self.capacityFields(snapshot.volume),
            "areaMeasurementBasis": "data-volume-folder-allocated-bytes",
            "measuredBytes": snapshot.scannedVolumeBytes, "unclassifiedBytes": snapshot.unaccountedBytes,
            "spaceAccounting": Self.accountingFields(snapshot),
            "permissionProbe": String(describing: snapshot.diskAccess.state),
            "checkedPaths": snapshot.diskAccess.checkedPaths, "deniedPaths": snapshot.diskAccess.deniedPaths,
            "areas": snapshot.volumeAreas.map { ["path": $0.path, "bytes": $0.allocatedBytes,
                "unreadableCount": $0.inaccessibleItemCount, "unreadablePaths": $0.inaccessiblePaths,
                "note": $0.measurementNote ?? ""] as [String: Any] },
            "projectUnreadableCount": snapshot.projectArtifacts.inaccessibleItemCount,
            "toolUnreadableCount": snapshot.usages.reduce(0) { $0 + $1.inaccessibleItemCount },
            "diagnosticFacts": snapshot.spaceDiagnostics?.facts ?? [],
            "diagnosticUnavailable": snapshot.spaceDiagnostics?.unavailable ?? []])
    }

    static func capacityFields(_ volume: VolumeUsage) -> [String: Any] {
        ["ordinaryAvailableBytes": volume.physicalAvailableBytes.map { $0 as Any } ?? NSNull(),
         "importantAvailableBytes": volume.importantAvailableBytes.map { $0 as Any } ?? NSNull(),
         "displayedAvailableBytes": volume.displayedAvailableBytes,
         "displayBasis": volume.physicalAvailableBytes == nil ? "important-usage-fallback" : "ordinary-free"]
    }

    static func accountingFields(_ snapshot: ScanSnapshot) -> [String: Any] {
        let value = snapshot.spaceAccounting
        var fields: [String: Any] = ["status": value.status.rawValue, "rawGapBytes": value.rawGapBytes,
            "knownVolumeBytes": value.knownVolumeBytes, "unresolvedBytes": value.unresolvedBytes,
            "measurementVolumeUUID": snapshot.volume.volumeUUID.map { $0 as Any } ?? NSNull()]
        if let raw = snapshot.spaceDiagnostics?.containerUsage,
           let data = try? JSONEncoder().encode(raw), let json = try? JSONSerialization.jsonObject(with: data) {
            fields["containerUsage"] = json
        }
        return fields
    }

    func finish(status: String) {
        lock.lock(); defer { lock.unlock() }
        append("finished", ["status": status, "omittedEvents": omitted])
        do { try handle?.synchronize(); try handle?.close() }
        catch { failure = error.localizedDescription }
        handle = nil
    }

    deinit { try? handle?.close() }
}
