import Foundation

struct DeveloperDiagnosticAnalyzer: Sendable {
    private let runner = CommandRunner()

    func scan() -> DeveloperDiagnostics {
        DeveloperDiagnostics(docker: scanDocker(), xcode: scanXcode())
    }

    func scanDocker() -> DockerDiagnostic {
        guard let dockerURL = firstExecutable([
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]) else {
            return DockerDiagnostic(state: .unavailable("Docker CLI가 설치되어 있지 않습니다."), resources: [])
        }

        let output = runner.run(
            executable: dockerURL,
            arguments: ["system", "df", "--format", "{{json .}}"]
        )
        if output.timedOut {
            return DockerDiagnostic(state: .failed("Docker가 15초 안에 응답하지 않았습니다."), resources: [])
        }
        guard output.exitCode == 0 else {
            let message = conciseError(output.standardError, fallback: "Docker 데몬에 연결할 수 없습니다.")
            return DockerDiagnostic(state: .failed(message), resources: [])
        }

        do {
            let resources = try DockerSystemDFParser.parse(output.standardOutput)
            return DockerDiagnostic(state: .available, resources: resources)
        } catch {
            return DockerDiagnostic(state: .failed("Docker 사용량 출력을 해석하지 못했습니다."), resources: [])
        }
    }

    func scanXcode() -> XcodeDiagnostic {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard FileManager.default.isExecutableFile(atPath: xcrun.path) else {
            return XcodeDiagnostic(
                state: .unavailable("Xcode Command Line Tools가 설치되어 있지 않습니다."),
                runtimes: [], deviceCount: 0, unavailableDeviceCount: 0
            )
        }

        let runtimeOutput = runner.run(
            executable: xcrun,
            arguments: ["simctl", "runtime", "list", "--json"]
        )
        if runtimeOutput.timedOut {
            return XcodeDiagnostic(
                state: .failed("CoreSimulator가 15초 안에 응답하지 않았습니다."),
                runtimes: [], deviceCount: 0, unavailableDeviceCount: 0
            )
        }
        guard runtimeOutput.exitCode == 0 else {
            return XcodeDiagnostic(
                state: .failed(conciseError(runtimeOutput.standardError, fallback: "CoreSimulator 서비스에 연결할 수 없습니다.")),
                runtimes: [], deviceCount: 0, unavailableDeviceCount: 0
            )
        }

        do {
            let runtimes = try SimulatorRuntimeParser.parse(runtimeOutput.standardOutput)
            let deviceOutput = runner.run(
                executable: xcrun,
                arguments: ["simctl", "list", "devices", "--json"]
            )
            let devices = deviceOutput.exitCode == 0
                ? (try? SimulatorDeviceParser.parse(deviceOutput.standardOutput))
                : nil
            return XcodeDiagnostic(
                state: .available,
                runtimes: runtimes,
                deviceCount: devices?.total ?? 0,
                unavailableDeviceCount: devices?.unavailable ?? 0
            )
        } catch {
            return XcodeDiagnostic(
                state: .failed("Xcode 시뮬레이터 출력을 해석하지 못했습니다."),
                runtimes: [], deviceCount: 0, unavailableDeviceCount: 0
            )
        }
    }

    private func firstExecutable(_ paths: [String]) -> URL? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    private func conciseError(_ error: String, fallback: String) -> String {
        let line = error.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? fallback : line
    }
}

enum DockerSystemDFParser {
    private struct Row: Decodable {
        let active: String
        let reclaimable: String
        let size: String
        let totalCount: String
        let type: String

        enum CodingKeys: String, CodingKey {
            case active = "Active"
            case reclaimable = "Reclaimable"
            case size = "Size"
            case totalCount = "TotalCount"
            case type = "Type"
        }
    }

    static func parse(_ text: String) throws -> [DockerResourceUsage] {
        try text.split(whereSeparator: \.isNewline).map { line in
            let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
            return DockerResourceUsage(
                type: row.type,
                totalCount: Int(row.totalCount) ?? 0,
                activeCount: Int(row.active) ?? 0,
                sizeBytes: ByteSizeParser.parse(row.size) ?? 0,
                reclaimableBytes: ByteSizeParser.parse(row.reclaimable) ?? 0
            )
        }
    }
}

enum SimulatorRuntimeParser {
    private struct Runtime: Decodable {
        let build: String
        let deletable: Bool
        let identifier: String
        let lastUsedAt: String?
        let platformIdentifier: String
        let sizeBytes: Int64
        let state: String
        let version: String
    }

    static func parse(_ text: String) throws -> [SimulatorRuntimeUsage] {
        let payload = try JSONDecoder().decode([String: Runtime].self, from: Data(text.utf8))
        return payload.values.map { runtime in
            SimulatorRuntimeUsage(
                id: runtime.identifier,
                platform: platformName(runtime.platformIdentifier),
                version: runtime.version,
                build: runtime.build,
                sizeBytes: runtime.sizeBytes,
                state: runtime.state,
                isDeletable: runtime.deletable,
                lastUsedAt: runtime.lastUsedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func platformName(_ identifier: String) -> String {
        if identifier.contains("iphone") { return "iOS" }
        if identifier.contains("watch") { return "watchOS" }
        if identifier.contains("appletv") { return "tvOS" }
        if identifier.contains("xr") { return "visionOS" }
        return identifier
    }
}

enum SimulatorDeviceParser {
    struct Summary {
        let total: Int
        let unavailable: Int
    }

    private struct Payload: Decodable {
        let devices: [String: [Device]]
    }

    private struct Device: Decodable {
        let isAvailable: Bool?
    }

    static func parse(_ text: String) throws -> Summary {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(text.utf8))
        let devices = payload.devices.values.flatMap { $0 }
        return Summary(total: devices.count, unavailable: devices.filter { $0.isAvailable == false }.count)
    }
}

enum ByteSizeParser {
    static func parse(_ text: String) -> Int64? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([KMGTPE]?I?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let number = Double(text[numberRange]) else { return nil }

        let unit = text[unitRange].uppercased()
        let powers: [String: Double] = [
            "B": 1,
            "KB": 1_000, "MB": 1_000_000, "GB": 1_000_000_000, "TB": 1_000_000_000_000,
            "KIB": 1_024, "MIB": 1_048_576, "GIB": 1_073_741_824, "TIB": 1_099_511_627_776
        ]
        guard let multiplier = powers[unit] else { return nil }
        return Int64(number * multiplier)
    }
}
