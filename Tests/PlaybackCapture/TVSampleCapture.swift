import AVFoundation
import CoreImage
import CoreMediaIO
import Foundation

@main
struct TVSampleCapture {
    private static func stage(_ value: String) {
        print(value)
        fflush(nil)
    }

    static func main() {
        do { try run() } catch {
            print("captureFailed")
            exit(1)
        }
    }

    private static func identity(_ device: AVCaptureDevice) -> CaptureSourceIdentity {
        CaptureSourceIdentity(
            uniqueID: device.uniqueID, name: device.localizedName, model: device.modelID,
            external: device.deviceType == .external, transport: UInt32(bitPattern: device.transportType),
            muxed: device.hasMediaType(.muxed), video: device.hasMediaType(.video), audio: device.hasMediaType(.audio),
            continuityCamera: device.isContinuityCamera, connected: device.isConnected)
    }

    private static func run() throws {
        let args = CommandLine.arguments
        let inspect = args.count == 4 && args[1] == "--inspect-source"
        let longPause = args.count == 8 && args[7] == "--long-pause"
        guard inspect || ((args.count == 7 || longPause) && args[1] == "--capture"),
            CapturePolicy.safeLabel(args[2], maximumBytes: 256),
            CapturePolicy.safeLabel(args[3], maximumBytes: 256)
        else { exit(2) }
        // Independent watchdog also bounds discovery and a stalled startRunning.
        DispatchQueue.global().asyncAfter(deadline: .now() + (longPause ? 490 : 130)) { _exit(3) }
        for (label, selector) in [
            ("screen", kCMIOHardwarePropertyAllowScreenCaptureDevices),
            ("wireless", kCMIOHardwarePropertyAllowWirelessScreenCaptureDevices),
        ] {
            var key = CMIOObjectPropertyAddress(
                mSelector: UInt32(selector), mScope: UInt32(kCMIOObjectPropertyScopeGlobal), mElement: 0)
            var enabled: UInt32 = 1
            let status = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &key, 0, nil, 4, &enabled)
            guard status == 0 else {
                stage("captureEnablementFailed \(label) \(status)")
                exit(4)
            }
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 3))
        guard let device = AVCaptureDevice(uniqueID: args[2]),
            identity(device).matches(approvedID: args[2], approvedName: args[3])
        else {
            print("captureSourceRejected")
            exit(5)
        }
        if inspect {
            print("verifiedScreenMetadataOnly")
            return
        }
        stage("captureSourceVerified")

        let directory = URL(fileURLWithPath: args[4], isDirectory: true)
        let readyURL = URL(fileURLWithPath: args[5])
        let stopURL = URL(fileURLWithPath: args[6])
        let pauseURL = stopURL.deletingLastPathComponent().appendingPathComponent("capture.sampling-paused")
        guard args[4].hasPrefix("/"), args[5].hasPrefix("/"), args[6].hasPrefix("/"),
            readyURL.lastPathComponent == "capture.ready", stopURL.lastPathComponent == "capture.stop",
            readyURL.deletingLastPathComponent() == directory.deletingLastPathComponent(),
            stopURL.deletingLastPathComponent() == directory.deletingLastPathComponent(),
            directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path,
            (try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).isDirectory == true,
            (try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty,
            !FileManager.default.fileExists(atPath: readyURL.path),
            !FileManager.default.fileExists(atPath: stopURL.path),
            !FileManager.default.fileExists(atPath: pauseURL.path)
        else { exit(6) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        // The sole input is created only after exact identity and media checks.
        // There is no default-device lookup, camera permission request or preview.
        let capture = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard input.device.uniqueID == args[2], capture.canAddInput(input) else { exit(7) }
        capture.addInput(input)
        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let audio = AVCaptureAudioDataOutput()
        audio.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 2,
        ]
        guard capture.canAddOutput(video), capture.canAddOutput(audio) else { exit(8) }
        capture.addOutput(video)
        capture.addOutput(audio)
        guard capture.inputs.count == 1, (capture.inputs.first as? AVCaptureDeviceInput)?.device.uniqueID == args[2],
            video.connection(with: .video) != nil, audio.connection(with: .audio) != nil
        else { exit(9) }
        let samples = CaptureSamples(directory: directory, readyURL: readyURL)
        video.setSampleBufferDelegate(samples, queue: samples.queue)
        audio.setSampleBufferDelegate(samples, queue: samples.queue)
        let parent = getppid()
        stage("captureSessionConfigured")
        stage("captureStarting")
        capture.startRunning()
        stage(capture.isRunning ? "captureRunning" : "captureNotRunning")
        let deadline = ProcessInfo.processInfo.systemUptime + (longPause ? 480 : CapturePolicy.maximumSeconds)
        while identity(device).matches(approvedID: args[2], approvedName: args[3]), capture.isRunning,
            getppid() == parent, !samples.hasFailed,
            !FileManager.default.fileExists(atPath: stopURL.path), ProcessInfo.processInfo.systemUptime < deadline
        {
            samples.setPersistencePaused(longPause && FileManager.default.fileExists(atPath: pauseURL.path))
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        let requestedStop =
            FileManager.default.fileExists(atPath: stopURL.path) && getppid() == parent
            && identity(device).matches(approvedID: args[2], approvedName: args[3])
        stage("captureStopping")
        capture.stopRunning()
        video.setSampleBufferDelegate(nil, queue: nil)
        audio.setSampleBufferDelegate(nil, queue: nil)
        guard try samples.finish(requestedStop: requestedStop) else { exit(10) }
        print("captureComplete")
    }
}

private final class CaptureSamples: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable
{
    let queue = DispatchQueue(label: "AirCiller.PlaybackCapture.Samples")
    private let context = CIContext()
    private let directory: URL
    private let readyURL: URL
    private var rows: [[String: Any]] = []
    private var frameCount = 0
    private var lastFrame = -Double.infinity
    private var lastAudio = -Double.infinity
    private var ready = false
    private var failed = false
    private var savedBytes = 0
    private var persistencePaused = false
    var hasFailed: Bool { queue.sync { failed } }

    func setPersistencePaused(_ paused: Bool) { queue.sync { persistencePaused = paused } }

    init(directory: URL, readyURL: URL) {
        self.directory = directory
        self.readyURL = readyURL
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard !failed, !persistencePaused else { return }
        guard rows.count < CapturePolicy.maximumRows else {
            failed = true
            return
        }
        let uptime = ProcessInfo.processInfo.systemUptime
        do {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sample) {
                guard uptime - lastFrame >= 0.5 else { return }
                guard frameCount < CapturePolicy.maximumFrames else {
                    failed = true
                    return
                }
                lastFrame = uptime
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                guard image.extent.width > 0, image.extent.height > 0 else {
                    failed = true
                    return
                }
                let scale = min(1, 960 / image.extent.width, 540 / image.extent.height)
                let reduced = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                frameCount += 1
                let name = String(format: "frame-%03d.png", frameCount)
                let file = directory.appendingPathComponent(name)
                try context.writePNGRepresentation(
                    of: reduced, to: file, format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? CapturePolicy.maximumBytes
                savedBytes += size
                guard savedBytes <= CapturePolicy.maximumBytes else {
                    failed = true
                    return
                }
                rows.append(["kind": "video", "uptime": uptime, "frame": name])
                if !ready {
                    try Data().write(to: readyURL, options: .withoutOverwriting)
                    ready = true
                    print("captureReady")
                    fflush(nil)
                }
            } else if let format = CMSampleBufferGetFormatDescription(sample),
                let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format),
                basic.pointee.mFormatID == kAudioFormatLinearPCM, basic.pointee.mBitsPerChannel == 32,
                basic.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                basic.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                let buffer = CMSampleBufferGetDataBuffer(sample)
            {
                guard uptime - lastAudio >= 0.2 else { return }
                lastAudio = uptime
                let length = CMBlockBufferGetDataLength(buffer)
                guard length > 0, length <= 1_048_576, length % 4 == 0 else {
                    failed = true
                    return
                }
                var values = [Float](repeating: 0, count: length / 4)
                let status = values.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr, values.allSatisfy(\.isFinite) else {
                    failed = true
                    return
                }
                let power = values.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(values.count)
                var row: [String: Any] = [
                    "kind": "audio", "uptime": uptime, "channels": basic.pointee.mChannelsPerFrame,
                    "rmsDBFS": power > 0 ? 10 * log10(power) : -160,
                ]
                if let frequency = CapturePolicy.testToneFrequency(
                    values, channels: Int(basic.pointee.mChannelsPerFrame), sampleRate: basic.pointee.mSampleRate)
                {
                    row["testToneHz"] = frequency
                }
                rows.append(row)
            }
        } catch { failed = true }
    }

    func finish(requestedStop: Bool) throws -> Bool {
        try queue.sync {
            let success = ready && !failed && requestedStop
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "schemaVersion": 1, "sourceVerified": true,
                    "complete": success, "rows": rows,
                ], options: [.prettyPrinted, .sortedKeys])
            let manifest = directory.appendingPathComponent("samples.json")
            try data.write(to: manifest, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
            return success
        }
    }
}
