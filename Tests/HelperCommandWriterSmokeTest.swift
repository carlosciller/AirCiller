import Darwin
import Foundation

@main
struct HelperCommandWriterSmokeTest {
    static func main() throws {
        if CommandLine.arguments.contains("--closed-reader") {
            // Use the default signal disposition: an unprotected write would
            // kill this child with SIGPIPE before Swift's catch could run.
            signal(SIGPIPE, SIG_DFL)
            let pipe = Pipe()
            try pipe.fileHandleForReading.close()
            do {
                let command = Data("stop\n".utf8)
                if CommandLine.arguments.contains("--unprotected") {
                    try pipe.fileHandleForWriting.write(contentsOf: command)
                } else {
                    try HelperCommandWriter.write(command, to: pipe.fileHandleForWriting)
                }
                preconditionFailure("Writing to a closed reader must fail")
            } catch {
                let failure = error as NSError
                let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
                let posix = underlying ?? failure
                precondition(posix.domain == NSPOSIXErrorDomain && posix.code == Int(EPIPE))
            }
            return
        }

        let pipe = Pipe()
        let command = Data("{\"command\":\"pause\"}\n".utf8)
        try HelperCommandWriter.write(command, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()
        precondition(pipe.fileHandleForReading.readDataToEndOfFile() == command)

        for protected in [false, true] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--closed-reader"] + (protected ? [] : ["--unprotected"])
            try child.run()
            child.waitUntilExit()
            if protected {
                precondition(child.terminationReason == .exit && child.terminationStatus == 0)
            } else {
                precondition(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGPIPE)
            }
        }
        print("Helper commands survive a closed pipe without changing global signal handling: OK")
    }
}
