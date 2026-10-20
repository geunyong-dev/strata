import XCTest
@testable import Strata

final class DashboardViewModelTests: XCTestCase {
    @MainActor
    func testUnknownSelectionIsIgnoredBeforeScan() {
        let model = DashboardViewModel()
        model.toggleCleanupAction("unknown")
        model.setCleanupGroupSelected(.safe, selected: true)
        XCTAssertTrue(model.selectedCleanupActionIDs.isEmpty)
        XCTAssertFalse(model.canExecuteCleanup)
    }

    @MainActor
    func testVerificationAndExecutionCannotStartBeforeScan() async {
        let model = DashboardViewModel()
        await model.runDryRun()
        await model.executeCleanup()
        XCTAssertFalse(model.isRunningDryRun)
        XCTAssertFalse(model.isExecutingCleanup)
        XCTAssertTrue(model.dryRunResults.isEmpty)
        XCTAssertFalse(model.canExecuteCleanup)
    }
}
