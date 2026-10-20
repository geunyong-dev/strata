import XCTest
@testable import Strata

final class CleanupSpaceChangeTests: XCTestCase {
    private func run(_ before: Int64?, _ after: Int64?, version: Int? = 1) -> CleanupRunSummary {
        CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
                          availableBytesBefore: before, availableBytesAfter: after, results: [],
                          spaceMeasurementVersion: version)
    }

    func testSignedChangeAndZeroAreDistinct() {
        XCTAssertEqual(run(100, 200).spaceChangeBytes, 100)
        XCTAssertTrue(run(100, 200).spaceChangeText.hasPrefix("+"))
        XCTAssertEqual(run(120764948480, 120764207104).spaceChangeBytes, -741376)
        XCTAssertTrue(run(200, 100).spaceChangeText.hasPrefix("−"))
        XCTAssertEqual(run(100, 100).spaceChangeText, "변화 없음")
        XCTAssertEqual(run(0, 0).spaceChangeBytes, 0)
        XCTAssertEqual(run(Int64.max, 0).spaceChangeBytes, -Int64.max)
        XCTAssertFalse(run(Int64.max, 0).spaceChangeText.isEmpty)
    }

    func testMissingAndLegacyZeroAreNotClaimedAsMeasured() {
        for value in [run(nil, 100), run(100, nil), run(-1, 100), run(0, 100, version: nil)] {
            XCTAssertNil(value.spaceChangeBytes)
            XCTAssertEqual(value.spaceChangeText, "측정 불가")
        }
        XCTAssertEqual(run(200, 100, version: nil).spaceChangeBytes, -100)
    }

    func testLegacyRecordDecodesWithoutRewriting() throws {
        let data = Data(#"{"id":"11111111-1111-1111-1111-111111111111","startedAt":"2026-09-18T08:20:00Z","finishedAt":"2026-09-18T08:23:13Z","availableBytesBefore":120764948480,"availableBytesAfter":120764207104,"results":[{"actionID":"project:example","title":"example","status":"succeeded","message":"휴지통으로 이동했습니다: /example"}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(CleanupRunSummary.self, from: data)
        XCTAssertEqual(summary.spaceChangeBytes, -741376)
        XCTAssertEqual(summary.movedToTrashCount, 1)
        XCTAssertNil(summary.spaceMeasurementVersion)
    }

    func testTrashCountOnlyIncludesSuccessfulMoves() {
        let rows: [CleanupExecutionItemResult] = [
            .init(actionID: "1", title: "1", status: .succeeded, message: "Done", method: .trash),
            .init(actionID: "2", title: "2", status: .failed, message: "휴지통으로 이동했습니다", method: .trash),
            .init(actionID: "3", title: "3", status: .skipped, message: "Skipped", method: .trash),
            .init(actionID: "4", title: "4", status: .succeeded, message: "Done", method: .toolCleanup),
            .init(actionID: "5", title: "5", status: .succeeded, message: "휴지통으로 이동했습니다: /example")
        ]
        XCTAssertEqual(rows.filter(\.wasMovedToTrash).count, 2)
    }

    func testNewMissingMeasurementAndMethodRoundTrip() throws {
        let summary = CleanupRunSummary(id: UUID(), startedAt: Date(), finishedAt: Date(),
            availableBytesBefore: nil, availableBytesAfter: 0,
            results: [.init(actionID: "1", title: "1", status: .succeeded, message: "Done", method: .trash)],
            spaceMeasurementVersion: 1)
        let decoded = try JSONDecoder().decode(CleanupRunSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertNil(decoded.spaceChangeBytes)
        XCTAssertEqual(decoded.measuredCapacity(decoded.availableBytesAfter), 0)
        XCTAssertEqual(decoded.movedToTrashCount, 1)
    }
}
