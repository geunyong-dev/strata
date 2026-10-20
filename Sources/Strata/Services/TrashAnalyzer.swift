import Foundation
import Darwin

/// Reads only the current user's Trash. Never enumerates external-volume Trash or deletes files.
struct TrashAnalyzer: Sendable {
    static func exclusions(for trashURL: URL, dataRoot: URL) -> [URL] {
        var urls = [trashURL]
        let prefix = "/System/Volumes/Data"
        if dataRoot.path == prefix && !trashURL.path.hasPrefix(prefix + "/") {
            urls.append(dataRoot.appending(path: String(trashURL.path.dropFirst())))
        }
        return urls
    }

    func measure(at url: URL, expectedDevice: UInt64?, onProgress: (DirectoryScanProgress) -> Void = { _ in }) -> VolumeAreaUsage {
        func result(_ bytes: Int64 = 0, errors: Int = 0, paths: [String] = [], note: String? = nil) -> VolumeAreaUsage {
            VolumeAreaUsage(name: "휴지통", path: url.path, symbol: "trash", allocatedBytes: bytes,
                inaccessibleItemCount: errors, inaccessiblePaths: paths, isTrash: true, measurementNote: note)
        }
        guard let expectedDevice, FileSystemScanner().deviceID(for: url.deletingLastPathComponent()) == expectedDevice else {
            return result(errors: 1, paths: [url.path], note: "현재 사용자 홈이 측정 볼륨 밖에 있거나 접근할 수 없어 휴지통을 측정하지 않았습니다.")
        }
        var value = stat()
        let status = url.path.withCString { lstat($0, &value) }
        if status != 0 {
            let code = errno
            ScanLogContext.posix(path: url.path, operation: "trash_lstat", code: code)
            if code == ENOENT { return result(note: "현재 사용자 휴지통 폴더가 없습니다.") }
            return result(errors: 1, paths: [url.path], note: "휴지통에 접근할 수 없습니다. 읽기 권한을 확인한 뒤 다시 스캔해 주세요.")
        }
        guard value.st_mode & S_IFMT == S_IFDIR, UInt64(value.st_dev) == expectedDevice else {
            return result(errors: 1, paths: [url.path], note: "휴지통이 일반 폴더가 아니거나 다른 볼륨에 있어 측정하지 않았습니다.")
        }
        // Explicitly check listing access: FileManager.fileExists alone hides permission failures.
        guard let directory = url.path.withCString({ opendir($0) }) else {
            ScanLogContext.posix(path: url.path, operation: "trash_opendir", code: errno)
            return result(errors: 1, paths: [url.path], note: "휴지통 내용을 읽을 수 없습니다. 전체 디스크 접근 권한을 확인해 주세요.")
        }
        closedir(directory)
        let measurement = FileSystemScanner().measure(urls: [url], onProgress: onProgress)
        // If the directory disappears while scanning, do not report a verified empty Trash.
        let stillExists = url.path.withCString { lstat($0, &value) } == 0
        let errors = measurement.inaccessibleItemCount + (stillExists ? 0 : 1)
        return result(measurement.allocatedBytes, errors: errors,
                      paths: stillExists ? measurement.inaccessiblePaths : [url.path],
                      note: errors > 0 ? "읽지 못한 항목이 있어 전체 휴지통 용량은 확인하지 못했습니다." : "현재 사용자 휴지통만 측정했습니다. 다른 사용자와 외장 디스크의 휴지통은 포함하지 않습니다.")
    }
}
