import Foundation

@main
struct AirPlayControllerStopSmokeTest {
    @MainActor static func main() async throws {
        for silently in [false, true] {
            try await localStop(silently: silently)
        }
        try await remoteStop()
        try await receiverObservations()
        try await replacementWaitsForExit()
        try await cancelledReplacementCannotContinue()
        try await stoppedReplacementCannotContinue()
        try await supersededReplacementCannotContinue()
        try await retiredCancellationCannotCancelReplacement()
        print("AirPlay Stop: timeline ownership, helper exit ordering and cancelled replacements: OK")
    }

    @MainActor private static func retiredCancellationCannotCancelReplacement() async throws {
        let controller = AirPlayController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        let retiredSessionID = try controller.beginProcessTestSession(process)
        defer { if process.isRunning { process.terminate() } }
        let replacement = Task { try await controller.prepareReplacementTestSession() }
        try await waitForReplacement(controller)
        // The old start task's MainActor cancellation callback can arrive while
        // its already-stopping helper is still being joined by the next start.
        controller.cancelProcessTestSession(UUID())
        controller.cancelProcessTestSession(retiredSessionID)
        try await replacement.value
        precondition(!process.isRunning && !controller.isSessionActive)

        let activeSessionID = controller.beginEventTestSession(position: 0, duration: 60)
        emit("playing", to: controller, sessionID: activeSessionID)
        controller.cancelProcessTestSession(activeSessionID)
        emit("stopped", to: controller, sessionID: activeSessionID)
        controller.endEventTestSession(activeSessionID)
        precondition(!controller.isConnected && !controller.isSessionActive)
    }

    @MainActor private static func cancelledReplacementCannotContinue() async throws {
        let controller = AirPlayController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try controller.beginProcessTestSession(process)
        defer { if process.isRunning { process.terminate() } }
        let replacement = Task { try await controller.prepareReplacementTestSession() }
        try await waitForReplacement(controller)
        controller.stop(silently: true)
        replacement.cancel()
        do {
            try await replacement.value
            preconditionFailure("Cancelled replacement continued")
        } catch is CancellationError {}
        // A later explicit Play may still finish retirement normally.
        try await controller.prepareReplacementTestSession()
        precondition(!process.isRunning && !controller.isSessionActive)
    }

    @MainActor private static func supersededReplacementCannotContinue() async throws {
        let controller = AirPlayController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try controller.beginProcessTestSession(process)
        defer { if process.isRunning { process.terminate() } }
        let first = Task { try await controller.prepareReplacementTestSession() }
        try await waitForReplacement(controller)
        try await controller.prepareReplacementTestSession()
        do {
            try await first.value
            preconditionFailure("Superseded replacement continued")
        } catch is CancellationError {}
        precondition(!process.isRunning && !controller.isSessionActive)
        // No helper and repeated Stop are both safe and need no grace-period sleep.
        controller.stop(silently: true)
        controller.stop(silently: true)
        try await controller.prepareReplacementTestSession()
    }

    @MainActor private static func stoppedReplacementCannotContinue() async throws {
        let controller = AirPlayController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try controller.beginProcessTestSession(process)
        defer { if process.isRunning { process.terminate() } }
        let replacement = Task { try await controller.prepareReplacementTestSession() }
        try await waitForReplacement(controller)
        controller.stop(silently: true)
        do {
            try await replacement.value
            preconditionFailure("Stop did not invalidate a waiting replacement")
        } catch is CancellationError {}
        try await controller.prepareReplacementTestSession()
        precondition(!process.isRunning && !controller.isSessionActive)
    }

    @MainActor private static func waitForReplacement(_ controller: AirPlayController) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !controller.isReplacementWaitingTest {
            precondition(Date() < deadline, "Replacement did not reach the retirement barrier")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor private static func replacementWaitsForExit() async throws {
        let controller = AirPlayController()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.4"]
        try controller.beginProcessTestSession(process)
        defer { if process.isRunning { process.terminate() } }
        controller.stop(silently: true)
        try await controller.prepareReplacementTestSession()
        precondition(!process.isRunning, "Replacement started while the retired AirPlay helper was still running")
        precondition(!controller.isSessionActive, "Retired helper references survived replacement readiness")
    }

    @MainActor private static func localStop(silently: Bool) async throws {
        let controller = AirPlayController()
        let sessionID = controller.beginEventTestSession(position: 25, duration: 64.922)
        var updates: [(Double, Double, Bool)] = []
        var stopped = 0
        var ended = 0
        var errors = 0
        controller.onPlaybackUpdate = { updates.append(($0, $1, $2)) }
        controller.onPlaybackStopped = { stopped += 1 }
        controller.onPlaybackEnded = { ended += 1 }
        controller.onPlaybackError = { _ in errors += 1 }

        emit("playing", to: controller, sessionID: sessionID)
        precondition(controller.isConnected && updates.count == 1)
        controller.stop(silently: silently)
        let countAtStop = updates.count
        // The consumer has already removed its presentation-to-movie mapping.
        // A final presentation-time callback here would corrupt its resume position.
        emit("stopped", to: controller, sessionID: sessionID)
        precondition(updates.count == countAtStop, "Local Stop ACK republished the retired presentation clock")
        precondition(stopped == 0 && !controller.isConnected)

        for event in ["playing", "status", "paused", "resumed", "seeked", "ended"] {
            emit(event, to: controller, sessionID: sessionID)
        }
        try await Task.sleep(for: .milliseconds(650))
        precondition(updates.count == countAtStop, "A stopped session emitted a late timeline update")
        precondition(stopped == 0 && ended == 0 && errors == 0 && !controller.isConnected)
        controller.endEventTestSession(sessionID)
        precondition(!controller.isSessionActive && errors == 0)

        // Clearing `stopping` during teardown must not let the previous session leak into a new one.
        let nextSessionID = controller.beginEventTestSession(position: 0, duration: 60)
        emit("playing", to: controller, sessionID: sessionID)
        emit("stopped", to: controller, sessionID: sessionID)
        precondition(updates.count == countAtStop && stopped == 0 && !controller.isConnected)
        controller.stop(silently: true)
        controller.endEventTestSession(nextSessionID)
    }

    @MainActor private static func remoteStop() async throws {
        let controller = AirPlayController()
        let sessionID = controller.beginEventTestSession(position: 25, duration: 64.922)
        var updates: [(Double, Double, Bool)] = []
        var callbacks: [String] = []
        var errors = 0
        controller.onPlaybackUpdate = {
            updates.append(($0, $1, $2))
            callbacks.append("update")
        }
        controller.onPlaybackStopped = { callbacks.append("stopped") }
        controller.onPlaybackError = { _ in errors += 1 }

        emit("playing", to: controller, sessionID: sessionID)
        precondition(controller.isConnected)
        callbacks.removeAll()
        emit("stopped", to: controller, sessionID: sessionID)
        precondition(callbacks == ["update", "stopped"], "Remote Stop must publish its final time before cleanup")
        precondition(updates.count == 2 && !controller.isConnected)
        let final = updates[1]
        precondition(final.0 >= 25 && final.0 < 26 && final.1 == 64.922 && !final.2)
        try await Task.sleep(for: .milliseconds(650))
        precondition(updates.count == 2 && callbacks == ["update", "stopped"])
        controller.endEventTestSession(sessionID)
        precondition(!controller.isSessionActive && errors == 0, "Remote Stop lost its terminal-event marker")
    }

    @MainActor private static func receiverObservations() async throws {
        let controller = AirPlayController()
        let sessionID = controller.beginEventTestSession(position: 25, duration: 64.922)
        var observations: [AirPlayReceiverObservation] = []
        var updates = 0
        controller.onReceiverPlaybackUpdate = { observations.append($0) }
        controller.onPlaybackUpdate = { _, _, _ in updates += 1 }

        emit("playing", to: controller, sessionID: sessionID)
        precondition(observations.count == 1 && observations[0].position == 25)
        let firstObservationDate = observations[0].at
        try await Task.sleep(for: .milliseconds(650))
        precondition(updates > 1, "The UI clock must remain responsive between receiver events")
        precondition(
            observations.count == 1 && observations[0].at == firstObservationDate,
            "The Mac clock incorrectly renewed receiver evidence")

        for event in ["paused", "resumed", "seeked"] {
            let json = "{\"event\":\"\(event)\",\"source\":\"command\",\"position\":40,\"duration\":64.922}\n"
            controller.receiveEventTestOutput(Data(json.utf8), sessionID: sessionID)
        }
        precondition(observations.count == 1, "Command ACKs cannot confirm receiver state or position")

        controller.receiveEventTestOutput(
            Data("{\"event\":\"paused\",\"source\":\"receiver\"}\n".utf8), sessionID: sessionID)
        precondition(observations.count == 2 && !observations[1].playing)
        precondition(
            observations[1].position == nil && observations[1].duration == nil,
            "Missing receiver timing must not inherit the interpolated clock or seek target")

        controller.receiveEventTestOutput(
            Data("{\"event\":\"status\",\"position\":41.25,\"duration\":64.922,\"playing\":true}\n".utf8),
            sessionID: sessionID)
        precondition(observations.count == 3 && observations[2].position == 41.25 && observations[2].playing)
        controller.stop(silently: true)
        emit("status", to: controller, sessionID: sessionID)
        controller.endEventTestSession(sessionID)
        let nextSession = controller.beginEventTestSession(position: 0, duration: 60)
        emit("playing", to: controller, sessionID: sessionID)
        precondition(observations.count == 3, "Stopped or retired sessions cannot renew receiver evidence")
        controller.stop(silently: true)
        controller.endEventTestSession(nextSession)
    }

    @MainActor private static func emit(_ event: String, to controller: AirPlayController, sessionID: UUID) {
        let json = "{\"event\":\"\(event)\",\"position\":25,\"duration\":64.922,\"playing\":true}\n"
        controller.receiveEventTestOutput(Data(json.utf8), sessionID: sessionID)
    }
}
