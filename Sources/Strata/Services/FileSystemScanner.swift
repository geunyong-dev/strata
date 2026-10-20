import Foundation
import Darwin

struct DirectoryMeasurement: Sendable {
    let allocatedBytes: Int64
    let inaccessibleItemCount: Int
    let inaccessiblePaths: [String]
}

struct DirectoryScanProgress: Sendable {
    let allocatedBytes: Int64
    let visitedItemCount: Int
    let currentPath: String
}

struct FileSystemScanner: Sendable {
    typealias EnumerationFactory = (URL, @escaping (URL, Error) -> Bool) -> FileManager.DirectoryEnumerator?

    static func makeEnumerator(at root: URL, onError: @escaping (URL, Error) -> Bool) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [], errorHandler: onError)
    }
    private struct FileIdentity: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    func measure(urls: [URL], excludedURLs: [URL] = [],
                 makeEnumerator: EnumerationFactory = FileSystemScanner.makeEnumerator,
                 onProgress: (DirectoryScanProgress) -> Void = { _ in }) -> DirectoryMeasurement {
        var total: Int64 = 0
        var visited = 0
        var currentPath = urls.first?.path ?? ""
        var lastReport = Date.distantPast
        func report(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastReport) >= 0.25 else { return }
            lastReport = now
            onProgress(DirectoryScanProgress(allocatedBytes: total, visitedItemCount: visited, currentPath: currentPath))
        }
        report(force: true)
        var inaccessiblePaths = Set<String>()
        var visitedFiles = Set<FileIdentity>()
        var visitedDirectories = Set<FileIdentity>()
        let excluded = excludedURLs.map { canonicalPath($0.path) }

        for root in urls where FileManager.default.fileExists(atPath: root.path) {
            if Task.isCancelled { break }
            currentPath = root.path
            visited += 1
            let rootPath = root.standardizedFileURL.path
            let canonicalRootPath = canonicalPath(rootPath)
            guard !isExcluded(canonicalRootPath, excluded: excluded) else { continue }
            guard let rootStat = fileStat(root) else {
                inaccessiblePaths.insert(canonicalRootPath)
                continue
            }

            let rootDevice = UInt64(rootStat.st_dev)
            let rootIdentity = FileIdentity(device: rootDevice, inode: UInt64(rootStat.st_ino))
            let rootMode = rootStat.st_mode & S_IFMT
            if rootMode == S_IFLNK { continue }
            if rootMode != S_IFDIR {
                if visitedFiles.insert(rootIdentity).inserted {
                    total += Int64(rootStat.st_blocks) * 512
                }
                continue
            }
            guard visitedDirectories.insert(rootIdentity).inserted else { continue }

            // Retry the enumeration after EINTR. Restore directory traversal state, but
            // retain file identities so an already measured file is never added twice.
            let directoriesBeforeTraversal = visitedDirectories
            var attempt = 0
            var retryEnumeration = false
            repeat {
            retryEnumeration = false
            visitedDirectories = directoriesBeforeTraversal
            var attemptErrors = Set<String>()
            guard let enumerator = makeEnumerator(root, { url, error in
                    ScanLogContext.error(path: url.path, operation: "enumerate", error: error as NSError)
                    attemptErrors.insert(canonicalPath(url.path))
                    if InterruptedReadRetry.isInterrupted(error as NSError) { retryEnumeration = true }
                    else { inaccessiblePaths.insert(canonicalPath(url.path)) }
                    return true
                }) else {
                inaccessiblePaths.insert(canonicalRootPath)
                break
            }

            for case let itemURL as URL in enumerator {
                if Task.isCancelled { break }
                visited += 1
                currentPath = itemURL.path
                report()
                let itemPath = itemURL.standardizedFileURL.path
                let canonicalItemPath: String
                if itemPath.hasPrefix(rootPath + "/") {
                    canonicalItemPath = canonicalRootPath + itemPath.dropFirst(rootPath.count)
                } else {
                    canonicalItemPath = canonicalPath(itemPath)
                }
                guard let stat = fileStat(itemURL) else {
                    attemptErrors.insert(canonicalItemPath)
                    continue
                }
                let mode = stat.st_mode & S_IFMT
                // DirectoryEnumerator already avoids following symbolic links. Calling
                // skipDescendants on a non-directory can skip unrelated pending children.
                if mode == S_IFLNK { continue }
                if isExcluded(canonicalItemPath, excluded: excluded) {
                    if mode == S_IFDIR { enumerator.skipDescendants() }
                    continue
                }

                // Never cross into another mounted filesystem. This avoids counting
                // mounted simulator runtimes and disk images through their mount path.
                guard UInt64(stat.st_dev) == rootDevice else {
                    if mode == S_IFDIR { enumerator.skipDescendants() }
                    continue
                }

                let identity = FileIdentity(device: UInt64(stat.st_dev), inode: UInt64(stat.st_ino))
                if mode == S_IFDIR {
                    if !visitedDirectories.insert(identity).inserted {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                // st_blocks is allocated 512-byte blocks and correctly avoids
                // inflating sparse files. Device + inode deduplicates hard links.
                if visitedFiles.insert(identity).inserted {
                    total += Int64(stat.st_blocks) * 512
                }
            }
            if retryEnumeration && attempt < InterruptedReadRetry.maximumRetries && !Task.isCancelled {
                attempt += 1
                ScanLogContext.current?.write("read_retry", ["path": root.path, "operation": "enumerate", "attempt": attempt])
            } else {
                inaccessiblePaths.formUnion(attemptErrors)
                retryEnumeration = false
            }
            } while retryEnumeration
        }

        report(force: true)
        return .init(
            allocatedBytes: total,
            inaccessibleItemCount: inaccessiblePaths.count,
            inaccessiblePaths: Array(inaccessiblePaths).sorted().prefix(50).map { $0 }
        )
    }

    func deviceID(for url: URL) -> UInt64? {
        fileStat(url).map { UInt64($0.st_dev) }
    }

    private func fileStat(_ url: URL) -> stat? {
        var value = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            let outcome = InterruptedReadRetry.run { lstat(path, &value) }
            if outcome.retries > 0 {
                ScanLogContext.current?.write("read_retry", ["path": url.path, "operation": "lstat", "attempt": outcome.retries])
            }
            guard outcome.result == 0 else {
                ScanLogContext.posix(path: url.path, operation: "lstat", code: outcome.error)
                return nil
            }
            return value
        }
    }

    private func isExcluded(_ path: String, excluded: [String]) -> Bool {
        excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
