import Foundation

@main
struct ServeDirectory {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "ServeDirectory.Usage", code: 2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let server = LocalHTTPServer(rootDirectory: directory)
        let baseURL = try await server.start()
        print(baseURL.absoluteString)
        fflush(stdout)
        while true {
            try await Task.sleep(for: .seconds(3_600))
        }
    }
}
