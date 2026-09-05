import Darwin
import Foundation

enum HelperCommandWriter {
    /// A helper may exit between checking its state and writing a command.
    /// Suppress SIGPIPE on this descriptor only, so FileHandle throws instead
    /// of terminating the application. Keep the process-wide signal policy.
    static func write(_ data: Data, to handle: FileHandle) throws {
        guard fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try handle.write(contentsOf: data)
    }
}
