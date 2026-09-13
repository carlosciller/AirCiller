import Foundation

struct HLSPreparationResult: Sendable {
    let duration: Double
    let demandProfile: StreamDemandProfile
    let subtitle: SubtitleTrack?
    let usedCache: Bool
}

enum HLSPreparationEvent: Sendable {
    case began(PlaybackStartupTrace.Stage)
    case ended(PlaybackStartupTrace.Stage)
    case packagingProgress(Double, Double?)
    case ocrProgress(Int, Int)
    case process(VODBuildProcess?)
    case cacheHit
}

/// Prepares a complete local HLS VOD. No receiver, server or user credentials.
/// Direct MP4 packaging deliberately stays in its existing independent route.
enum HLSPreparationService {
    typealias Observer = @MainActor @Sendable (HLSPreparationEvent) -> Void

    static func prepare(
        input: URL, probe: MediaProbe, audio: AudioTrack?, outputMode: AudioOutputMode,
        audioDelay: Double, subtitle: SubtitleTrack?, subtitleDelay: Double,
        outputDirectory: URL, ffmpegURL: URL, cache: PreparedMediaCache? = nil,
        capacityReader: @escaping PreparedMediaCache.CapacityReader = PreparedMediaCache.availableCapacity,
        observer: @escaping Observer = { _ in }
    ) async throws -> HLSPreparationResult {
        try Task.checkCancellation()
        let multiplexed = probe.isHDR
        let key = try? PreparedMediaCache.makeKey(
            source: input, probe: probe, audio: audio, outputMode: outputMode,
            audioDelay: audioDelay, multiplexed: multiplexed,
            engineVersion: "hls-base-v1", engineURL: ffmpegURL
        )

        // The immutable video/audio package and text extraction are independent.
        // Bitmap OCR keeps the exact final rendition duration used by 0.12.6.
        enum Branch: Sendable {
            case base(Bool)
            case text(HLSSubtitleContent)
        }
        var usedCache = false
        var textContent: HLSSubtitleContent?
        try await withThrowingTaskGroup(of: Branch.self) { group in
            group.addTask {
                .base(
                    try await prepareBase(
                        input: input, probe: probe, audio: audio, outputMode: outputMode,
                        audioDelay: audioDelay, directory: outputDirectory, ffmpegURL: ffmpegURL,
                        cache: cache, key: key, capacityReader: capacityReader, observer: observer
                    ))
            }
            if let subtitle, !subtitle.usesBitmapOCR {
                group.addTask {
                    await observer(.began(.subtitles))
                    let content = try await SubtitleService.materializeHLSContent(
                        track: subtitle, videoURL: input, videoDuration: probe.duration,
                        outputDirectory: outputDirectory, ffmpegURL: ffmpegURL
                    )
                    return .text(content)
                }
            }
            // A failure cancels and joins the sibling before the caller can
            // remove its session directory or begin a replacement preparation.
            for try await branch in group {
                switch branch {
                case .base(let hit): usedCache = hit
                case .text(let content): textContent = content
                }
            }
        }
        try Task.checkCancellation()
        var resolvedSubtitle = subtitle
        if let subtitle {
            if let textContent {
                resolvedSubtitle = try SubtitleService.finalizeHLSContent(
                    textContent, delay: subtitleDelay,
                    videoPlaylistURL: outputDirectory.appendingPathComponent("video.m3u8"),
                    outputDirectory: outputDirectory
                )
            } else {
                await observer(.began(.subtitles))
                resolvedSubtitle = try await SubtitleService.prepare(
                    track: subtitle, videoURL: input, delay: subtitleDelay,
                    videoPlaylistURL: outputDirectory.appendingPathComponent("video.m3u8"),
                    outputDirectory: outputDirectory,
                    ocrProgress: { completed, total in
                        Task { @MainActor in observer(.ocrProgress(completed, total)) }
                    }
                )
            }
            try Task.checkCancellation()
            try SubtitleService.alignRenditionPlaylists(
                outputDirectory: outputDirectory, expectedDuration: probe.duration
            )
            await observer(.ended(.subtitles))
        }
        await observer(.began(.validation))
        if !multiplexed {
            try SubtitleService.writeMasterPlaylist(
                probe: probe, audio: audio, audioOutputMode: outputMode,
                subtitle: resolvedSubtitle, outputDirectory: outputDirectory
            )
        }
        let duration = try SubtitleService.validatePackage(
            outputDirectory: outputDirectory, expectedDuration: probe.duration,
            hasAudio: audio != nil && !multiplexed, hasSubtitles: subtitle != nil,
            requiresMasterPlaylist: !multiplexed
        )
        let profile = try StreamDemandAnalyzer.packagedHLSProfile(
            outputDirectory: outputDirectory, hasSeparateAudio: audio != nil && !multiplexed
        )
        try Task.checkCancellation()
        await observer(.ended(.validation))
        return HLSPreparationResult(
            duration: duration, demandProfile: profile, subtitle: resolvedSubtitle, usedCache: usedCache
        )
    }

    private static func prepareBase(
        input: URL, probe: MediaProbe, audio: AudioTrack?, outputMode: AudioOutputMode,
        audioDelay: Double, directory: URL, ffmpegURL: URL,
        cache: PreparedMediaCache?, key: PreparedMediaCache.Key?,
        capacityReader: @escaping PreparedMediaCache.CapacityReader, observer: @escaping Observer
    ) async throws -> Bool {
        if let cache, let key {
            await observer(.began(.cacheLookup))
            let hit: Bool
            do { hit = try await cache.checkout(key: key, into: directory) } catch is CancellationError {
                throw CancellationError()
            } catch { hit = false }
            await observer(.ended(.cacheLookup))
            if hit {
                // Checkout already checks the inventory. Keep the normal VOD
                // validation too, so a malformed cached base is never served.
                do {
                    _ = try validateBase(directory, probe: probe, audio: audio)
                    await observer(.cacheHit)
                    return true
                } catch {
                    do { try await cache.invalidate(key: key) } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Rebuild if the session links can be safely removed below.
                    }
                }
            }
        }
        try Task.checkCancellation()
        // Never let ffmpeg -y overwrite a hard link left by a failed checkout.
        // A cleanup failure aborts preparation rather than modifying cached bytes.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where file.lastPathComponent.hasPrefix("video") || file.lastPathComponent.hasPrefix("audio") {
            try FileManager.default.removeItem(at: file)
        }
        // A valid cache hit needs no full-file space reservation.
        if let size = probe.fileSize, size > 0 {
            let required = Int64(min(Double(Int64.max - 1_024), max(Double(size) + 768_000_000, Double(size) * 1.12)))
            if let available = capacityReader(directory), available >= 0, available < required {
                if let cache {
                    do {
                        try await cache.reclaimSpace(
                            requiredFreeBytes: required, forDirectory: directory, capacityReader: capacityReader)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Cache cleanup remains optional. Only the fresh capacity
                        // reading below decides whether preparation has room.
                    }
                }
                try Task.checkCancellation()
                if let current = capacityReader(directory), current >= 0, current < required {
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    throw AirCillerError.invalidVODPackage(
                        L10n.format(
                            "Para preparar esta película hacen falta aproximadamente %@ libres; ahora hay %@. AirCiller no modificará ni recodificará el archivo original.",
                            formatter.string(fromByteCount: required), formatter.string(fromByteCount: current))
                    )
                }
            }
        }
        await observer(.began(.packaging))
        let build = makeBuild(
            input: input, directory: directory, ffmpegURL: ffmpegURL,
            probe: probe, audio: audio, outputMode: outputMode, audioDelay: audioDelay
        )
        await observer(.process(build))
        defer {
            build.didStart()
            build.closePipes()
        }
        let reporter = Task {
            while !Task.isCancelled {
                await observer(.packagingProgress(build.progress.seconds, build.progress.speed))
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        let status: Int32
        do {
            status = try await CancellableProcess(build.process).run { build.didStart() }
        } catch {
            reporter.cancel()
            _ = try? await reporter.value
            await observer(.process(nil))
            throw error
        }
        reporter.cancel()
        _ = try? await reporter.value
        await observer(.process(nil))
        try Task.checkCancellation()
        guard status == 0 else { throw AirCillerError.ffmpegStopped(build.log.snapshot) }
        if probe.isHDR {
            let initialization = directory.appendingPathComponent("video-init.mp4")
            try HDRConfigurationInjector.normalizeHLSFileType(initializationSegment: initialization)
            let compatibleDV = probe.dolbyVisionProfile == 8 && probe.dolbyVisionCompatibilityID == 1
            if probe.colorTransfer?.lowercased() == "smpte2084", !probe.isDolbyVision || compatibleDV {
                try HDRConfigurationInjector.injectStaticMetadata(
                    initializationSegment: initialization,
                    firstMediaSegment: directory.appendingPathComponent("video-00000000.m4s")
                )
            }
        }
        try SubtitleService.alignRenditionPlaylists(outputDirectory: directory, expectedDuration: probe.duration)
        _ = try validateBase(directory, probe: probe, audio: audio)
        try Task.checkCancellation()
        await observer(.ended(.packaging))
        if let cache, let key {
            await observer(.began(.cacheStore))
            do { _ = try await cache.store(key: key, from: directory) } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A cache failure must not invalidate a successfully prepared movie.
            }
            await observer(.ended(.cacheStore))
        }
        return false
    }

    private static func validateBase(_ directory: URL, probe: MediaProbe, audio: AudioTrack?) throws -> Double {
        try SubtitleService.validatePackage(
            outputDirectory: directory, expectedDuration: probe.duration,
            hasAudio: audio != nil && !probe.isHDR, hasSubtitles: false, requiresMasterPlaylist: false
        )
    }

    private static func makeBuild(
        input: URL, directory: URL, ffmpegURL: URL, probe: MediaProbe,
        audio: AudioTrack?, outputMode: AudioOutputMode, audioDelay: Double
    ) -> VODBuildProcess {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments =
            probe.isHDR
            ? VODCommandBuilder.multiplexedArguments(
                input: input, outputDirectory: directory, probe: probe,
                audio: audio, outputMode: outputMode, audioDelay: audioDelay)
            : VODCommandBuilder.arguments(
                input: input, outputDirectory: directory, probe: probe,
                audio: audio, outputMode: outputMode, audioDelay: audioDelay)
        let errors = Pipe()
        let output = Pipe()
        let log = ProcessLogBuffer()
        let progress = ProcessProgressBuffer()
        errors.fileHandleForReading.readabilityHandler = { handle in
            if let text = String(data: handle.availableData, encoding: .utf8) { log.append(text) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            if let text = String(data: handle.availableData, encoding: .utf8) { progress.append(text) }
        }
        process.standardError = errors
        process.standardOutput = output
        return VODBuildProcess(process: process, log: log, progress: progress, errorPipe: errors, progressPipe: output)
    }
}
