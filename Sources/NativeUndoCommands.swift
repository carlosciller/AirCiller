import AppKit
import SwiftUI

/// Exposes AppKit's current responder Undo manager without replacing its actions.
@MainActor
final class NativeUndoCommandState: NSObject, ObservableObject {
    struct Presentation: Equatable {
        let undoTitle: String
        let redoTitle: String
        let canUndo: Bool
        let canRedo: Bool

        @MainActor init(manager: UndoManager?) {
            let manager = manager ?? UndoManager()
            undoTitle = manager.undoMenuItemTitle
            redoTitle = manager.redoMenuItemTitle
            canUndo = manager.canUndo
            canRedo = manager.canRedo
        }
    }

    @Published private(set) var presentation = Presentation(manager: nil)
    private var isObserving = false

    func start() {
        guard !isObserving else { return }
        isObserving = true
        for name in [
            Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange,
            Notification.Name.NSUndoManagerDidRedoChange, NSMenu.didBeginTrackingNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification, NSText.didChangeNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        refresh()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        isObserving = false
    }

    @objc func refresh() {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        update(manager: window?.firstResponder?.undoManager ?? window?.undoManager)
    }

    func update(manager: UndoManager?) {
        let current = Presentation(manager: manager)
        if presentation != current { presentation = current }
    }

    func performUndo() {
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        refresh()
    }

    func performRedo() {
        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        refresh()
    }
}

struct NativeUndoCommands: Commands {
    @ObservedObject var state: NativeUndoCommandState

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(state.presentation.undoTitle) { state.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!state.presentation.canUndo)
            Button(state.presentation.redoTitle) { state.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.presentation.canRedo)
        }
    }
}
