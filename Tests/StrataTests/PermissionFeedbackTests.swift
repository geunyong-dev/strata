import XCTest
@testable import Strata

final class PermissionFeedbackTests: XCTestCase {
    func testStatesHaveDistinctActionableFeedback() {
        XCTAssertTrue(PermissionFeedback.resultText(.available).contains("계속 진행"))
        XCTAssertTrue(PermissionFeedback.resultText(.limited).contains("제한"))
        XCTAssertTrue(PermissionFeedback.resultText(.unknown).contains("판단하지 못했"))
        XCTAssertTrue(PermissionFeedback.resultText(nil).contains("아직 확인 결과"))
    }

    func testRescanNoticeOnlyAppliesToOlderSnapshot() {
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(PermissionFeedback.needsRescan(recheckedAt: nil, scanFinishedAt: date))
        XCTAssertFalse(PermissionFeedback.needsRescan(recheckedAt: date, scanFinishedAt: nil))
        XCTAssertTrue(PermissionFeedback.needsRescan(recheckedAt: date, scanFinishedAt: date.addingTimeInterval(-1)))
        XCTAssertFalse(PermissionFeedback.needsRescan(recheckedAt: date, scanFinishedAt: date.addingTimeInterval(1)))
    }
}
