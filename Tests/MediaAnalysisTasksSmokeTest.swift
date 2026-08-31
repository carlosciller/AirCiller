import Foundation

@main
@MainActor
struct MediaAnalysisTasksSmokeTest {
    static func main() async throws {
        let tasks = MediaAnalysisTasks()
        let firstDemand = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        tasks.replaceDemand(with: firstDemand)

        let replacementDemand = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        tasks.replaceDemand(with: replacementDemand)
        guard firstDemand.isCancelled else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.Replacement", code: 1)
        }

        let primary = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        tasks.replacePrimary(with: primary)
        tasks.cancelAll()

        guard primary.isCancelled,
            replacementDemand.isCancelled,
            tasks.primary == nil,
            tasks.demand == nil
        else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.Stop", code: 2)
        }
        print("Primary and demand analyses share one cancellable lifecycle: OK")
    }
}
