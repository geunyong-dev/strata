import Foundation

enum CleanupScope {
    static func contains(_ action: CleanupAction, area: String) -> Bool {
        guard case let .projectArtifact(path) = action.kind else { return false }
        let candidate = normalized(path)
        let root = normalized(area)
        return root == "/" || candidate == root || candidate.hasPrefix(root + "/")
    }

    static func isUnlocated(_ action: CleanupAction) -> Bool {
        if case .projectArtifact = action.kind { return false }
        return true
    }

    private static func normalized(_ path: String) -> String {
        let value = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = "/System/Volumes/Data"
        if value == prefix { return "/" }
        if value.hasPrefix(prefix + "/") { return String(value.dropFirst(prefix.count)) }
        return value
    }
}
