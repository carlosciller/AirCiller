import Foundation

@main
enum CredentialServiceProbe {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 else { exit(2) }
        do {
            let result = try CredentialServiceClient.read(
                account: arguments[1], allowInteraction: false,
                operation: arguments[0] == "cleanup" ? "cleanupFixture" : "read"
            )
            if arguments[0] != "cleanup", result != "AirCiller synthetic credential" { exit(3) }
            print("Synthetic credential operation succeeded.")
        } catch {
            print("Credential request refused: \((error as NSError).code)")
            exit(1)
        }
    }
}
