import Foundation

actor StorageAnalyzer {
    private let scanner = FileSystemScanner()
    private let permissionInspector = PermissionInspector()
    private let developerDiagnosticAnalyzer = DeveloperDiagnosticAnalyzer()
    private let projectArtifactAnalyzer = ProjectArtifactAnalyzer()

    func scan(startedAt: Date = Date(), includeAdministrator: Bool = false,
              onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> ScanSnapshot {
        try Task.checkCancellation()
        var progress = ScanProgress(startedAt: startedAt, volume: volumeUsage())
        onProgress(progress)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let excluded = ToolchainCatalog.excludedRelativePaths.map {
            home.appending(path: $0, directoryHint: .isDirectory)
        }
        let scanner = self.scanner
        progress = scanVolumeAreas(with: scanner, progress: progress, onProgress: onProgress)
        try Task.checkCancellation()
        var administratorReport: AdministratorScanReport?
        if includeAdministrator {
            progress.phase = "관리자 정밀 검사"
            progress.currentPath = "macOS 인증 후 시스템 영역을 다시 측정합니다. 최대 3분 정도 걸리며 완료 후 코어 시료에 반영됩니다."
            progress.updatedAt = Date()
            onProgress(progress)
            let result = AdministratorScan().refine(progress.areas)
            progress.areas = result.0
            administratorReport = result.1
            progress.updatedAt = Date()
            onProgress(progress)
            try Task.checkCancellation()
        }
        let volumeAreas = progress.areas.sorted { $0.allocatedBytes > $1.allocatedBytes }
        progress.phase = "접근 권한 확인"
        progress.currentPath = "보호 폴더 읽기 권한"
        progress.updatedAt = Date()
        onProgress(progress)
        let diskAccess = permissionInspector.inspect()
        progress.phase = "개발 도구 진단"
        progress.currentPath = "Docker · Xcode 응답 대기"
        progress.updatedAt = Date()
        onProgress(progress)
        let diagnostics = developerDiagnosticAnalyzer.scan()
        try Task.checkCancellation()
        progress.phase = "프로젝트 산출물 검사"
        progress.currentPath = "프로젝트 검색 위치 확인"
        progress.updatedAt = Date()
        onProgress(progress)
        let projectArtifacts = projectArtifactAnalyzer.scan(onProgress: { path in
            progress.currentPath = path
            progress.updatedAt = Date()
            onProgress(progress)
        })
        try Task.checkCancellation()
        progress.phase = "툴체인 캐시 검사"
        progress.currentPath = "개발 도구별 캐시 분석"
        progress.updatedAt = Date()
        onProgress(progress)

        var usages: [ToolchainUsage] = []
        await withTaskGroup(of: ToolchainUsage.self) { group in
            for definition in ToolchainCatalog.definitions {
                group.addTask {
                    let clock = ContinuousClock()
                    let start = clock.now
                    let urls = definition.relativePaths.map {
                        home.appending(path: $0, directoryHint: .isDirectory)
                    }
                    let measurement = scanner.measure(urls: urls, excludedURLs: excluded)
                    return ToolchainUsage(
                        definition: definition,
                        allocatedBytes: measurement.allocatedBytes,
                        scannedPaths: urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.path),
                        inaccessibleItemCount: measurement.inaccessibleItemCount,
                        scanDuration: start.duration(to: clock.now)
                    )
                }
            }
            for await usage in group {
                usages.append(usage)
                progress.currentPath = "\(usage.definition.name) 완료 · \(usages.count)/\(ToolchainCatalog.definitions.count)"
                progress.updatedAt = Date()
                onProgress(progress)
            }
        }

        try Task.checkCancellation()
        progress.phase = "미분류 공간 진단"
        progress.currentPath = "APFS 볼륨 · 스냅샷 읽기 전용 확인"
        progress.updatedAt = Date()
        onProgress(progress)
        let spaceDiagnostics = SpaceDiagnosticAnalyzer().scan()
        try Task.checkCancellation()
        return ScanSnapshot(
            volume: volumeUsage(),
            volumeAreas: volumeAreas,
            diskAccess: diskAccess,
            diagnostics: diagnostics,
            projectArtifacts: projectArtifacts,
            usages: usages.sorted { $0.allocatedBytes > $1.allocatedBytes },
            startedAt: startedAt,
            finishedAt: Date(),
            spaceDiagnostics: spaceDiagnostics,
            administratorScan: administratorReport
        )
    }

    private func scanVolumeAreas(with scanner: FileSystemScanner, progress initial: ScanProgress,
                                 onProgress: @escaping @Sendable (ScanProgress) -> Void) -> ScanProgress {
        var progress = initial
        let dataVolume = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        let root = FileManager.default.fileExists(atPath: dataVolume.path)
            ? dataVolume
            : URL(fileURLWithPath: "/", isDirectory: true)

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let children: [URL]
        do { children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) } catch {
            ScanLogContext.error(path: root.path, operation: "volume_roots", error: error as NSError)
            children = []
        }
        let dataVolumeDevice = scanner.deviceID(for: root)
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash", directoryHint: .isDirectory)
        let trashExclusions = TrashAnalyzer.exclusions(for: trashURL, dataRoot: root)

        let targets = children.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isSymbolicLink != true && scanner.deviceID(for: url) == dataVolumeDevice
        }.sorted { $0.path < $1.path }
        progress.totalAreaCount = targets.count + 1
        progress.phase = "저장공간 검사"
        var completed: [VolumeAreaUsage] = []
        var completedItems = 0
        for url in targets {
            if Task.isCancelled { break }
            let presentation = Self.areaPresentation(for: url.lastPathComponent)
            let path = displayPath(for: url.path, dataRoot: root.path)
            let measurement = scanner.measure(urls: [url], excludedURLs: trashExclusions, onProgress: { partial in
                progress.currentPath = self.displayPath(for: partial.currentPath, dataRoot: root.path)
                progress.visitedItemCount = completedItems + partial.visitedItemCount
                progress.updatedAt = Date()
                progress.areas = completed + [VolumeAreaUsage(name: presentation.name, path: path,
                    symbol: presentation.symbol, allocatedBytes: partial.allocatedBytes,
                    inaccessibleItemCount: 0, inaccessiblePaths: [])]
                onProgress(progress)
            })
            if Task.isCancelled { break }
            completedItems = progress.visitedItemCount
            completed.append(VolumeAreaUsage(
                name: presentation.name,
                path: displayPath(for: url.path, dataRoot: root.path),
                symbol: presentation.symbol,
                allocatedBytes: measurement.allocatedBytes,
                inaccessibleItemCount: measurement.inaccessibleItemCount,
                inaccessiblePaths: measurement.inaccessiblePaths
            ))
            progress.completedAreaCount = completed.count
            progress.areas = completed
            progress.updatedAt = Date()
            onProgress(progress)
        }
        if !Task.isCancelled {
            progress.phase = "휴지통 검사"
            progress.currentPath = trashURL.path
            progress.updatedAt = Date()
            onProgress(progress)
            let trash = TrashAnalyzer().measure(at: trashURL, expectedDevice: dataVolumeDevice) { partial in
                progress.currentPath = partial.currentPath
                progress.visitedItemCount = completedItems + partial.visitedItemCount
                progress.updatedAt = Date()
                progress.areas = completed + [VolumeAreaUsage(name: "휴지통", path: trashURL.path, symbol: "trash",
                    allocatedBytes: partial.allocatedBytes, inaccessibleItemCount: 0, inaccessiblePaths: [], isTrash: true)]
                onProgress(progress)
            }
            if !Task.isCancelled {
                completed.append(trash)
                progress.areas = completed
                progress.completedAreaCount = completed.count
                progress.updatedAt = Date()
                onProgress(progress)
            }
        }
        return progress
    }

    private func displayPath(for path: String, dataRoot: String) -> String {
        guard dataRoot == "/System/Volumes/Data", path.hasPrefix(dataRoot) else { return path }
        let suffix = String(path.dropFirst(dataRoot.count))
        return suffix.isEmpty ? "/" : suffix
    }

    static func areaPresentation(for component: String) -> (name: String, symbol: String) {
        switch component {
        case "Applications": ("앱 폴더", "app.fill")
        case "Users": ("사용자", "person.2.fill")
        case "Library": ("공용 라이브러리", "books.vertical.fill")
        case "System": ("시스템 폴더", "gearshape.2.fill")
        case "private": ("시스템 및 임시 데이터", "internaldrive.fill")
        case "opt", "usr": (component, "terminal.fill")
        case "Volumes": ("마운트 지점", "externaldrive.fill")
        case ".Spotlight-V100": ("Spotlight 검색 데이터", "magnifyingglass")
        case ".DocumentRevisions-V100": ("문서 변경 이력", "clock.arrow.circlepath")
        case ".fseventsd": ("파일 변경 기록", "list.bullet.rectangle")
        default: (component, "folder.fill")
        }
    }

    private func volumeUsage() -> VolumeUsage {
        var home = FileManager.default.homeDirectoryForCurrentUser
        home.removeAllCachedResourceValues()
        let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey, .volumeUUIDStringKey
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? Int64(values?.volumeAvailableCapacity ?? 0)
        return VolumeUsage(totalBytes: total, availableBytes: available,
                           physicalAvailableBytes: values?.volumeAvailableCapacity.map { Int64($0) },
                           importantAvailableBytes: values?.volumeAvailableCapacityForImportantUsage,
                           volumeUUID: values?.volumeUUIDString)
    }
}
