import Foundation
import Darwin

struct CommandOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
    let timedOut: Bool
    var cancelled: Bool = false
}

struct CommandRunner: Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval = 15) -> CommandOutput {
        guard !Task.isCancelled else {
            return CommandOutput(standardOutput: "", standardError: "취소됨", exitCode: -1, timedOut: false, cancelled: true)
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Strata-\(UUID().uuidString)", directoryHint: .isDirectory)
        let standardOutputURL = temporaryDirectory.appending(path: "stdout")
        let standardErrorURL = temporaryDirectory.appending(path: "stderr")

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
            FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let standardOutput = try FileHandle(forWritingTo: standardOutputURL)
            let standardError = try FileHandle(forWritingTo: standardErrorURL)
            defer {
                try? standardOutput.close()
                try? standardError.close()
            }

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = standardOutput
            process.standardError = standardError
            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            process.environment = environment

            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline && !Task.isCancelled {
                Thread.sleep(forTimeInterval: 0.05)
            }
            let cancelled = Task.isCancelled
            let timedOut = process.isRunning && !cancelled
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.1)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
            try? standardOutput.synchronize()
            try? standardError.synchronize()

            return CommandOutput(
                standardOutput: String(decoding: (try? Data(contentsOf: standardOutputURL)) ?? Data(), as: UTF8.self),
                standardError: String(decoding: (try? Data(contentsOf: standardErrorURL)) ?? Data(), as: UTF8.self),
                exitCode: process.terminationStatus,
                timedOut: timedOut,
                cancelled: cancelled
            )
        } catch {
            return CommandOutput(
                standardOutput: "",
                standardError: error.localizedDescription,
                exitCode: -1,
                timedOut: false
            )
        }
    }
}
