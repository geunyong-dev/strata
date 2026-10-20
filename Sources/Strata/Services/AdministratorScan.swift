import Foundation
import ReadOnlyScanCore

struct AdministratorScanReport: Sendable {
    enum Status: String, Sendable { case completed, partial, cancelled, unavailable }
    let status: Status
    let additionalBytes: Int64
    let improvedAreas: Int
    let message: String
}

struct AdministratorScan: Sendable {
    typealias Runner = @Sendable (URL, [String], TimeInterval) -> CommandOutput
    var run: Runner = { CommandRunner().run(executable: $0, arguments: $1, timeout: $2) }

    func refine(_ areas: [VolumeAreaUsage], bundle: Bundle = .main) -> ([VolumeAreaUsage], AdministratorScanReport) {
        func unchanged(_ status: AdministratorScanReport.Status, _ message: String) -> ([VolumeAreaUsage], AdministratorScanReport) {
            ScanLogContext.current?.write("administrator_scan", ["status": status.rawValue, "message": message])
            return (areas, .init(status: status, additionalBytes: 0, improvedAreas: 0, message: message))
        }
        let helper = bundle.bundleURL.appending(path: "Contents/Helpers/StrataReadOnlyScanner")
        guard bundle.bundleURL.pathExtension == "app", FileManager.default.isExecutableFile(atPath: helper.path) else {
            return unchanged(.unavailable, "정밀 검사 도구가 없습니다. 설치본에서 다시 시도해주세요. 일반 검사 결과를 표시합니다.")
        }
        let verification = run(URL(fileURLWithPath: "/usr/bin/codesign"),
                               ["--verify", "--deep", "--strict", bundle.bundleURL.path], 10)
        guard verification.exitCode == 0, !verification.timedOut, !verification.cancelled else {
            return unchanged(.unavailable, "설치본 무결성을 확인하지 못했습니다. 일반 검사 결과를 유지합니다.")
        }
        let id = UUID().uuidString
        let directory = URL(fileURLWithPath: "/private/tmp/strata-readonly-" + id, isDirectory: true)
        let lease = directory.appending(path: "lease")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            guard FileManager.default.createFile(atPath: lease.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
                return unchanged(.unavailable, "정밀 검사를 준비하지 못했습니다. 일반 검사 결과를 유지합니다.")
            }
            ScanLogContext.current?.write("administrator_scan_started", ["scope": ReadOnlyScanScope.paths])
            let output = run(URL(fileURLWithPath: "/usr/bin/osascript"), Self.arguments(helper: helper.path, leaseID: id), 340)
            // Removing the lease stops the privileged scanner on its next traversal step,
            // even when terminating osascript did not terminate its privileged child.
            try? FileManager.default.removeItem(at: lease)
            if output.cancelled || Task.isCancelled {
                return unchanged(.cancelled, "정밀 검사를 중단했습니다.")
            }
            if output.standardError.contains("(-128)") {
                return unchanged(.cancelled, "관리자 인증을 취소했습니다. 일반 검사 결과를 표시합니다.")
            }
            guard !output.timedOut, output.exitCode == 0,
                  let response = Self.decode(output.standardOutput) else {
                ScanLogContext.current?.write("administrator_scan_failed", ["exitCode": output.exitCode,
                    "timedOut": output.timedOut, "error": String(output.standardError.prefix(1000))])
                return unchanged(.unavailable, "정밀 검사를 완료하지 못했습니다. 일반 검사 결과를 유지합니다. 로그에서 원인을 확인할 수 있습니다.")
            }
            for result in response.results {
                ScanLogContext.current?.write("administrator_area", ["path": result.path, "bytes": result.bytes,
                    "unreadablePaths": result.unreadablePaths, "unreadableCount": result.unreadableCount,
                    "posixErrorCodes": result.errorCodes,
                    "visited": result.visited, "complete": result.complete])
            }
            let merged = Self.merge(areas, response: response)
            ScanLogContext.current?.write("administrator_scan", ["status": merged.1.status.rawValue,
                "additionalBytes": merged.1.additionalBytes, "improvedAreas": merged.1.improvedAreas])
            return merged
        } catch {
            return unchanged(.unavailable, "정밀 검사를 준비하지 못했습니다. 일반 검사 결과를 유지합니다.")
        }
    }

    static func arguments(helper: String, leaseID: String) -> [String] {
        let command = "exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin " + shellQuote(helper) + " " + shellQuote(leaseID)
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return ["-e", "with timeout of 330 seconds", "-e", "do shell script \"\(literal)\" with administrator privileges", "-e", "end timeout"]
    }

    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func decode(_ string: String) -> ReadOnlyScanResponse? {
        guard string.utf8.count <= 8_000_000,
              let response = try? JSONDecoder().decode(ReadOnlyScanResponse.self, from: Data(string.utf8)),
              response.version == 1, response.effectiveUID == 0,
              !response.results.isEmpty, response.results.count <= ReadOnlyScanScope.paths.count,
              Set(response.results.map(\.path)).count == response.results.count,
              response.results.allSatisfy({ result in
                  ReadOnlyScanScope.paths.contains(result.path) && result.bytes >= 0 && result.bytes <= Int64.max / 12
                  && result.unreadableCount >= 0 && result.visited >= 0
                  && result.unreadablePaths.count <= min(1000, result.unreadableCount)
                  && (result.unreadableCount == 0 || !result.unreadablePaths.isEmpty)
                  && result.unreadablePaths.allSatisfy { $0 == result.path || $0.hasPrefix(result.path + "/") }
              }) else { return nil }
        return response
    }

    static func merge(_ areas: [VolumeAreaUsage], response: ReadOnlyScanResponse) -> ([VolumeAreaUsage], AdministratorScanReport) {
        var added: Int64 = 0
        var improved = 0
        var retained = response.results.count < ReadOnlyScanScope.paths.count
        let merged = areas.map { area -> VolumeAreaUsage in
            guard let result = response.results.first(where: { ReadOnlyScanScope.displayPath($0.path) == area.path }) else { return area }
            // Replace the WHOLE area; never sum a privileged subtree into a partial scan.
            // Different TCC contexts can make a root scan less complete: retain the
            // ordinary result if the new measurement is smaller or unfinished.
            guard result.complete, result.bytes >= area.allocatedBytes,
                  result.bytes > area.allocatedBytes || result.unreadableCount <= area.inaccessibleItemCount else {
                retained = true; return area
            }
            let gain = result.bytes - area.allocatedBytes
            added += gain
            if gain > 0 || result.unreadableCount < area.inaccessibleItemCount { improved += 1 }
            return VolumeAreaUsage(name: area.name, path: area.path, symbol: area.symbol,
                allocatedBytes: result.bytes, inaccessibleItemCount: result.unreadableCount,
                inaccessiblePaths: Array(result.unreadablePaths.prefix(50)),
                measurementNote: "관리자 권한으로 다시 측정했습니다. 읽지 못한 하위 항목이 있으면 일부 용량은 포함되지 않습니다.")
        }
        let message = retained
            ? "정밀 검사 일부 반영 · 완료하지 못했거나 더 적게 측정된 영역은 일반 검사 결과를 유지했습니다."
            : "정밀 검사 완료 · 추가로 확인한 공간 \(added.storageFormatted)"
        return (merged, .init(status: retained ? .partial : .completed, additionalBytes: added,
                              improvedAreas: improved, message: message))
    }
}
