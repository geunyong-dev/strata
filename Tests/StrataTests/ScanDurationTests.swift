import XCTest
@testable import Strata

final class ScanDurationTests: XCTestCase {
    func testDurationFormattingAndBoundaries() {
        let start = Date(timeIntervalSince1970: 1000)
        for (interval, expected) in [(-1.0, "0초"), (0, "0초"), (0.9, "0초"), (59, "59초"),
                                      (60, "1분 0초"), (125, "2분 5초"), (3599, "59분 59초"),
                                      (3600, "1시간 0분 0초"), (3661, "1시간 1분 1초")] {
            XCTAssertEqual(ScanDuration.text(from: start, to: start.addingTimeInterval(interval)), expected)
        }
    }

    @MainActor
    func testTimerStartsBeforeFirstProgressAndResetsForNextScan() async {
        let model = DashboardViewModel(scanOperation: { _ in
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        })
        XCTAssertNil(model.scanStartedAt)
        let first = Task { await model.scan() }
        while !model.isScanning { await Task.yield() }
        let start = model.scanStartedAt
        XCTAssertNotNil(start)
        XCTAssertNil(model.scanProgress)
        model.cancelScan()
        await first.value
        let second = Task { await model.scan() }
        while !model.isScanning { await Task.yield() }
        XCTAssertGreaterThanOrEqual(model.scanStartedAt ?? .distantPast, start ?? .distantFuture)
        model.cancelScan()
        await second.value
    }
}
