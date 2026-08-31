import Foundation

struct CapturedProcessResult: Sendable {
    let output: Data
    let errorOutput: Data
    let status: Int32
}

/// Runs a short-lived child process with bounded output and structured cancellation.
enum CapturedProcess {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        maximumOutputBytes: Int = 1_048_576
    ) async throws -> CapturedProcessResult {
        let process = Process()
        let input = standardInput == nil ? nil : Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = input ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        let outputCollector = ProcessDataBuffer(maximumBytes: maximumOutputBytes)
        let errorCollector = ProcessDataBuffer(maximumBytes: maximumOutputBytes)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                outputCollector.append(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                errorCollector.append(data)
            }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
        }

        do {
            let status = try await CancellableProcess(process).run {
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
                if let standardInput, let input {
                    try? input.fileHandleForWriting.write(contentsOf: standardInput)
                    try? input.fileHandleForWriting.close()
                }
            }
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(output.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errors.fileHandleForReading.readDataToEndOfFile())
            return CapturedProcessResult(
                output: outputCollector.snapshot,
                errorOutput: errorCollector.snapshot,
                status: status
            )
        } catch {
            try? input?.fileHandleForWriting.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            outputCollector.append(output.fileHandleForReading.readDataToEndOfFile())
            errorCollector.append(errors.fileHandleForReading.readDataToEndOfFile())
            throw error
        }
    }
}
