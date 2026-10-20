import XCTest
@testable import Strata

final class DeveloperDiagnosticParserTests: XCTestCase {
    func testParsesDockerSystemDFRowsAndReclaimablePercentage() throws {
        let input = """
        {"Active":"4","Reclaimable":"17.09GB (58%)","Size":"29.21GB","TotalCount":"16","Type":"Images"}
        {"Active":"0","Reclaimable":"20.56GB","Size":"20.56GB","TotalCount":"64","Type":"Build Cache"}
        """

        let resources = try DockerSystemDFParser.parse(input)
        XCTAssertEqual(resources.count, 2)
        XCTAssertEqual(resources[0].type, "Images")
        XCTAssertEqual(resources[0].sizeBytes, 29_210_000_000)
        XCTAssertEqual(resources[0].reclaimableBytes, 17_090_000_000)
        XCTAssertEqual(resources[1].totalCount, 64)
    }

    func testParsesBinaryAndDecimalByteSizes() {
        XCTAssertEqual(ByteSizeParser.parse("1.5GB"), 1_500_000_000)
        XCTAssertEqual(ByteSizeParser.parse("1.5 GiB"), 1_610_612_736)
        XCTAssertEqual(ByteSizeParser.parse("0B"), 0)
    }

    func testParsesSimulatorRuntimeJSON() throws {
        let input = """
        {
          "RUNTIME-ID": {
            "build": "23C54",
            "deletable": true,
            "identifier": "RUNTIME-ID",
            "lastUsedAt": "2026-01-26T08:58:51Z",
            "platformIdentifier": "com.apple.platform.iphonesimulator",
            "sizeBytes": 8381044573,
            "state": "Ready",
            "version": "26.2"
          }
        }
        """

        let runtimes = try SimulatorRuntimeParser.parse(input)
        XCTAssertEqual(runtimes.count, 1)
        XCTAssertEqual(runtimes[0].platform, "iOS")
        XCTAssertEqual(runtimes[0].sizeBytes, 8_381_044_573)
        XCTAssertNotNil(runtimes[0].lastUsedAt)
    }

    func testParsesSimulatorDeviceAvailability() throws {
        let input = """
        {"devices":{"runtime":[{"isAvailable":true},{"isAvailable":false},{}]}}
        """

        let summary = try SimulatorDeviceParser.parse(input)
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.unavailable, 1)
    }
}
