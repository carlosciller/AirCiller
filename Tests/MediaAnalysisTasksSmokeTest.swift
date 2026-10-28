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
        tasks.cancelDemand()
        guard replacementDemand.isCancelled, tasks.demand == nil,
            !primary.isCancelled, tasks.primary != nil
        else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.HLS", code: 3)
        }
        tasks.cancelAll()

        guard primary.isCancelled,
            replacementDemand.isCancelled,
            tasks.primary == nil,
            tasks.demand == nil
        else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.Stop", code: 2)
        }
        // Direct preparation must join the retired analysis, without cancelling
        // a new movie's task installed while that join is suspended.
        var retiredFinished = false
        let retired = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
            retiredFinished = true
        }
        tasks.replaceDemand(with: retired)
        let joined = tasks.cancelDemand()
        // A second Play after Stop must still wait for the already-cancelled
        // process. Removing the current task is not proof that it has exited.
        guard tasks.cancelDemand() != nil else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.RetryJoin", code: 6)
        }
        let newMovie = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        tasks.replaceDemand(with: newMovie)
        await joined?.value
        guard retiredFinished, retired.isCancelled, !newMovie.isCancelled,
            tasks.demand != nil
        else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.DirectJoin", code: 4)
        }
        tasks.cancelAll()
        await newMovie.value
        await tasks.cancelDemand()?.value
        guard tasks.cancelDemand() == nil else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.EmptyJoin", code: 5)
        }
        var completedResult = 42
        let completed = Task<Void, Never> { completedResult = 73 }
        tasks.replaceDemand(with: completed)
        await completed.value
        await tasks.cancelDemand()?.value
        guard completedResult == 73 else {
            throw NSError(domain: "MediaAnalysisTasksSmokeTest.CompletedResult", code: 7)
        }
        print("Primary and demand analyses share one cancellable lifecycle: OK")
    }
}
