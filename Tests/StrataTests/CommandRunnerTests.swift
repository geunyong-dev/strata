import XCTest
@testable import Strata

final class CommandRunnerTests: XCTestCase {
    func testCapturesOutputAndExitCodeSeparately() {
        let result = CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'output'; printf 'diagnostic' >&2; exit 7"])
        XCTAssertEqual(result.standardOutput, "output")
        XCTAssertEqual(result.standardError, "diagnostic")
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertFalse(result.timedOut)
    }

    func testConcurrentCommandsKeepTheirOwnOutput() async {
        let results = await withTaskGroup(of: (String, CommandOutput).self) { group in
            for index in 0..<12 {
                let marker = "command-\(index)"
                group.addTask {
                    // Fixed test script; marker is a positional argument, not interpolated shell code.
                    let result = CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", "printf '%s' \"$1\"; /bin/sleep 0.1; printf '%s' \"$1\" >&2", "test", marker])
                    return (marker, result)
                }
            }
            var results: [(String, CommandOutput)] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(results.count, 12)
        for (marker, result) in results {
            XCTAssertEqual(result.standardOutput, marker)
            XCTAssertEqual(result.standardError, marker)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.timedOut)
        }
    }

    func testTimeoutStopsAnUnresponsiveCommand() {
        let start = ContinuousClock.now
        let result = CommandRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                         arguments: ["5"], timeout: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testMissingExecutableReturnsFailure() {
        let result = CommandRunner().run(executable: URL(fileURLWithPath: "/nonexistent-strata-test/command"), arguments: [])
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertFalse(result.standardError.isEmpty)
        XCTAssertFalse(result.timedOut)
    }
}
