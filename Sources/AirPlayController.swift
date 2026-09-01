import Foundation
import OSLog
import Observation

struct AirPlayDevice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let address: String
    let port: Int
    let model: String
    let osVersion: String
    let protocolVersion: String
    let pairing: String
    let requiresPassword: Bool

    var detail: String {
        [model, protocolVersion, osVersion.isEmpty ? nil : "tvOS \(osVersion)"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

enum DirectAirPlayError: LocalizedError {
    case helperMissing
    case noDevice
    case helperFailed(String)
    case authorizationRequired(String)
    case connectionTimedOut

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return L10n.text("Falta el motor AirPlay incluido en AirCiller. Vuelve a instalar la aplicación.")
        case .noDevice:
            return L10n.text("Elige un Apple TV antes de reproducir.")
        case .helperFailed(let message):
            return L10n.helperText(message)
        case .authorizationRequired(let message):
            return L10n.helperText(message)
        case .connectionTimedOut:
            return L10n.text("El Apple TV no confirmó el inicio de la reproducción a tiempo.")
        }
    }
}

enum AirPlayPairingState: Equatable {
    case idle
    case starting
    case waitingForPIN
    case verifying
    case success
    case failed(String)
}

enum AirPlayAuthorizationState: Equatable {
    case unknown
    case checking
    case authorized
    case required
}

private struct AirPlayHelperEvent: Decodable {
    let event: String
    let devices: [AirPlayDevice]?
    let device: AirPlayDevice?
    let message: String?
    let technical: String?
    let reason: String?
    let source: String?
    let credentials: String?
    let deviceName: String?
    let protocolName: String?
    let duration: Double?
    let position: Double?
    let playing: Bool?

    enum CodingKeys: String, CodingKey {
        case event, devices, device, message, technical, reason, source, credentials, deviceName, duration, position,
            playing
        case protocolName = "protocol"
    }
}

@Observable
@MainActor
final class AirPlayController {
    private(set) var devices: [AirPlayDevice] = []
    var selectedDeviceID: String?
    private(set) var isScanning = false
    private(set) var isConnected = false
    private(set) var status = "Buscando Apple TV…"
    private(set) var scanError: String?
    var isPairingPresented = false
    private(set) var pairingState: AirPlayPairingState = .idle
    private(set) var authorizationState: AirPlayAuthorizationState = .unknown

    @ObservationIgnored var onPlaybackUpdate: ((Double, Double, Bool) -> Void)?
    @ObservationIgnored var onPlaybackWaiting: ((Bool) -> Void)?
    @ObservationIgnored var onPlaybackEnded: (() -> Void)?
    @ObservationIgnored var onPlaybackStopped: (() -> Void)?
    @ObservationIgnored var onPlaybackError: ((String) -> Void)?
    @ObservationIgnored var onAuthorizationRequired: ((String) -> Void)?
    @ObservationIgnored var onPairingSucceeded: ((Bool) -> Void)?

    var selectedDevice: AirPlayDevice? {
        devices.first(where: { $0.id == selectedDeviceID })
    }

    var isSessionActive: Bool { playbackProcess != nil }

    var requiresPairing: Bool {
        guard let selectedDevice, selectedDevice.pairing == "Mandatory" else { return false }
        return authorizationState == .required
    }

    var isCheckingAuthorization: Bool {
        selectedDevice?.pairing == "Mandatory" && (authorizationState == .unknown || authorizationState == .checking)
    }

    var needsAuthorizationValidation: Bool {
        guard let selectedDevice, selectedDevice.pairing == "Mandatory" else { return false }
        return authorizationState == .authorized && validatedAuthorizationDeviceID != selectedDevice.id
    }

    private let logger = Logger(subsystem: "local.carlosciller.AirCiller", category: "AirPlay")
    @ObservationIgnored private var playbackProcess: Process?
    @ObservationIgnored private var playbackSessionID: UUID?
    @ObservationIgnored private var playbackDeviceID: String?
    @ObservationIgnored private var playbackDeviceName: String?
    @ObservationIgnored private var inputPipe: Pipe?
    @ObservationIgnored private var outputPipe: Pipe?
    @ObservationIgnored private var errorPipe: Pipe?
    @ObservationIgnored private var outputBuffer = Data()
    @ObservationIgnored private var pendingStart: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var startTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var receivedTerminalEvent = false
    @ObservationIgnored private var confirmedPlayback = false
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var timelinePosition = 0.0
    @ObservationIgnored private var timelineDuration = 0.0
    @ObservationIgnored private var timelineIsPlaying = false
    @ObservationIgnored private var timelineReferenceDate = Date()
    @ObservationIgnored private var pairingProcess: Process?
    @ObservationIgnored private var pairingSessionID: UUID?
    @ObservationIgnored private var pairingDeviceID: String?
    @ObservationIgnored private var pairingDeviceName: String?
    @ObservationIgnored private var pairingIntent = AirPlayPairingIntent()
    @ObservationIgnored private var pairingInputPipe: Pipe?
    @ObservationIgnored private var pairingOutputPipe: Pipe?
    @ObservationIgnored private var pairingErrorPipe: Pipe?
    @ObservationIgnored private var pairingOutputBuffer = Data()
    @ObservationIgnored private var pairingWasCancelled = false
    @ObservationIgnored private var successfulPairingSessionID: UUID?
    @ObservationIgnored private var pairingLifecycle = AirPlayPairingLifecycle()
    @ObservationIgnored private let credentialStore = AirPlayCredentialStore()
    @ObservationIgnored private var credentialCache: [String: String] = [:]
    @ObservationIgnored private var validatedAuthorizationDeviceID: String?

    func refreshDevices() async {
        guard !isScanning, playbackProcess == nil else { return }
        isScanning = true
        scanError = nil
        status = "Buscando Apple TV…"

        do {
            let locations = try Self.helperLocations()
            let result = try await Self.runHelper(
                script: locations.script,
                vendor: locations.vendor,
                python: locations.python,
                arguments: ["scan", "--timeout", "5"]
            )
            guard result.status == 0 else {
                throw DirectAirPlayError.helperFailed(Self.readableFailure(from: result))
            }
            guard let event = Self.decodeLastEvent(result.output), event.event == "devices" else {
                throw DirectAirPlayError.helperFailed("El motor AirPlay devolvió una respuesta de búsqueda no válida.")
            }
            devices = event.devices ?? []
            if let selectedDeviceID, devices.contains(where: { $0.id == selectedDeviceID }) {
                // Keep the user's current selection.
            } else {
                selectedDeviceID = devices.first?.id
            }
            await refreshAuthorization()
            status =
                devices.isEmpty
                ? "No se encontró ningún Apple TV"
                : (devices.count == 1
                    ? L10n.text("1 receptor disponible")
                    : L10n.format("%lld receptores disponibles", Int64(devices.count)))
        } catch {
            let message = error.localizedDescription
            scanError = message
            status = "No se pudo buscar el Apple TV"
            logger.error("Búsqueda AirPlay fallida: \(message, privacy: .private)")
        }
        isScanning = false
    }

    func selectDevice(_ deviceID: String) async {
        guard playbackProcess == nil, selectedDeviceID != deviceID else { return }
        selectedDeviceID = deviceID
        authorizationState = .unknown
        validatedAuthorizationDeviceID = nil
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        guard let device = selectedDevice else {
            authorizationState = .unknown
            return
        }
        guard device.pairing == "Mandatory" else {
            authorizationState = .authorized
            return
        }
        if credentialCache[device.id] != nil {
            authorizationState = .authorized
            return
        }

        authorizationState = .checking
        let deviceID = device.id
        let credential = await credentialStore.credential(for: deviceID)
        guard selectedDeviceID == deviceID else { return }
        if let credential, !credential.isEmpty {
            credentialCache[deviceID] = credential
            authorizationState = .authorized
        } else {
            authorizationState = .required
        }
    }

    func resetSelectedDeviceAuthorization() async throws {
        guard let device = selectedDevice else { throw DirectAirPlayError.noDevice }
        guard playbackProcess == nil else {
            throw DirectAirPlayError.helperFailed(
                L10n.text("Detén la reproducción antes de restablecer la autorización.")
            )
        }

        cancelPairing()
        let deviceID = device.id
        try await credentialStore.removeCredential(for: deviceID)

        credentialCache.removeValue(forKey: deviceID)
        validatedAuthorizationDeviceID = nil
        authorizationState = device.pairing == "Mandatory" ? .required : .authorized
        status = L10n.text("Autorización restablecida")
    }

    func validateAuthorization() async throws {
        guard let selectedDevice else { throw DirectAirPlayError.noDevice }
        guard selectedDevice.pairing == "Mandatory" else {
            authorizationState = .authorized
            validatedAuthorizationDeviceID = selectedDevice.id
            return
        }
        if validatedAuthorizationDeviceID == selectedDevice.id,
            authorizationState == .authorized
        {
            return
        }

        let deviceID = selectedDevice.id
        let credential: String
        if let cached = credentialCache[deviceID], !cached.isEmpty {
            credential = cached
        } else {
            let stored = await credentialStore.credential(for: deviceID)
            guard let stored, !stored.isEmpty else {
                markAuthorizationRequired(for: deviceID)
                throw DirectAirPlayError.authorizationRequired(
                    "Hay que autorizar AirCiller en este Apple TV antes de reproducir."
                )
            }
            credentialCache[deviceID] = stored
            credential = stored
        }

        authorizationState = .checking
        var input = try JSONSerialization.data(withJSONObject: ["credentials": credential])
        input.append(0x0A)
        let address = selectedDevice.address
        let locations = try Self.helperLocations()
        let result = try await Self.runHelper(
            script: locations.script,
            vendor: locations.vendor,
            python: locations.python,
            arguments: ["authorize", "--address", address, "--timeout", "5"],
            standardInput: input
        )
        guard selectedDeviceID == deviceID else { throw DirectAirPlayError.noDevice }

        if result.status == 0,
            let event = Self.decodeLastEvent(result.output),
            event.event == "authorized"
        {
            authorizationState = .authorized
            validatedAuthorizationDeviceID = deviceID
            status = L10n.format("%@ autorizado", selectedDevice.name)
            return
        }

        let event = Self.decodeLastEvent(result.output)
        let message = event?.message ?? Self.readableFailure(from: result)
        if event?.reason == "authorizationRequired" {
            markAuthorizationRequired(for: deviceID)
            throw DirectAirPlayError.authorizationRequired(message)
        }
        authorizationState = .authorized
        throw DirectAirPlayError.helperFailed(message)
    }

    func startPlayback(
        url: URL,
        position: Double,
        duration: Double = 0,
        title: String? = nil
    ) async throws {
        guard let selectedDevice else { throw DirectAirPlayError.noDevice }
        let credential: String?
        if selectedDevice.pairing == "Mandatory" {
            if let cached = credentialCache[selectedDevice.id] {
                credential = cached
            } else {
                let deviceID = selectedDevice.id
                credential = await credentialStore.credential(for: deviceID)
                guard let credential, !credential.isEmpty else {
                    authorizationState = .required
                    throw DirectAirPlayError.authorizationRequired(
                        "Hay que autorizar AirCiller en este Apple TV antes de reproducir."
                    )
                }
                credentialCache[deviceID] = credential
                authorizationState = .authorized
            }
        } else {
            credential = nil
        }
        stop(silently: true)
        resetTimeline(position: position, duration: duration)
        playbackDeviceID = selectedDevice.id
        playbackDeviceName = selectedDevice.name

        let sessionID = UUID()
        let locations = try Self.helperLocations()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        let errorCollector = ProcessDataBuffer(maximumBytes: 1_048_576)
        let errorDrain = DispatchGroup()
        errorDrain.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCollector.append(errors.fileHandleForReading.readDataToEndOfFile())
            errorDrain.leave()
        }
        process.executableURL = locations.python
        let displayTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = [
            locations.script.path,
            "play",
            "--address", selectedDevice.address,
            "--url", url.absoluteString,
            "--position", String(format: "%.3f", position),
            "--duration", String(format: "%.3f", max(0, duration)),
            "--title",
            displayTitle?.isEmpty == false
                ? displayTitle!
                : url.deletingPathExtension().lastPathComponent,
            "--artwork", locations.artwork.path,
            "--timeout", "5",
        ]
        process.arguments = arguments
        process.environment = Self.helperEnvironment(vendor: locations.vendor)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        playbackProcess = process
        playbackSessionID = sessionID
        inputPipe = input
        outputPipe = output
        errorPipe = errors
        outputBuffer.removeAll(keepingCapacity: true)
        stopping = false
        receivedTerminalEvent = false
        confirmedPlayback = false
        isConnected = false
        status = L10n.format("Conectando con %@…", selectedDevice.name)

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor [weak self] in
                self?.consumeOutput(data, sessionID: sessionID)
            }
        }
        process.terminationHandler = { [weak self] process in
            errorDrain.wait()
            let stderr = errorCollector.snapshot
            Task { @MainActor [weak self] in
                self?.processTerminated(
                    sessionID: sessionID,
                    status: process.terminationStatus,
                    stderr: stderr
                )
            }
        }

        do {
            try process.run()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            send(["credentials": credential ?? ""])
        } catch {
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            clearProcess(sessionID: sessionID)
            throw DirectAirPlayError.helperFailed(
                L10n.format("No se pudo abrir el motor AirPlay: %@", error.localizedDescription))
        }

        logger.info(
            "Control directo hacia \(selectedDevice.name, privacy: .private) (\(selectedDevice.address, privacy: .private))"
        )

        try await withCheckedThrowingContinuation { continuation in
            pendingStart = continuation
            startTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                        self.playbackSessionID == sessionID,
                        self.pendingStart != nil
                    else { return }
                    self.failPendingStart(DirectAirPlayError.connectionTimedOut)
                    self.stop(silently: true)
                }
            }
        }
    }

    func beginPairing(resumePlayback: Bool = false) {
        guard let selectedDevice else {
            pairingState = .failed(DirectAirPlayError.noDevice.localizedDescription)
            isPairingPresented = true
            return
        }
        isPairingPresented = true
        pairingState = .starting
        guard
            pairingLifecycle.requestStart(
                resumePlayback: resumePlayback,
                processIsActive: pairingProcess != nil
            )
        else {
            cancelRunningPairingForRestart()
            return
        }
        pairingDeviceID = selectedDevice.id
        pairingDeviceName = selectedDevice.name
        pairingIntent.begin(resumePlayback: resumePlayback)
        pairingWasCancelled = false
        successfulPairingSessionID = nil
        pairingOutputBuffer.removeAll(keepingCapacity: true)

        do {
            let sessionID = UUID()
            let locations = try Self.helperLocations()
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            let errorCollector = ProcessDataBuffer(maximumBytes: 1_048_576)
            let errorDrain = DispatchGroup()
            errorDrain.enter()
            DispatchQueue.global(qos: .utility).async {
                errorCollector.append(errors.fileHandleForReading.readDataToEndOfFile())
                errorDrain.leave()
            }
            process.executableURL = locations.python
            process.arguments = [
                locations.script.path,
                "pair",
                "--address", selectedDevice.address,
                "--timeout", "5",
            ]
            process.environment = Self.helperEnvironment(vendor: locations.vendor)
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            pairingProcess = process
            pairingSessionID = sessionID
            pairingInputPipe = input
            pairingOutputPipe = output
            pairingErrorPipe = errors

            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                Task { @MainActor [weak self] in
                    self?.consumePairingOutput(data, sessionID: sessionID)
                }
            }
            process.terminationHandler = { [weak self] process in
                errorDrain.wait()
                let stderr = errorCollector.snapshot
                Task { @MainActor [weak self] in
                    self?.pairingTerminated(
                        sessionID: sessionID,
                        status: process.terminationStatus,
                        stderr: stderr
                    )
                }
            }
            try process.run()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            status = L10n.format("Iniciando emparejamiento con %@…", selectedDevice.name)
        } catch {
            try? pairingOutputPipe?.fileHandleForWriting.close()
            try? pairingErrorPipe?.fileHandleForWriting.close()
            if let sessionID = pairingSessionID {
                clearPairingProcess(sessionID: sessionID)
            }
            pairingState = .failed(error.localizedDescription)
        }
    }

    func submitPairingPIN(_ pin: String) {
        let digits = pin.filter(\.isNumber)
        guard digits.count == 4,
            let handle = pairingInputPipe?.fileHandleForWriting
        else {
            pairingState = .failed(L10n.text("El código debe tener cuatro cifras."))
            return
        }
        pairingState = .verifying
        guard var data = try? JSONSerialization.data(withJSONObject: ["pin": digits]) else { return }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
        } catch {
            pairingState = .failed(L10n.text("No se pudo enviar el código al motor AirPlay."))
        }
    }

    func retryPairing() {
        beginPairing(resumePlayback: pairingIntent.shouldResumePlayback)
    }

    func cancelPairing(closeSheet: Bool = true) {
        pairingLifecycle.cancel()
        pairingWasCancelled = true
        successfulPairingSessionID = nil
        pairingIntent.cancel()
        try? pairingInputPipe?.fileHandleForWriting.close()
        if let process = pairingProcess {
            CancellableProcess(process).terminate()
        }
        pairingState = .idle
        if closeSheet { isPairingPresented = false }
    }

    private func cancelRunningPairingForRestart() {
        pairingWasCancelled = true
        successfulPairingSessionID = nil
        pairingIntent.cancel()
        try? pairingInputPipe?.fileHandleForWriting.close()
        if let process = pairingProcess {
            CancellableProcess(process).terminate()
        }
    }

    @discardableResult
    func pause() -> Bool {
        send(["command": "pause"])
    }

    @discardableResult
    func resume() -> Bool {
        send(["command": "resume"])
    }

    @discardableResult
    func seek(to position: Double) -> Bool {
        guard send(["command": "seek", "position": max(0, position)]) else { return false }
        timelinePosition = min(max(0, position), timelineDuration > 0 ? timelineDuration : position)
        timelineReferenceDate = Date()
        publishTimeline()
        return true
    }

    func stop(silently: Bool = false) {
        stopTimeline()
        failPendingStart(CancellationError())
        guard let process = playbackProcess else {
            isConnected = false
            playbackDeviceID = nil
            playbackDeviceName = nil
            return
        }
        stopping = true
        receivedTerminalEvent = silently
        send(["command": "stop"])
        if !silently { status = "Deteniendo AirPlay…" }
        Task { [weak process] in
            try? await Task.sleep(for: .seconds(2))
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    @discardableResult
    private func send(_ command: [String: Any]) -> Bool {
        guard let handle = inputPipe?.fileHandleForWriting,
            JSONSerialization.isValidJSONObject(command),
            var data = try? JSONSerialization.data(withJSONObject: command)
        else {
            if !stopping {
                onPlaybackError?(L10n.text("No hay un canal de control activo con el Apple TV."))
            }
            return false
        }
        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            if stopping { return false }
            let message = L10n.text("Se perdió el canal de control con el Apple TV.")
            logger.error("\(message, privacy: .public) \(error.localizedDescription, privacy: .private)")
            onPlaybackError?(message)
            return false
        }
    }

    private func consumeOutput(_ data: Data, sessionID: UUID) {
        guard playbackSessionID == sessionID else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                let event = try? JSONDecoder().decode(AirPlayHelperEvent.self, from: Data(line))
            else {
                continue
            }
            handle(event)
        }
    }

    private func consumePairingOutput(_ data: Data, sessionID: UUID) {
        guard pairingSessionID == sessionID, !pairingWasCancelled else { return }
        pairingOutputBuffer.append(data)
        while let newline = pairingOutputBuffer.firstIndex(of: 0x0A) {
            let line = pairingOutputBuffer[..<newline]
            pairingOutputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                let event = try? JSONDecoder().decode(AirPlayHelperEvent.self, from: Data(line))
            else {
                continue
            }
            switch event.event {
            case "pairingStarted":
                pairingState = .starting
            case "pinRequired":
                pairingState = .waitingForPIN
                status = L10n.format(
                    "Introduce en AirCiller el código mostrado en %@",
                    event.deviceName ?? L10n.text("el Apple TV"))
            case "paired":
                guard let deviceID = pairingDeviceID,
                    let credentials = event.credentials,
                    !credentials.isEmpty
                else {
                    pairingState = .failed(L10n.text("El Apple TV no devolvió una credencial válida."))
                    continue
                }
                let deviceName = pairingDeviceName ?? event.deviceName ?? "Apple TV"
                let shouldResumePlayback = pairingIntent.consumeSuccess()
                // Mark the verified result before the helper exits. Keychain
                // storage is serialized asynchronously and may finish just
                // after the process closes its output channel.
                successfulPairingSessionID = sessionID
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.credentialStore.storeCredential(credentials, for: deviceID)
                        guard self.successfulPairingSessionID == sessionID,
                            !self.pairingWasCancelled
                        else { return }
                        self.credentialCache[deviceID] = credentials
                        self.authorizationState = .authorized
                        // The helper emits `paired` only after verifying this exact
                        // credential on a fresh AirPlay connection.
                        self.validatedAuthorizationDeviceID = deviceID
                        self.pairingState = .success
                        self.successfulPairingSessionID = sessionID
                        self.status = L10n.format("%@ emparejado", deviceName)
                        try? await Task.sleep(for: .milliseconds(650))
                        guard self.successfulPairingSessionID == sessionID,
                            self.pairingState == .success
                        else { return }
                        self.successfulPairingSessionID = nil
                        self.isPairingPresented = false
                        self.onPairingSucceeded?(shouldResumePlayback)
                    } catch {
                        self.successfulPairingSessionID = nil
                        self.pairingState = .failed(
                            L10n.format(
                                "El emparejamiento funcionó, pero no se pudo guardar en el Llavero: %@",
                                error.localizedDescription))
                    }
                }
            case "error":
                pairingState = .failed(
                    L10n.helperText(event.message ?? "No se pudo emparejar el Apple TV."))
            default:
                break
            }
        }
    }

    private func handle(_ event: AirPlayHelperEvent) {
        switch event.event {
        case "connecting":
            let name = event.device?.name ?? playbackDeviceName ?? "Apple TV"
            status = L10n.format("Autenticando con %@…", name)
        case "accepted":
            validatedAuthorizationDeviceID = playbackDeviceID
            authorizationState = .authorized
            status = L10n.format("Orden aceptada · %@", event.protocolName ?? "AirPlay")
        case "phase":
            if let message = event.message {
                if !confirmedPlayback { status = L10n.helperText(message) }
                logger.info("AirPlay 2: \(message, privacy: .public)")
            }
        case "waiting":
            status = "Apple TV está preparando la reproducción…"
            onPlaybackWaiting?(confirmedPlayback)
        case "playing":
            confirmedPlayback = true
            isConnected = true
            status = L10n.format("Reproduciendo en %@", playbackDeviceName ?? "Apple TV")
            logger.info(
                "Reproducción confirmada position=\(event.position ?? -1, privacy: .public) duration=\(event.duration ?? -1, privacy: .public)"
            )
            applyTimelineEvent(
                position: event.position,
                duration: event.duration,
                playing: true
            )
            finishPendingStart()
        case "status":
            applyTimelineEvent(
                position: event.position,
                duration: event.duration,
                playing: event.playing ?? true
            )
        case "paused":
            status = L10n.format("En pausa en %@", playbackDeviceName ?? "Apple TV")
            if event.source == "command" {
                logger.info("Orden de pausa aceptada por el Apple TV")
            } else {
                logger.info("Pausa comunicada por el Apple TV")
            }
            applyTimelineEvent(
                position: event.position,
                duration: event.duration,
                playing: false
            )
        case "resumed":
            status = L10n.format("Reproduciendo en %@", playbackDeviceName ?? "Apple TV")
            if event.source == "command" {
                logger.info("Orden de reanudación aceptada por el Apple TV")
            } else {
                logger.info("Reanudación comunicada por el Apple TV")
            }
            applyTimelineEvent(
                position: event.position,
                duration: event.duration,
                playing: true
            )
        case "seeked":
            if let position = event.position {
                timelinePosition = min(max(0, position), timelineDuration > 0 ? timelineDuration : position)
                timelineReferenceDate = Date()
                publishTimeline()
                logger.info("Salto aceptado por el Apple TV position=\(position, privacy: .public)")
            }
        case "ended":
            receivedTerminalEvent = true
            isConnected = false
            status = "Reproducción terminada"
            logger.info("Final natural confirmado por el Apple TV")
            if timelineDuration > 0 { timelinePosition = timelineDuration }
            stopTimeline()
            onPlaybackEnded?()
        case "stopped":
            let wasStoppedLocally = stopping
            receivedTerminalEvent = true
            isConnected = false
            status = "AirPlay detenido"
            logger.info("Parada confirmada por el Apple TV")
            stopTimeline()
            publishTimeline()
            if !wasStoppedLocally { onPlaybackStopped?() }
        case "warning":
            if let message = event.message { logger.warning("\(message, privacy: .private)") }
        case "error":
            let wasStopping = stopping
            receivedTerminalEvent = true
            isConnected = false
            guard !wasStopping else { return }
            let message = L10n.helperText(
                event.message ?? "El Apple TV rechazó la reproducción sin indicar el motivo.")
            logger.error("AirPlay: \(message, privacy: .private) \(event.technical ?? "", privacy: .private)")
            let error: DirectAirPlayError =
                event.reason == "authorizationRequired"
                ? .authorizationRequired(message)
                : .helperFailed(message)
            if event.reason == "authorizationRequired", let deviceID = playbackDeviceID {
                markAuthorizationRequired(for: deviceID)
            }
            if pendingStart != nil {
                failPendingStart(error)
            } else if event.reason == "authorizationRequired" {
                onAuthorizationRequired?(message)
            } else {
                onPlaybackError?(message)
            }
        default:
            break
        }
    }

    private func processTerminated(sessionID: UUID, status terminationStatus: Int32, stderr: Data) {
        guard playbackSessionID == sessionID else { return }
        let wasStopping = stopping
        let hadTerminalEvent = receivedTerminalEvent
        let hadConfirmedPlayback = confirmedPlayback
        stopTimeline()
        clearProcess(sessionID: sessionID)

        if pendingStart != nil {
            let raw = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message =
                raw?.isEmpty == false
                ? L10n.format("El motor AirPlay se cerró antes de reproducir: %@", raw!)
                : L10n.text("El motor AirPlay se cerró antes de que el Apple TV confirmara la reproducción.")
            failPendingStart(DirectAirPlayError.helperFailed(message))
        } else if !wasStopping, !hadTerminalEvent, hadConfirmedPlayback {
            onPlaybackError?(
                L10n.format(
                    "Se cerró inesperadamente la conexión con el Apple TV (código %lld).",
                    Int64(terminationStatus)))
        }
    }

    private func pairingTerminated(sessionID: UUID, status terminationStatus: Int32, stderr: Data) {
        guard pairingSessionID == sessionID else { return }
        let wasCancelled = pairingWasCancelled
        let isFinishingVerifiedPairing = successfulPairingSessionID == sessionID
        let currentState = pairingState
        clearPairingProcess(sessionID: sessionID)
        if let resumePlayback = pairingLifecycle.processDidTerminate() {
            beginPairing(resumePlayback: resumePlayback)
            return
        }
        guard !wasCancelled, !isFinishingVerifiedPairing else { return }
        switch currentState {
        case .success, .failed:
            return
        default:
            let raw = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            pairingState = .failed(
                raw?.isEmpty == false
                    ? L10n.format("El emparejamiento se cerró: %@", raw!)
                    : L10n.format(
                        "El emparejamiento se cerró antes de ser confirmado (código %lld).",
                        Int64(terminationStatus))
            )
        }
    }

    private func finishPendingStart() {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        let continuation = pendingStart
        pendingStart = nil
        continuation?.resume()
    }

    private func failPendingStart(_ error: Error) {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        let continuation = pendingStart
        pendingStart = nil
        continuation?.resume(throwing: error)
    }

    private func clearProcess(sessionID: UUID) {
        guard playbackSessionID == sessionID else { return }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        playbackProcess = nil
        playbackSessionID = nil
        playbackDeviceID = nil
        playbackDeviceName = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        isConnected = false
        stopping = false
    }

    private func resetTimeline(position: Double, duration: Double) {
        timelineTask?.cancel()
        timelineTask = nil
        timelinePosition = max(0, position)
        timelineDuration = max(0, duration)
        timelineIsPlaying = false
        timelineReferenceDate = Date()
    }

    private func applyTimelineEvent(position: Double?, duration: Double?, playing: Bool) {
        updateTimelineClock()
        if let duration, duration.isFinite, duration > 0 {
            timelineDuration = duration
        }
        if let position, position.isFinite, position >= 0 {
            timelinePosition = min(position, timelineDuration > 0 ? timelineDuration : position)
        }
        timelineIsPlaying = playing
        timelineReferenceDate = Date()
        if playing { startTimelineTaskIfNeeded() }
        publishTimeline()
    }

    private func updateTimelineClock() {
        let now = Date()
        if timelineIsPlaying {
            timelinePosition += now.timeIntervalSince(timelineReferenceDate)
            if timelineDuration > 0 { timelinePosition = min(timelinePosition, timelineDuration) }
        }
        timelineReferenceDate = now
    }

    private func publishTimeline() {
        onPlaybackUpdate?(timelinePosition, timelineDuration, timelineIsPlaying)
    }

    private func startTimelineTaskIfNeeded() {
        guard timelineTask == nil else { return }
        timelineTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.updateTimelineClock()
                self.publishTimeline()
            }
        }
    }

    private func stopTimeline() {
        updateTimelineClock()
        timelineIsPlaying = false
        timelineTask?.cancel()
        timelineTask = nil
    }

    private func clearPairingProcess(sessionID: UUID) {
        guard pairingSessionID == sessionID else { return }
        pairingOutputPipe?.fileHandleForReading.readabilityHandler = nil
        pairingErrorPipe?.fileHandleForReading.readabilityHandler = nil
        pairingProcess = nil
        pairingSessionID = nil
        pairingInputPipe = nil
        pairingOutputPipe = nil
        pairingErrorPipe = nil
    }

    private nonisolated static func helperLocations() throws -> (
        script: URL,
        vendor: URL,
        artwork: URL,
        python: URL
    ) {
        guard let resources = Bundle.main.resourceURL else { throw DirectAirPlayError.helperMissing }
        let script = resources.appendingPathComponent("AirCillerAirPlay.py")
        let vendor = resources.appendingPathComponent("VendorPython", isDirectory: true)
        let artwork = resources.appendingPathComponent("AirCillerArtwork.png")
        let runtimeMarker = vendor.appendingPathComponent(".airciller-python-executable")
        let runtimeValue = try? String(contentsOf: runtimeMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recordedPython = runtimeValue.flatMap { BundledEngine.resolveRuntimeMarker($0) }
        let bundledPython = BundledEngine.airPlayPython()?.path
        let pythonCandidates =
            BundledEngine.isRequired
            ? [bundledPython].compactMap { $0 }
            : [
                bundledPython,
                ManagedComponentStore.executableURL(for: .airPlay)?.path,
                recordedPython?.path,
                "/opt/homebrew/opt/python@3.13/bin/python3.13",
                "/usr/local/opt/python@3.13/bin/python3.13",
            ].compactMap { $0 }
        let python =
            pythonCandidates
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
        guard FileManager.default.fileExists(atPath: script.path),
            FileManager.default.fileExists(atPath: vendor.path),
            FileManager.default.fileExists(atPath: artwork.path),
            let python,
            FileManager.default.isExecutableFile(atPath: python.path)
        else {
            throw DirectAirPlayError.helperMissing
        }
        return (script, vendor, artwork, python)
    }

    private nonisolated static func helperEnvironment(vendor: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = vendor.path
        // macOS still links /usr/bin/python3 to LibreSSL. urllib3 announces that
        // mismatch even though AirCiller only uses it on the local AirPlay link.
        // Keep every other Python warning visible for diagnostics.
        environment["PYTHONWARNINGS"] = "ignore:urllib3 v2 only supports OpenSSL"
        environment["PYTHONPYCACHEPREFIX"] =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PythonCache", isDirectory: true).path
        return environment
    }

    private nonisolated static func runHelper(
        script: URL,
        vendor: URL,
        python: URL,
        arguments: [String],
        standardInput: Data? = nil
    ) async throws -> CapturedProcessResult {
        try await CapturedProcess.run(
            executable: python,
            arguments: [script.path] + arguments,
            environment: helperEnvironment(vendor: vendor),
            standardInput: standardInput
        )
    }

    private nonisolated static func decodeLastEvent(_ data: Data) -> AirPlayHelperEvent? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").reversed().compactMap { line in
            try? JSONDecoder().decode(AirPlayHelperEvent.self, from: Data(line.utf8))
        }.first
    }

    private nonisolated static func readableFailure(from result: CapturedProcessResult) -> String {
        if let event = decodeLastEvent(result.output), let message = event.message {
            return L10n.helperText(message)
        }
        let stderr = String(data: result.errorOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr?.isEmpty == false
            ? stderr!
            : L10n.format("El motor AirPlay terminó con el código %lld.", Int64(result.status))
    }

    private func markAuthorizationRequired(for deviceID: String) {
        credentialCache.removeValue(forKey: deviceID)
        if validatedAuthorizationDeviceID == deviceID {
            validatedAuthorizationDeviceID = nil
        }
        authorizationState = .required
        Task { [credentialStore] in
            try? await credentialStore.removeCredential(for: deviceID)
        }
    }
}
