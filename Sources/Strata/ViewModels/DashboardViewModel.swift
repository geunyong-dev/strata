import Foundation

@MainActor
@Observable
final class DashboardViewModel {
    enum State {
        case idle
        case scanning
        case loaded(ScanSnapshot)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var scanProgress: ScanProgress?
    private(set) var scanStartedAt: Date?
    private(set) var scanLogWarning: String?
    private(set) var cleanupActions: [CleanupAction] = []
    private(set) var selectedCleanupActionIDs = Set<String>()
    private(set) var dryRunResults: [String: DryRunResult] = [:]
    private(set) var isRunningDryRun = false
    private(set) var isExecutingCleanup = false
    private(set) var cleanupHistory: [CleanupRunSummary] = []
    private(set) var isCancellingScan = false
    private(set) var scanNotice: String?
    private(set) var historyWarning: String?
    private var scanTask: Task<ScanSnapshot, Error>?
    private let scanOperation: (@Sendable (@escaping @Sendable (ScanProgress) -> Void) async throws -> ScanSnapshot)?
    private let analyzer = StorageAnalyzer()
    private let cleanupPlanBuilder = CleanupPlanBuilder()
    private let dryRunAnalyzer = CleanupDryRunAnalyzer()
    private let cleanupExecutor = CleanupExecutor()
    private let cleanupHistoryStore: CleanupHistoryStore

    init(store: CleanupHistoryStore = CleanupHistoryStore(),
         scanOperation: (@Sendable (@escaping @Sendable (ScanProgress) -> Void) async throws -> ScanSnapshot)? = nil) {
        self.scanOperation = scanOperation
        cleanupHistoryStore = store
        do { cleanupHistory = try store.loadChecked() }
        catch { historyWarning = "저장된 정리 이력을 읽지 못했습니다. 기존 파일은 변경하지 않았습니다." }
    }

    func scan(includeAdministrator: Bool = false) async {
        guard !isScanning, !isRunningDryRun, !isExecutingCleanup else { return }
        scanStartedAt = Date()
        let log = scanOperation == nil ? ScanLog(startedAt: scanStartedAt ?? Date()) : nil
        scanLogWarning = log?.warning
        log?.write("scan_mode", ["administratorRequested": includeAdministrator])
        let previousState = state
        scanNotice = nil
        dryRunResults = [:]
        state = .scanning
        scanProgress = nil
        let (updates, continuation) = AsyncStream<ScanProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let consumer = Task { @MainActor in
            for await progress in updates { self.scanProgress = progress }
        }
        let task = Task {
            if let scanOperation { return try await scanOperation { continuation.yield($0) } }
            return try await ScanLogContext.$current.withValue(log) {
                try await analyzer.scan(startedAt: scanStartedAt ?? Date(), includeAdministrator: includeAdministrator) {
                    log?.progress($0)
                    continuation.yield($0)
                }
            }
        }
        scanTask = task
        let outcome = await task.result
        switch outcome {
        case let .success(snapshot):
            if !task.isCancelled { log?.summary(snapshot) }
            log?.finish(status: task.isCancelled ? "cancelled" : "completed")
        case let .failure(error):
            log?.write("scan_error", ["domain": (error as NSError).domain, "code": (error as NSError).code])
            log?.finish(status: task.isCancelled || error is CancellationError ? "cancelled" : "failed")
        }
        scanLogWarning = log?.warning
        continuation.finish()
        await consumer.value
        scanTask = nil
        isCancellingScan = false
        scanProgress = nil
        guard case let .success(snapshot) = outcome, !task.isCancelled else {
            if case let .failure(error) = outcome, !(error is CancellationError), !task.isCancelled {
                state = .failed(error.localizedDescription)
                return
            }
            state = previousState
            scanNotice = "스캔을 중단했습니다. 중간 결과는 저장하지 않았습니다. 이전 측정이 있으면 그대로 표시합니다."
            return
        }
        cleanupActions = cleanupPlanBuilder.makeActions(
            diagnostics: snapshot.diagnostics,
            projectArtifacts: snapshot.projectArtifacts
        )
        selectedCleanupActionIDs = Set(
            cleanupActions.filter { $0.safety == .safe }.map(\.id)
        )
        dryRunResults = [:]
        state = .loaded(snapshot)
        scanProgress = nil
    }

    func cancelScan() {
        guard isScanning else { return }
        isCancellingScan = true
        scanTask?.cancel()
    }

    func toggleCleanupAction(_ id: String) {
        guard !isScanning, !isRunningDryRun, !isExecutingCleanup,
              cleanupActions.contains(where: { $0.id == id }) else { return }
        if selectedCleanupActionIDs.contains(id) {
            selectedCleanupActionIDs.remove(id)
        } else {
            selectedCleanupActionIDs.insert(id)
        }
        dryRunResults[id] = nil
    }

    func setCleanupGroupSelected(_ level: SafetyLevel, selected: Bool, onlyIDs: Set<String>? = nil) {
        guard !isScanning, !isRunningDryRun, !isExecutingCleanup else { return }
        let groupIDs = Set(cleanupActions.filter { $0.safety == level && (onlyIDs?.contains($0.id) ?? true) }.map(\.id))
        let nextIDs = selected
            ? selectedCleanupActionIDs.union(groupIDs)
            : selectedCleanupActionIDs.subtracting(groupIDs)
        for id in selectedCleanupActionIDs.symmetricDifference(nextIDs) {
            dryRunResults[id] = nil
        }
        selectedCleanupActionIDs = nextIDs
    }

    func runDryRun() async {
        guard case .loaded = state, !isRunningDryRun, !isExecutingCleanup else { return }
        let selected = cleanupActions.filter { selectedCleanupActionIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        isRunningDryRun = true
        defer { isRunningDryRun = false }
        dryRunResults = await dryRunAnalyzer.preview(selected)
    }

    func executeCleanup() async {
        guard !isExecutingCleanup, canExecuteCleanup else { return }
        guard case let .loaded(snapshot) = state else { return }
        // Execute exactly the verified, non-dangerous items listed in the confirmation.
        let selected = cleanupActions.filter {
            selectedCleanupActionIDs.contains($0.id)
                && $0.safety != .dangerous
                && dryRunResults[$0.id]?.status == .verified
        }
        isExecutingCleanup = true
        defer { isExecutingCleanup = false }
        let summary = await cleanupExecutor.execute(
            selected,
            allowedProjectRoots: snapshot.projectArtifacts.scannedRoots
        )
        cleanupHistory.insert(summary, at: 0)
        cleanupHistory = Array(cleanupHistory.prefix(50))
        do {
            try cleanupHistoryStore.save(cleanupHistory)
            historyWarning = nil
        } catch {
            historyWarning = "정리 결과를 파일에 저장하지 못했습니다. 현재 앱에서는 확인할 수 있지만 재실행 후에는 남지 않을 수 있습니다."
        }
        let succeededIDs = Set(
            summary.results.filter { $0.status == .succeeded }.map(\.actionID)
        )
        selectedCleanupActionIDs.subtract(succeededIDs)
        for id in succeededIDs {
            dryRunResults[id] = nil
        }
    }

    var selectedCleanupBytes: Int64 {
        cleanupActions
            .filter { selectedCleanupActionIDs.contains($0.id) }
            .reduce(0) { $0 + $1.estimatedBytes }
    }

    var canExecuteCleanup: Bool {
        guard case .loaded = state, !isRunningDryRun, !isExecutingCleanup else { return false }
        return cleanupActions.contains { action in
            selectedCleanupActionIDs.contains(action.id)
                && action.safety != .dangerous
                && dryRunResults[action.id]?.status == .verified
        }
    }

    var isScanning: Bool {
        if case .scanning = state { true } else { false }
    }
}
