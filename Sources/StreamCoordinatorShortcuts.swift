import Foundation

extension StreamCoordinator: ShortcutsTarget {
    var shortcutsIsBusy: Bool {
        isAnalyzing || isWaitingToStart || isPreparing || isStreaming || airPlay.isPairingPresented
            || showConversionAlert || (airPlay.authorizationState == .checking && !airPlay.isScanning)
    }
    var shortcutsHasSession: Bool { isStreaming && airPlay.isSessionActive && commandAvailability.canTogglePlayback }
    var shortcutsGeneration: UUID { playbackCommandGeneration }
    var shortcutsIsDiscovering: Bool { isShortcutsDiscoveryPending || airPlay.isScanning }
    var shortcutsReferencedPaths: Set<String> {
        Set(queueItems.map(\.path) + recentItems.map(\.path) + [selectedURL?.path].compactMap { $0 })
    }
    var shortcutsDestinations: [ShortcutsDestination] {
        airPlay.devices.map { ShortcutsDestination(id: $0.id, name: $0.name) }
    }
    var shortcutsSelectedDestinationID: String? { airPlay.selectedDeviceID }

    func shortcutsBeginDiscovery() {
        guard !isShortcutsDiscoveryPending else { return }
        isShortcutsDiscoveryPending = true
        Task {
            defer { isShortcutsDiscoveryPending = false }
            await airPlay.refreshDevices()
        }
    }

    func shortcutsSelectDestination(id: String) async {
        await airPlay.selectDevice(id)
    }

    func shortcutsLoad(_ url: URL, autoStart: Bool, fromBeginning: Bool) {
        loadVideo(url, autoStart: autoStart, startingAt: fromBeginning ? 0 : nil)
    }

    func shortcutsEnqueue(_ url: URL) {
        addToQueueFromShortcuts(url)
    }

    func shortcutsPause() -> Bool { airPlay.pause() }
    func shortcutsResume() -> Bool { airPlay.resume() }
    func shortcutsStop() { stop() }
}
