import Foundation
import Darwin

public struct ReadOnlyMeasurement: Codable, Sendable {
    public let path: String
    public let bytes: Int64
    public let unreadablePaths: [String]
    public let unreadableCount: Int
    public let visited: Int
    public let complete: Bool
    public let errorCodes: [String: Int32]

    public init(path: String, bytes: Int64, unreadablePaths: [String], unreadableCount: Int,
                visited: Int, complete: Bool, errorCodes: [String: Int32] = [:]) {
        self.path = path; self.bytes = bytes; self.unreadablePaths = unreadablePaths
        self.unreadableCount = unreadableCount; self.visited = visited; self.complete = complete
        self.errorCodes = errorCodes
    }
}

public struct ReadOnlyScanResponse: Codable, Sendable {
    public let version: Int
    public let effectiveUID: UInt32
    public let results: [ReadOnlyMeasurement]
    public init(version: Int = 1, effectiveUID: UInt32, results: [ReadOnlyMeasurement]) {
        self.version = version; self.effectiveUID = effectiveUID; self.results = results
    }
}

public enum ReadOnlyScanScope {
    // Deliberately no arbitrary scan-root argument, user home, external volumes, or cleanup commands.
    public static let paths = [
        "/System/Volumes/Data/.fseventsd",
        "/System/Volumes/Data/.Spotlight-V100",
        "/System/Volumes/Data/.DocumentRevisions-V100",
        "/System/Volumes/Data/Library",
        "/System/Volumes/Data/private",
        "/System/Volumes/Data/System"
    ]
    public static func displayPath(_ path: String) -> String {
        String(path.dropFirst("/System/Volumes/Data".count))
    }
}

/// Descriptor-relative traversal: never follows links or opens file contents.
/// The CLI constrains the roots; the injectable stop predicate allows fixture tests.
public struct ReadOnlyDirectoryScanner {
    public init() {}

    public func measure(path: String, maxEntries: Int = 2_000_000,
                        shouldStop: () -> Bool = { false }) -> ReadOnlyMeasurement {
        struct Identity: Hashable { let device: Int32; let inode: UInt64 }
        var seen = Set<Identity>()
        var errors: [String: Int32] = [:]
        var bytes: Int64 = 0
        var visited = 0
        var complete = true
        let rootFD = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else {
            let code = errno
            return .init(path: path, bytes: 0, unreadablePaths: [path], unreadableCount: 1, visited: 0, complete: true, errorCodes: [path: code])
        }
        var rootStat = stat()
        guard fstat(rootFD, &rootStat) == 0 else {
            let code = errno
            close(rootFD)
            return .init(path: path, bytes: 0, unreadablePaths: [path], unreadableCount: 1, visited: 0, complete: true, errorCodes: [path: code])
        }
        let device = rootStat.st_dev

        func walk(_ fd: Int32, _ currentPath: String, _ depth: Int) {
            // fdopendir takes ownership of fd, including on recursive calls.
            guard let directory = fdopendir(fd) else { let code = errno; close(fd); errors[currentPath] = code; return }
            defer { closedir(directory) }
            while true {
                if shouldStop() || visited >= maxEntries { complete = false; return }
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { errors[currentPath] = errno }
                    return
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                visited += 1
                let childPath = currentPath + "/" + name
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                    errors[childPath] = errno; continue
                }
                let kind = info.st_mode & S_IFMT
                if kind == S_IFLNK || info.st_dev != device { continue }
                let identity = Identity(device: info.st_dev, inode: info.st_ino)
                if kind == S_IFDIR {
                    guard depth < 128 else { errors[childPath] = ELOOP; continue }
                    guard !seen.contains(identity) else { continue }
                    let childFD = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard childFD >= 0 else { errors[childPath] = errno; continue }
                    var opened = stat()
                    // Reject a replaced directory or mount between stat and open.
                    guard fstat(childFD, &opened) == 0, opened.st_dev == device,
                          opened.st_ino == info.st_ino else {
                        close(childFD); errors[childPath] = ESTALE; continue
                    }
                    seen.insert(identity)
                    walk(childFD, childPath, depth + 1)
                    if !complete { return }
                } else if seen.insert(identity).inserted {
                    let (allocated, blockOverflow) = Int64(info.st_blocks).multipliedReportingOverflow(by: 512)
                    let (next, totalOverflow) = bytes.addingReportingOverflow(allocated)
                    guard !blockOverflow, !totalOverflow, allocated >= 0 else { complete = false; return }
                    bytes = next
                }
            }
        }
        seen.insert(Identity(device: device, inode: rootStat.st_ino))
        walk(rootFD, path, 0)
        let samples = Array(errors.keys.sorted().prefix(1000))
        return .init(path: path, bytes: bytes, unreadablePaths: samples,
                     unreadableCount: errors.count, visited: visited, complete: complete,
                     errorCodes: Dictionary(uniqueKeysWithValues: samples.map { ($0, errors[$0]!) }))
    }
}
