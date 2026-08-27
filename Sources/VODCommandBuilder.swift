import Foundation

enum VODCommandBuilder {
    static func arguments(
        input: URL,
        outputDirectory: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        durationLimit: Double? = nil
    ) -> [String] {
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "warning",
            "-stats_period", "0.25", "-progress", "pipe:1",
            "-fflags", "+genpts", "-i", input.path,
        ]

        var audioInputIndex = 0
        if audio != nil, abs(audioDelay) >= 0.001 {
            arguments += ["-itsoffset", String(format: "%.3f", audioDelay)]
            arguments += ["-fflags", "+genpts", "-i", input.path]
            audioInputIndex = 1
        }

        arguments += ["-map", "0:\(probe.videoStreamIndex)", "-an", "-sn", "-dn", "-c:v", "copy"]

        if probe.videoCodec.lowercased() == "hevc" {
            let compatibilityID = probe.dolbyVisionCompatibilityID
            let usesBackwardCompatibleDolbyVision =
                probe.dolbyVisionProfile == 8 && (compatibilityID == 1 || compatibilityID == 4)
            arguments += [
                "-tag:v", usesBackwardCompatibleDolbyVision ? "hvc1" : (probe.isDolbyVision ? "dvh1" : "hvc1"),
            ]
            if probe.isDolbyVision { arguments += ["-strict", "unofficial"] }
        }

        if let durationLimit, durationLimit > 0 {
            arguments += ["-t", String(format: "%.3f", durationLimit)]
        }
        arguments += hlsOutputArguments(
            segmentPattern: outputDirectory.appendingPathComponent("video-%08d.m4s").path,
            initializationFile: "video-init.mp4",
            playlistPath: outputDirectory.appendingPathComponent("video.m3u8").path,
            independentSegments: true
        )

        if let audio {
            arguments += ["-map", "\(audioInputIndex):\(audio.streamIndex)", "-vn", "-sn", "-dn"]
            switch outputMode {
            case .original:
                arguments += ["-c:a", "copy"]
            case .compatible:
                arguments += ["-c:a", "eac3", "-b:a", "640k"]
                if (audio.channels ?? 0) > 6 { arguments += ["-ac:a", "6"] }
            case .stereo:
                arguments += ["-c:a", "aac", "-b:a", "256k", "-ac:a", "2"]
            }
            if let durationLimit, durationLimit > 0 {
                arguments += ["-t", String(format: "%.3f", durationLimit)]
            }
            arguments += hlsOutputArguments(
                segmentPattern: outputDirectory.appendingPathComponent("audio-%08d.m4s").path,
                initializationFile: "audio-init.mp4",
                playlistPath: outputDirectory.appendingPathComponent("audio.m3u8").path,
                independentSegments: false
            )
        }
        return arguments
    }

    /// Builds one fMP4 HLS media rendition containing video and the selected
    /// audio track. Sending this media playlist directly avoids tvOS rejecting
    /// an otherwise valid HDR/Dolby Vision variant at multivariant selection.
    static func multiplexedArguments(
        input: URL,
        outputDirectory: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        durationLimit: Double? = nil
    ) -> [String] {
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "warning",
            "-stats_period", "0.25", "-progress", "pipe:1",
            "-fflags", "+genpts", "-i", input.path,
        ]

        var audioInputIndex = 0
        if audio != nil, abs(audioDelay) >= 0.001 {
            arguments += ["-itsoffset", String(format: "%.3f", audioDelay)]
            arguments += ["-fflags", "+genpts", "-i", input.path]
            audioInputIndex = 1
        }

        arguments += ["-map", "0:\(probe.videoStreamIndex)"]
        if let audio {
            arguments += ["-map", "\(audioInputIndex):\(audio.streamIndex)"]
        }
        arguments += ["-sn", "-dn", "-c:v", "copy"]

        if probe.videoCodec.lowercased() == "hevc" {
            let compatibilityID = probe.dolbyVisionCompatibilityID
            let usesBackwardCompatibleDolbyVision =
                probe.dolbyVisionProfile == 8 && (compatibilityID == 1 || compatibilityID == 4)
            arguments += [
                "-tag:v",
                usesBackwardCompatibleDolbyVision ? "hvc1" : (probe.isDolbyVision ? "dvh1" : "hvc1"),
            ]
            if probe.isDolbyVision { arguments += ["-strict", "unofficial"] }
        }

        if let audio {
            switch outputMode {
            case .original:
                arguments += ["-c:a", "copy"]
            case .compatible:
                arguments += ["-c:a", "eac3", "-b:a", "640k"]
                if (audio.channels ?? 0) > 6 { arguments += ["-ac:a", "6"] }
            case .stereo:
                arguments += ["-c:a", "aac", "-b:a", "256k", "-ac:a", "2"]
            }
        }
        if let durationLimit, durationLimit > 0 {
            arguments += ["-t", String(format: "%.3f", durationLimit)]
        }
        arguments += hlsOutputArguments(
            segmentPattern: outputDirectory.appendingPathComponent("video-%08d.m4s").path,
            initializationFile: "video-init.mp4",
            playlistPath: outputDirectory.appendingPathComponent("video.m3u8").path,
            independentSegments: true
        )
        return arguments
    }

    private static func hlsOutputArguments(
        segmentPattern: String,
        initializationFile: String,
        playlistPath: String,
        independentSegments: Bool
    ) -> [String] {
        var flags = "temp_file"
        if independentSegments { flags += "+independent_segments" }
        return [
            "-avoid_negative_ts", "make_zero",
            "-max_muxing_queue_size", "4096",
            "-f", "hls",
            "-hls_segment_type", "fmp4",
            "-hls_fmp4_init_filename", initializationFile,
            "-hls_time", "6",
            "-hls_list_size", "0",
            "-hls_playlist_type", "vod",
            "-hls_flags", flags,
            "-hls_segment_filename", segmentPattern,
            playlistPath,
        ]
    }
}

enum DirectFileCommandBuilder {
    static func arguments(
        input: URL,
        output: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        subtitle: SubtitleTrack?,
        subtitleDelay: Double,
        durationLimit: Double? = nil
    ) -> [String] {
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "warning",
            "-stats_period", "0.25", "-progress", "pipe:1",
            "-fflags", "+genpts", "-i", input.path,
        ]
        var nextInputIndex = 1
        var audioInputIndex = 0
        if audio != nil, abs(audioDelay) >= 0.001 {
            arguments += ["-itsoffset", String(format: "%.3f", audioDelay)]
            arguments += ["-fflags", "+genpts", "-i", input.path]
            audioInputIndex = nextInputIndex
            nextInputIndex += 1
        }

        var subtitleInputIndex: Int?
        if let subtitle {
            if abs(subtitleDelay) < 0.001, subtitle.externalPath == nil {
                subtitleInputIndex = 0
            } else {
                arguments += ["-itsoffset", String(format: "%.3f", subtitleDelay)]
                let subtitleInput = subtitle.externalPath.map(URL.init(fileURLWithPath:)) ?? input
                arguments += ["-fflags", "+genpts", "-i", subtitleInput.path]
                subtitleInputIndex = nextInputIndex
                nextInputIndex += 1
            }
        }

        arguments += ["-map", "0:\(probe.videoStreamIndex)"]
        if let audio {
            arguments += ["-map", "\(audioInputIndex):\(audio.streamIndex)"]
        }
        if let subtitle, let subtitleInputIndex {
            let streamIndex = subtitle.externalPath == nil ? (subtitle.streamIndex ?? 0) : 0
            arguments += ["-map", "\(subtitleInputIndex):\(streamIndex)"]
        }
        arguments += ["-dn", "-c:v", "copy"]

        if probe.videoCodec.lowercased() == "hevc" {
            let compatibilityID = probe.dolbyVisionCompatibilityID
            let usesBackwardCompatibleDolbyVision =
                probe.dolbyVisionProfile == 8 && (compatibilityID == 1 || compatibilityID == 4)
            arguments += [
                "-tag:v", usesBackwardCompatibleDolbyVision ? "hvc1" : (probe.isDolbyVision ? "dvh1" : "hvc1"),
            ]
            if probe.isDolbyVision { arguments += ["-strict", "unofficial"] }
        }

        if let audio {
            switch outputMode {
            case .original:
                arguments += ["-c:a", "copy"]
            case .compatible:
                arguments += ["-c:a", "eac3", "-b:a", "640k"]
                if (audio.channels ?? 0) > 6 { arguments += ["-ac:a", "6"] }
            case .stereo:
                arguments += ["-c:a", "aac", "-b:a", "256k", "-ac:a", "2"]
            }
        }
        if let subtitle {
            arguments += ["-c:s", "mov_text"]
            if let language = subtitle.language, !language.isEmpty {
                arguments += ["-metadata:s:s:0", "language=\(language)"]
            }
            arguments += ["-disposition:s:0", subtitle.isForced ? "forced" : "default"]
        }
        if let durationLimit, durationLimit > 0 {
            arguments += ["-t", String(format: "%.3f", durationLimit)]
        }
        arguments += [
            "-avoid_negative_ts", "make_zero",
            "-max_muxing_queue_size", "4096",
            "-map_chapters", "-1",
            "-moov_size", "16777216",
            "-y", output.path,
        ]
        return arguments
    }
}
