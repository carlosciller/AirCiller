import AppKit
import Foundation

// A fixed application target; callers cannot supply a bundle, path or command.
@main
struct Lifecycle {
    @MainActor static func main() async {
        let target = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Movies/AirCiller.app")
        func running() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: "local.carlosciller.AirCiller")
                .filter { $0.bundleURL?.standardizedFileURL == target.standardizedFileURL }
        }
        guard CommandLine.arguments.count == 2 else { exit(2) }
        guard UserDefaults(suiteName: "local.carlosciller.AirCiller")?
            .bool(forKey: "privateRemoteEnabled") == true
        else { print("disabled"); return }
        switch CommandLine.arguments[1] {
        case "status": break
        case "open":
            if running().isEmpty {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                do { _ = try await NSWorkspace.shared.openApplication(at: target, configuration: configuration) }
                catch { print("launch_failed"); exit(1) }
            }
        case "close":
            for app in running() {
                guard app.terminate() else { print("termination_refused"); exit(1) }
            }
            for _ in 0..<100 {
                if running().isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard running().isEmpty else { print("termination_pending"); exit(1) }
        default: exit(2)
        }
        print(running().isEmpty ? "closed" : "running")
    }
}
