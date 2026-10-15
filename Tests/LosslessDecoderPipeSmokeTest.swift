import Foundation

@main
struct LosslessDecoderPipeSmokeTest {
    static func main() throws {
        let clean = Pipe()
        let cleanReader = try LosslessDecoderPipe(handle: clean.fileHandleForReading, log: ProcessLogBuffer()) {}
        try clean.fileHandleForWriting.write(contentsOf: Data("Successful decoding\n".utf8))
        try clean.fileHandleForWriting.close()
        try expect(cleanReader.finish(), "Final clean bytes and EOF are accepted without a callback")
        let damaged = Pipe()
        let damagedReader = try LosslessDecoderPipe(handle: damaged.fileHandleForReading, log: ProcessLogBuffer()) {}
        try damaged.fileHandleForWriting.write(contentsOf: Data("[dca] Invalid XLL sync word\n".utf8))
        try damaged.fileHandleForWriting.close()
        try expect(!damagedReader.finish(), "Recovery in final pipe bytes cannot pass")
        let incomplete = Pipe()
        let incompleteReader = try LosslessDecoderPipe(handle: incomplete.fileHandleForReading, log: ProcessLogBuffer())
        {}
        try expect(!incompleteReader.finish(), "An open writer is not complete diagnostic evidence")
        try incomplete.fileHandleForWriting.close()
        cleanReader.close()
        damagedReader.close()
        incompleteReader.close()
        print("Lossless stderr ownership: final bytes, EOF, incomplete writers and idempotent cleanup: OK")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LosslessDecoderPipe.\(message)", code: 1) }
    }
}
