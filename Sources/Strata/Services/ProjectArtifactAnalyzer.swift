import Foundation
import Darwin

struct ProjectArtifactAnalyzer: Sendable {
    private let scanner = FileSystemScanner()
    private let maximumSearchDepth = 8

    func scan(roots requestedRoots: [URL]? = nil, onProgress: (String) -> Void = { _ in }) -> ProjectArtifactReport {
        let roots = requestedRoots ?? defaultRoots()
        var artifacts: [ProjectArtifact] = []
        var inaccessibleCount = 0
        var lastReport = Date.distantPast

        for root in roots {
            if Task.isCancelled { break }
            onProgress(root.path)
            guard let rootDevice = scanner.deviceID(for: root) else {
                inaccessibleCount += 1
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [],
                errorHandler: { url, error in
                    ScanLogContext.error(path: url.path, operation: "project_enumerate", error: error as NSError)
                    inaccessibleCount += 1
                    return true
                }
            ) else {
                inaccessibleCount += 1
                continue
            }

            for case let url as URL in enumerator {
                if Task.isCancelled { break }
                if Date().timeIntervalSince(lastReport) >= 0.25 {
                    lastReport = Date()
                    onProgress(url.path)
                }
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
                ])
                if values?.isSymbolicLink == true { continue }
                guard values?.isDirectory == true else { continue }

                if scanner.deviceID(for: url) != rootDevice {
                    enumerator.skipDescendants()
                    continue
                }

                let directoryName = url.lastPathComponent
                if ProjectArtifactCatalog.ignoredDirectoryNames.contains(directoryName) {
                    enumerator.skipDescendants()
                    continue
                }

                if let definition = definition(for: directoryName) {
                    // Capture before enumerating this candidate: enumeration can update atime.
                    var metadata = stat()
                    let hasMetadata = url.path.withCString { lstat($0, &metadata) } == 0
                    func date(_ value: timespec) -> Date? {
                        guard hasMetadata, value.tv_sec > 0 else { return nil }
                        return Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000)
                    }
                    let createdAt = date(metadata.st_birthtimespec)
                    let modifiedAt = date(metadata.st_mtimespec)
                    let accessedAt = date(metadata.st_atimespec)
                    let measurement = scanner.measure(urls: [url], onProgress: { onProgress($0.currentPath) })
                    artifacts.append(ProjectArtifact(
                        definition: definition,
                        path: url.path,
                        projectName: projectName(for: url, root: root),
                        allocatedBytes: measurement.allocatedBytes,
                        modifiedAt: modifiedAt,
                        inaccessibleItemCount: measurement.inaccessibleItemCount,
                        createdAt: createdAt,
                        accessedAt: accessedAt,
                        evidence: ArtifactEvidence.inspect(url, definitionID: definition.id)
                    ))
                    inaccessibleCount += measurement.inaccessibleItemCount
                    enumerator.skipDescendants()
                    continue
                }

                if enumerator.level >= maximumSearchDepth {
                    enumerator.skipDescendants()
                }
            }
        }

        return ProjectArtifactReport(
            scannedRoots: roots.map(\.path),
            artifacts: artifacts.sorted { $0.allocatedBytes > $1.allocatedBytes },
            inaccessibleItemCount: inaccessibleCount
        )
    }

    private func definition(for directoryName: String) -> ProjectArtifactDefinition? {
        ProjectArtifactCatalog.definitions.first { $0.directoryNames.contains(directoryName) }
    }

    private func projectName(for artifactURL: URL, root: URL) -> String {
        let parent = artifactURL.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? root.lastPathComponent : parent
    }

    private func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let relativePaths = [
            "Documents/workspace", "Developer", "Projects", "Code", "src", "workspace"
        ]
        var seen = Set<String>()
        return relativePaths.compactMap { relativePath in
            let url = home.appending(path: relativePath, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(canonicalPath).inserted else { return nil }
            return url
        }
    }
}
