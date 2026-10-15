import Foundation

/// Local decoder evidence only; paths refer to the bounded public FATE fixture
/// and its separately generated damaged copy. No playback or credential access.
@main
struct DTSLosslessGuardMediaTest {
    static func main() async throws {
        guard CommandLine.arguments.count == 5 else { throw Failure.invalidInput }
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        var originalPCM: Data?
        for (index, path) in CommandLine.arguments.dropFirst(2).enumerated() {
            let source = URL(fileURLWithPath: path)
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            guard let size = attributes[.size] as? Int, (1...1_048_576).contains(size) else {
                throw Failure.invalidInput
            }
            let result = try await CapturedProcess.run(
                executable: executable,
                arguments: [
                    "-v", "verbose", "-nostdin", "-xerror", "-err_detect", "explode", "-core_only", "0",
                    "-i", source.path, "-map", "0:a:0", "-c:a", "pcm_s24le", "-f", "s24le", "pipe:1",
                ])
            let guardState = LosslessDecoderGuard()
            for byte in result.errorOutput { guardState.append(Data([byte])) }
            guard result.status == 0, result.output.count == 36_864,
                index == 1 ? guardState.failure == .recovery : guardState.failure == nil
            else { throw Failure.guardMismatch }
            if index == 0 {
                originalPCM = result.output
            } else {
                guard result.output != originalPCM else { throw Failure.guardMismatch }
            }
            print(
                "case=\(index), decoderExit=\(result.status), pcmBytes=\(result.output.count), rejected=\(guardState.failure != nil)"
            )
        }
    }

    private enum Failure: Error { case invalidInput, guardMismatch }
}
