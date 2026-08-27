import Foundation

final class VODBuildProcess: @unchecked Sendable {
    let process: Process
    let log: ProcessLogBuffer
    let progress: ProcessProgressBuffer
    private let errorPipe: Pipe
    private let progressPipe: Pipe

    init(
        process: Process,
        log: ProcessLogBuffer,
        progress: ProcessProgressBuffer,
        errorPipe: Pipe,
        progressPipe: Pipe
    ) {
        self.process = process
        self.log = log
        self.progress = progress
        self.errorPipe = errorPipe
        self.progressPipe = progressPipe
    }

    func closePipes() {
        errorPipe.fileHandleForReading.readabilityHandler = nil
        progressPipe.fileHandleForReading.readabilityHandler = nil
        try? errorPipe.fileHandleForReading.close()
        try? progressPipe.fileHandleForReading.close()
    }

    func didStart() {
        try? errorPipe.fileHandleForWriting.close()
        try? progressPipe.fileHandleForWriting.close()
    }
}

final class ProcessProgressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var latestSeconds = 0.0
    private var latestSpeed: Double?

    func append(_ value: String) {
        lock.lock()
        pending.append(value)
        let lines = pending.components(separatedBy: "\n")
        pending = lines.last ?? ""
        for line in lines.dropLast() {
            if line.hasPrefix("out_time_us="),
                let microseconds = Double(line.dropFirst("out_time_us=".count))
            {
                latestSeconds = max(latestSeconds, microseconds / 1_000_000)
            } else if line.hasPrefix("speed=") {
                let value = line.dropFirst("speed=".count).trimmingCharacters(in: .whitespaces)
                latestSpeed = Double(
                    value.trimmingCharacters(in: CharacterSet(charactersIn: "x"))
                )
            }
        }
        lock.unlock()
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return latestSeconds
    }

    var speed: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestSpeed
    }
}

final class ProcessLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ value: String) {
        lock.lock()
        text.append(value)
        if text.count > 8_000 { text = String(text.suffix(8_000)) }
        lock.unlock()
    }

    var snapshot: String {
        lock.lock()
        defer { lock.unlock() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
