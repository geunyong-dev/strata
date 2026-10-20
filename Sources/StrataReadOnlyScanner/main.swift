import Foundation
import Darwin
import ReadOnlyScanCore

// A one-shot, read-only process, not a daemon. Only a UUID lease name is accepted;
// it cannot change scan roots or run commands. The GUI unlinks the lease on cancel.
guard CommandLine.arguments.count == 2,
      geteuid() == 0 else { exit(64) }
guard let lease = ReadOnlyScanLease(id: CommandLine.arguments[1]) else { exit(65) }
// Soft deadline returns completed areas; hard deadline bounds a stalled syscall.
alarm(200)
let deadline = ContinuousClock.now.advanced(by: .seconds(180))
func shouldStop() -> Bool {
    ContinuousClock.now >= deadline || !lease.isActive
}
var results: [ReadOnlyMeasurement] = []
for path in ReadOnlyScanScope.paths {
    if shouldStop() { break }
    results.append(ReadOnlyDirectoryScanner().measure(path: path, shouldStop: shouldStop))
}
let response = ReadOnlyScanResponse(effectiveUID: geteuid(), results: results)
guard let data = try? JSONEncoder().encode(response) else { exit(66) }
FileHandle.standardOutput.write(data)
