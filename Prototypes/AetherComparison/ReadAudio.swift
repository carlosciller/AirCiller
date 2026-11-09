import AVFoundation
import Foundation
import CryptoKit
import AudioToolbox

@main
struct ReadAudio {
    static func number(_ value: Double) -> Any { value.isFinite ? value as Any : NSNull() }
    static func main() async throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1 else { throw NSError(domain: "Expected one audio track", code: 1) }
        let assetDuration = try await asset.load(.duration)
        let trackRange = try await tracks[0].load(.timeRange)
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any]? = CommandLine.arguments.contains("--packets") ? nil : [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: settings)
        guard reader.canAdd(output) else { throw NSError(domain: "Cannot add audio output", code: 2) }
        let provider = reader.outputProvider(for: output)
        try reader.start()
        var samples = 0
        var first: Double?
        var end = 0.0
        var buffers: [[String: Any]] = []
        var digest = SHA256()
        while let ready = try await provider.next() {
            samples += ready.sampleCount
            let pts = CMTimeGetSeconds(ready.presentationTimeStamp)
            first = first ?? pts
            end = pts + CMTimeGetSeconds(ready.duration)
            let trim: String = ready.withUnsafeSampleBuffer { buffer in
                String(describing: CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault,
                    target: buffer, attachmentMode: kCMAttachmentMode_ShouldPropagate))
            }
            let bytes: Data = try ready.withUnsafeSampleBuffer { buffer in
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { return Data() }
                var data = Data(count: CMBlockBufferGetDataLength(block))
                let status = data.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: raw.baseAddress!)
                }
                guard status == noErr else { throw NSError(domain: "Read PCM bytes", code: Int(status)) }
                return data
            }
            digest.update(data: bytes)
            buffers.append(["pts": number(pts), "duration": number(CMTimeGetSeconds(ready.duration)),
                "samples": ready.sampleCount, "attachments": trim])
        }
        guard reader.status == .completed else { throw reader.error ?? NSError(domain: "Reader incomplete", code: 4) }
        var report: [String: Any] = ["status": "completed", "samples": samples,
            "decodedBytesSHA256": digest.finalize().map { String(format: "%02x", $0) }.joined(),
            "firstPTS": number(first ?? -1), "endPTS": number(end), "buffers": buffers,
            "assetDuration": number(CMTimeGetSeconds(assetDuration)), "trackStart": number(CMTimeGetSeconds(trackRange.start)),
            "trackDuration": number(CMTimeGetSeconds(trackRange.duration))]
        let formats = try await tracks[0].load(.formatDescriptions)
        if let format = formats.first, let source = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
            var input = source.pointee
            var outputFormat = AudioStreamBasicDescription(mSampleRate: input.mSampleRate,
                mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4 * input.mChannelsPerFrame, mFramesPerPacket: 1,
                mBytesPerFrame: 4 * input.mChannelsPerFrame, mChannelsPerFrame: input.mChannelsPerFrame,
                mBitsPerChannel: 32, mReserved: 0)
            var converter: AudioConverterRef?
            let status = AudioConverterNew(&input, &outputFormat, &converter)
            if status == noErr, let converter {
                defer { AudioConverterDispose(converter) }
                var prime = AudioConverterPrimeInfo()
                var size = UInt32(MemoryLayout<AudioConverterPrimeInfo>.size)
                let rc = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &size, &prime)
                report["converterPrimeInfo"] = ["status": rc, "leading": prime.leadingFrames, "trailing": prime.trailingFrames]
            } else { report["converterCreateStatus"] = status }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: .sortedKeys), as: UTF8.self))
    }
}
