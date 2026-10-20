import Foundation
import Darwin

enum InterruptedReadRetry {
    static let maximumRetries = 2

    static func isInterrupted(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain { return error.code == Int(EINTR) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain { return underlying.code == Int(EINTR) }
        return false
    }

    /// Return the captured errno alongside the result; logging must not overwrite it.
    static func run(_ operation: () -> Int32) -> (result: Int32, error: Int32, retries: Int) {
        var retries = 0
        while true {
            let result = operation()
            let code = result == 0 ? 0 : errno
            guard result != 0, code == EINTR, retries < maximumRetries, !Task.isCancelled else {
                return (result, code, retries)
            }
            retries += 1
        }
    }
}
