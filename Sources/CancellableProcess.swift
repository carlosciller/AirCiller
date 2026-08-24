import Darwin
import Foundation

/// Runs a Foundation `Process` without detaching it from the task that owns it.
/// Cancelling the task requests termination immediately and escalates only if
/// the child ignores SIGTERM.
final class CancellableProcess: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func run(onStarted: (() -> Void)? = nil) async throws -> Int32 {
        try Task.checkCancellation()
        let waiter = ProcessExitWaiter()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            process.terminationHandler = { process in
                Task { await waiter.finish(.success(process.terminationStatus)) }
            }
            do {
                try process.run()
                onStarted?()
            } catch {
                process.terminationHandler = nil
                await waiter.finish(.failure(error))
            }

            if Task.isCancelled { terminate() }
            let status = try await waiter.wait()
            try Task.checkCancellation()
            return status
        } onCancel: {
            self.terminate()
        }
    }

    /// Observes a process that was started synchronously so callers can keep
    /// reading progress while retaining structured cancellation.
    func waitForExit() async throws -> Int32 {
        try Task.checkCancellation()
        guard process.isRunning else { return process.terminationStatus }
        let waiter = ProcessExitWaiter()

        return try await withTaskCancellationHandler {
            process.terminationHandler = { process in
                Task { await waiter.finish(.success(process.terminationStatus)) }
            }
            if !process.isRunning {
                await waiter.finish(.success(process.terminationStatus))
            }
            let status = try await waiter.wait()
            try Task.checkCancellation()
            return status
        } onCancel: {
            self.terminate()
        }
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.process.isRunning else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
    }
}

private actor ProcessExitWaiter {
    private var result: Result<Int32, Error>?
    private var continuation: CheckedContinuation<Int32, Error>?

    func wait() async throws -> Int32 {
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ result: Result<Int32, Error>) {
        guard self.result == nil else { return }
        self.result = result
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let status):
            continuation.resume(returning: status)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
