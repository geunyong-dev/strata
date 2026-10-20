import Foundation
import Darwin

/// The elevated process only checks metadata on this descriptor. It never writes
/// to the user's temporary directory or reads the file's contents.
public final class ReadOnlyScanLease {
    private let descriptor: Int32

    public init?(id: String) {
        guard UUID(uuidString: id) != nil else { return nil }
        let base = open("/private/tmp", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard base >= 0 else { return nil }
        defer { close(base) }
        let directory = openat(base, "strata-readonly-" + id, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        var parentInfo = stat()
        guard fstat(directory, &parentInfo) == 0, parentInfo.st_mode & 0o777 == 0o700 else { return nil }
        let lease = openat(directory, "lease", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard lease >= 0 else { return nil }
        var info = stat()
        guard fstat(lease, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1,
              info.st_uid == parentInfo.st_uid, info.st_uid != 0 else { close(lease); return nil }
        descriptor = lease
    }

    public var isActive: Bool {
        var info = stat()
        return fstat(descriptor, &info) == 0 && info.st_nlink == 1
    }

    deinit { close(descriptor) }
}
