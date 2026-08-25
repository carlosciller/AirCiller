import AppKit
import Foundation
import Observation
@preconcurrency import Sparkle

@Observable
@MainActor
final class UpdateController {
    static let sparkleVersion = "2.9.6"

    private(set) var isStarted = false
    private(set) var isPlaybackBusy = false
    private(set) var automaticallyChecksForUpdates = false

    @ObservationIgnored private let configuration: UpdateConfiguration
    @ObservationIgnored private let updaterDelegate: UpdateControllerDelegate
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController

    init(bundle: Bundle = .main) {
        let updaterDelegate = UpdateControllerDelegate()
        configuration = UpdateConfiguration.load(from: bundle.infoDictionary)
        self.updaterDelegate = updaterDelegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
    }

    var isConfigured: Bool {
        configuration.isReady
    }

    var feedHost: String? {
        configuration.feedHost
    }

    var canCheckForUpdates: Bool {
        isConfigured
            && !isPlaybackBusy
            && (!isStarted || updaterController.updater.canCheckForUpdates)
    }

    func start() {
        guard isConfigured, !isStarted else { return }
        updaterController.startUpdater()
        isStarted = true
        refreshPreferences()
    }

    func checkForUpdates() {
        guard isConfigured else {
            presentConfigurationAlert()
            return
        }
        guard !isPlaybackBusy else {
            presentPlaybackBusyAlert()
            return
        }
        if !isStarted {
            start()
        }
        updaterController.checkForUpdates(nil)
    }

    func setPlaybackBusy(_ isBusy: Bool) {
        guard isPlaybackBusy != isBusy else { return }
        isPlaybackBusy = isBusy
        updaterDelegate.isPlaybackBusy = isBusy

        if !isBusy, isStarted, automaticallyChecksForUpdates {
            updaterController.updater.resetUpdateCycleAfterShortDelay()
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isStarted else { return }
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    func refreshPreferences() {
        guard isStarted else {
            automaticallyChecksForUpdates = false
            return
        }
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    private func presentConfigurationAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("Las actualizaciones no están configuradas")
        alert.informativeText = L10n.text(
            "Esta compilación local todavía no tiene una URL de actualizaciones y una clave pública EdDSA válidas."
        )
        alert.addButton(withTitle: L10n.text("Aceptar"))
        alert.runModal()
    }

    private func presentPlaybackBusyAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("Actualización aplazada")
        alert.informativeText = L10n.text(
            "Detén la reproducción o la preparación de la película antes de buscar actualizaciones."
        )
        alert.addButton(withTitle: L10n.text("Aceptar"))
        alert.runModal()
    }
}

@MainActor
private final class UpdateControllerDelegate: NSObject, SPUUpdaterDelegate {
    var isPlaybackBusy = false

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !isPlaybackBusy else {
            throw NSError(
                domain: "local.carlosciller.AirCiller.Updates",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.text(
                        "AirCiller aplazará la actualización hasta que termine la reproducción."
                    )
                ]
            )
        }
    }
}
