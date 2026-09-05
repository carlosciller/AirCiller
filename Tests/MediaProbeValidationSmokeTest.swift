import Foundation

@main
struct MediaProbeValidationSmokeTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-ProbeValidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = root.appendingPathComponent("ffprobe-fixture")
        let movie = root.appendingPathComponent("fixture.mkv")
        for duration in ["nan", "inf", "1e100", "-1", "12.5"] {
            let json = """
                {"streams":[{"index":0,"codec_type":"video","codec_name":"h264"}],
                 "format":{"duration":"\(duration)"},
                 "chapters":[{"id":0,"start_time":"0","end_time":"10"},
                             {"id":1,"start_time":"nan","end_time":"inf"}]}
                """
            try "#!/bin/sh\nprintf '%s' '\(json)'\n".write(to: fixture, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
            do {
                let probe = try await MediaProbeService.probe(url: movie, ffprobeURL: fixture)
                guard duration == "12.5", probe.duration == 12.5, probe.chapters.count == 1 else {
                    throw Failure.acceptedInvalidData
                }
            } catch AirCillerError.probeFailed {
                guard duration != "12.5" else { throw Failure.rejectedValidData }
            }
        }
        print("Invalid media durations are rejected; invalid chapters are ignored: OK")
    }

    private enum Failure: Error { case acceptedInvalidData, rejectedValidData }
}
