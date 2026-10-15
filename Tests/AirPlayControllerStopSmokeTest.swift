import Foundation

@main
struct AirPlayControllerStopSmokeTest {
    @MainActor static func main() async throws {
        for silently in [false, true] {
            try await localStop(silently: silently)
        }
        try await remoteStop()
        print("AirPlay Stop: local ACK stays silent, remote final timeline is preserved, no late callbacks: OK")
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

    @MainActor private static func emit(_ event: String, to controller: AirPlayController, sessionID: UUID) {
        let json = "{\"event\":\"\(event)\",\"position\":25,\"duration\":64.922,\"playing\":true}\n"
        controller.receiveEventTestOutput(Data(json.utf8), sessionID: sessionID)
    }
}
