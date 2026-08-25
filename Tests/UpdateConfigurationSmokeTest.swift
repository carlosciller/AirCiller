import Foundation

@main
enum UpdateConfigurationSmokeTest {
    static func main() {
        let publicKey = Data(repeating: 7, count: 32).base64EncodedString()
        let configured = UpdateConfiguration.load(from: [
            "SUFeedURL": "https://updates.example.org/appcast.xml",
            "SUPublicEDKey": publicKey,
        ])
        precondition(configured.isReady)
        precondition(configured.feedHost == "updates.example.org")

        precondition(
            !UpdateConfiguration.load(from: [
                "SUFeedURL": "http://updates.example.org/appcast.xml",
                "SUPublicEDKey": publicKey,
            ]).isReady
        )
        precondition(
            !UpdateConfiguration.load(from: [
                "SUFeedURL": "https://updates.example.org/appcast.xml",
                "SUPublicEDKey": "not-a-public-key",
            ]).isReady
        )
        precondition(!UpdateConfiguration.load(from: nil).isReady)

        print("Update configuration smoke test: OK")
    }
}
