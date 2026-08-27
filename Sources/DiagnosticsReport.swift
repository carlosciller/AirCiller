import Foundation

struct DiagnosticsReportSnapshot: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let systemVersion: String
    let architecture: String
    let appLanguage: String
    let playbackState: String
    let playbackRoute: String
    let currentTime: Double
    let duration: Double
    let rebufferEvents: Int
    let networkReady: Bool
    let videoCodec: String?
    let videoDimensions: String?
    let dolbyVisionProfile: Int?
    let hdr: Bool
    let audioCodec: String?
    let audioMode: String?
    let subtitleCodec: String?
    let subtitleKind: String?
    let receiverModel: String?
    let receiverSystem: String?
    let receiverProtocol: String?
    let authorizationState: String
    let ffmpegVersion: String?
    let ffmpegSource: String?
    let airPlayVersion: String?
    let airPlaySource: String?
}

enum DiagnosticsReport {
    static func render(
        _ snapshot: DiagnosticsReportSnapshot,
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let fields: [(String, String)] = [
            ("Generated", formatter.string(from: generatedAt)),
            ("AirCiller", "\(snapshot.appVersion) (\(snapshot.appBuild))"),
            ("macOS", snapshot.systemVersion),
            ("Architecture", snapshot.architecture),
            ("Language", snapshot.appLanguage),
            ("Playback state", snapshot.playbackState),
            ("Playback route", snapshot.playbackRoute),
            ("Timeline", timeline(position: snapshot.currentTime, duration: snapshot.duration)),
            ("Rebuffer events", String(snapshot.rebufferEvents)),
            ("Local network", snapshot.networkReady ? "ready" : "unavailable"),
            ("Video codec", snapshot.videoCodec ?? "not analyzed"),
            ("Video dimensions", snapshot.videoDimensions ?? "not analyzed"),
            ("Dolby Vision profile", snapshot.dolbyVisionProfile.map(String.init) ?? "none"),
            ("HDR", snapshot.hdr ? "yes" : "no"),
            ("Audio codec", snapshot.audioCodec ?? "none selected"),
            ("Audio mode", snapshot.audioMode ?? "none selected"),
            ("Subtitle codec", snapshot.subtitleCodec ?? "none selected"),
            ("Subtitle kind", snapshot.subtitleKind ?? "none selected"),
            ("Receiver model", snapshot.receiverModel ?? "not selected"),
            ("Receiver system", snapshot.receiverSystem ?? "unknown"),
            ("Receiver protocol", snapshot.receiverProtocol ?? "unknown"),
            ("Authorization", snapshot.authorizationState),
            ("FFmpeg", component(version: snapshot.ffmpegVersion, source: snapshot.ffmpegSource)),
            ("AirPlay engine", component(version: snapshot.airPlayVersion, source: snapshot.airPlaySource)),
        ]

        let lines = fields.map { "\($0.0): \(sanitize($0.1))" }
        return
            ([
                "AirCiller Diagnostics",
                "Privacy: filenames, paths, receiver names, addresses, and credentials are excluded.", "",
            ] + lines)
            .joined(separator: "\n") + "\n"
    }

    static func sanitize(_ value: String) -> String {
        var sanitized = value
        let replacements = [
            (#"(?i)\b(?:credentials?|password|token)\s*[:=]\s*[^\s,;]+"#, "[secret removed]"),
            (#"(?i)\b(?:https?|file)://[^\s]+"#, "[URL removed]"),
            (#"(?i)(?:~|/(?:Users|Volumes|private|tmp))(?:/[^\r\n,;·]*)?"#, "[path removed]"),
            (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "[address removed]"),
            (#"(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b"#, "[address removed]"),
        ]
        for (pattern, replacement) in replacements {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return sanitized
    }

    private static func timeline(position: Double, duration: Double) -> String {
        let safePosition = position.isFinite ? max(0, position) : 0
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        return String(format: "%.3f / %.3f seconds", safePosition, safeDuration)
    }

    private static func component(version: String?, source: String?) -> String {
        [version, source].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ").nilIfEmpty ?? "not available"
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
