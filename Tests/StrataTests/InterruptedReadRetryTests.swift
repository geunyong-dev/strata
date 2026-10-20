import XCTest
import Darwin
@testable import Strata

final class InterruptedReadRetryTests: XCTestCase {
    func testRetriesOnlyInterruptionAndStopsAtLimit() {
        var calls = 0
        let success = InterruptedReadRetry.run {
            calls += 1
            errno = EINTR
            return calls < 3 ? -1 : 0
        }
        XCTAssertEqual(success.result, 0)
        XCTAssertEqual(calls, 3)
        calls = 0
        let denied = InterruptedReadRetry.run { calls += 1; errno = EACCES; return -1 }
        XCTAssertEqual(denied.error, EACCES)
        XCTAssertEqual(calls, 1)
        calls = 0
        let exhausted = InterruptedReadRetry.run { calls += 1; errno = EINTR; return -1 }
        XCTAssertEqual(exhausted.error, EINTR)
        XCTAssertEqual(calls, 3)
    }

    func testEnumerationRecoveryDeduplicatesBytesAndPersistentErrors() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 8192).write(to: root.appending(path: "data"))
        let baseline = FileSystemScanner().measure(urls: [root])
        var calls = 0
        let interrupted = NSError(domain: NSCocoaErrorDomain, code: 256,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EINTR))])
        let recovered = FileSystemScanner().measure(urls: [root], makeEnumerator: { url, onError in
            calls += 1
            if calls == 1 { _ = onError(url, interrupted) }
            return FileSystemScanner.makeEnumerator(at: url, onError: onError)
        })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(recovered.allocatedBytes, baseline.allocatedBytes)
        XCTAssertEqual(recovered.inaccessibleItemCount, 0)
        calls = 0
        let denied = FileSystemScanner().measure(urls: [root], makeEnumerator: { url, onError in
            calls += 1
            for _ in 0..<3 { _ = onError(url, NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))) }
            return FileSystemScanner.makeEnumerator(at: url, onError: onError)
        })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(denied.inaccessibleItemCount, 1)
        calls = 0
        let exhausted = FileSystemScanner().measure(urls: [root], makeEnumerator: { url, onError in
            calls += 1
            _ = onError(url, interrupted)
            return FileSystemScanner.makeEnumerator(at: url, onError: onError)
        })
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(exhausted.inaccessibleItemCount, 1)
        XCTAssertEqual(exhausted.allocatedBytes, baseline.allocatedBytes)
    }

    func testCancellationDoesNotRetry() async {
        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var calls = 0
            _ = InterruptedReadRetry.run { calls += 1; errno = EINTR; return -1 }
            XCTAssertEqual(calls, 1)
        }.value
    }

    func testPermissionLabelDoesNotDependOnMeasurementErrors() {
        XCTAssertEqual(MeasurementStatusView.permissionText(.available), "보호 폴더 읽기 확인됨")
        XCTAssertEqual(MeasurementStatusView.permissionText(.limited), "일부 보호 폴더 접근 제한")
        XCTAssertEqual(MeasurementStatusView.permissionText(.unknown), "보호 폴더 읽기 확인 필요")
    }
}
