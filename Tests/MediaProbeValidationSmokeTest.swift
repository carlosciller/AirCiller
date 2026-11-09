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
        try await verifySelectiveExtradata(fixture: fixture, movie: movie)
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
        for (programs, duration, accepted) in [(1, "60", true), (2, "60", false), (1, "0", false)] {
            let programJSON = Array(repeating: "{\"program_id\":1}", count: programs).joined(separator: ",")
            let json = """
                {"streams":[{"index":0,"codec_type":"video","codec_name":"hevc"}],
                 "programs":[\(programJSON)],"format":{"format_name":"mpegts","duration":"\(duration)"}}
                """
            try "#!/bin/sh\nprintf '%s' '\(json)'\n".write(to: fixture, atomically: true, encoding: .utf8)
            do {
                _ = try await MediaProbeService.probe(url: movie, ffprobeURL: fixture)
                guard accepted else { throw Failure.acceptedInvalidData }
            } catch AirCillerError.probeFailed {
                guard !accepted else { throw Failure.rejectedValidData }
            }
        }
        for (fields, precision, eligible) in [
            ("\"sample_fmt\":\"s16\",\"bits_per_sample\":0", Int?.some(16), true),
            ("\"sample_fmt\":\"s32\",\"bits_per_raw_sample\":\"24\"", Int?.some(24), true),
            ("\"sample_fmt\":\"s32\",\"bits_per_raw_sample\":\"20\"", Int?.some(20), false),
            ("\"sample_fmt\":\"s32\",\"bits_per_sample\":0", Int?.none, false),
        ] {
            let json = """
                {"streams":[{"index":0,"codec_type":"video","codec_name":"h264"},
                {"index":1,"codec_type":"audio","codec_name":"pcm_bluray",
                "sample_rate":"48000","channels":2,"channel_layout":"stereo",\(fields)}],
                "format":{"duration":"8"}}
                """
            try "#!/bin/sh\nprintf '%s' '\(json)'\n".write(to: fixture, atomically: true, encoding: .utf8)
            let probe = try await MediaProbeService.probe(url: movie, ffprobeURL: fixture)
            guard let audio = probe.audioTracks.first, audio.sampleRate == 48_000,
                audio.bitsPerSample == precision, audio.canPrepareLosslessFLAC == eligible
            else { throw Failure.acceptedInvalidData }
        }
        print("Blu-ray PCM precision: explicit raw bits, decoder-specific signed16, no s32 inference: OK")
        print("Invalid media durations are rejected; invalid chapters are ignored: OK")
        print("Transport streams require one program and a finite duration: OK")
    }

    private static func verifySelectiveExtradata(fixture: URL, movie: URL) async throws {
        let metadata =
            #"{"streams":[{"index":0,"codec_type":"video","codec_name":"mjpeg","width":4000,"height":4000,"disposition":{"attached_pic":1}},{"index":4,"codec_type":"video","codec_name":"hevc","width":1920,"height":1080,"color_transfer":"smpte2084","side_data_list":[{"side_data_type":"DOVI configuration record","dv_profile":8,"dv_bl_signal_compatibility_id":1}]},{"index":6,"codec_type":"audio","codec_name":"eac3","channels":6},{"index":7,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle","tags":{"language":"eng"}}],"format":{"duration":"12.5"}}"#
        let configuration =
            #"{"streams":[{"index":4,"codec_name":"hevc","extradata":"\n00000000: 0101 0000 0000 0000 0000 0000 78"}]}"#
        try """
        #!/bin/sh
        case "$*" in
          *-select_streams*)
            case "$*" in *'-select_streams 4'*) ;; *) exit 81;; esac
            printf '%s' '\(configuration)';;
          *)
            case "$*" in *-show_data*|*extradata*) exit 82;; esac
            printf '%s' '\(metadata)';;
        esac
        """.write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let result = try await MediaProbeService.probe(url: movie, ffprobeURL: fixture)
        guard result.videoStreamIndex == 4, result.hevcCodecIdentifier == "hvc1.1.00000000.L120",
            result.isDolbyVision, result.dolbyVisionProfile == 8, result.dolbyVisionCompatibilityID == 1,
            result.audioTracks.first?.streamIndex == 6, result.subtitleTracks.first?.streamIndex == 7,
            result.duration == 12.5
        else { throw Failure.rejectedValidData }
        print("Probe extradata: only selected HEVC video, no attachment dump; HDR, audio and subtitles retained: OK")
    }

    private enum Failure: Error { case acceptedInvalidData, rejectedValidData }
}
