import Foundation
import Darwin

struct PermissionInspector: Sendable {
    func inspect() -> DiskAccessReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "Library/Mail",
            "Library/Messages",
            "Library/Safari",
            "Library/Application Support/AddressBook",
            "Library/Application Support/CallHistoryDB"
        ].map { home.appending(path: $0, directoryHint: .isDirectory) }

        var checked: [String] = []
        var denied: [String] = []

        for url in candidates {
            switch probe(url) {
            case .readable:
                checked.append(url.path)
            case .denied:
                checked.append(url.path)
                denied.append(url.path)
            case .missing:
                continue
            }
        }

        let state: DiskAccessState
        if !denied.isEmpty {
            state = .limited
        } else if !checked.isEmpty {
            state = .available
        } else {
            state = .unknown
        }
        return DiskAccessReport(state: state, checkedPaths: checked, deniedPaths: denied)
    }

    private enum ProbeResult {
        case readable
        case denied
        case missing
    }

    private func probe(_ url: URL) -> ProbeResult {
        var value = stat()
        let statResult = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &value)
        }
        guard statResult == 0 else {
            let code = errno
            ScanLogContext.posix(path: url.path, operation: "permission_lstat", code: code)
            return code == EACCES || code == EPERM ? .denied : .missing
        }

        guard (value.st_mode & S_IFMT) == S_IFDIR else { return .readable }
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return .missing }
            errno = 0
            guard let directory = opendir(path) else {
                let code = errno
                ScanLogContext.posix(path: url.path, operation: "permission_opendir", code: code)
                return code == EACCES || code == EPERM ? .denied : .missing
            }
            defer { closedir(directory) }
            errno = 0
            _ = readdir(directory)
            let code = errno
            if code != 0 { ScanLogContext.posix(path: url.path, operation: "permission_readdir", code: code) }
            return code == EACCES || code == EPERM ? .denied : .readable
        }
    }
}
