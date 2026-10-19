import AppKit

@main
struct NativeUndoCommandsSmokeTest {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let state = NativeUndoCommandState()
        let library = UndoManager()
        library.groupsByEvent = false
        let libraryValue = Value()
        register(library, value: libraryValue, replacement: 1, name: "Mark as Unwatched")
        state.update(manager: library)
        precondition(state.presentation.undoTitle == library.undoMenuItemTitle)
        precondition(state.presentation.canUndo && !state.presentation.canRedo)
        precondition(state.presentation.undoTitle.contains("Mark as Unwatched"))

        let editor = UndoManager()
        editor.groupsByEvent = false
        let textValue = Value()
        register(editor, value: textValue, replacement: 2, name: "Typing")
        state.update(manager: editor)
        precondition(state.presentation.undoTitle == editor.undoMenuItemTitle)
        precondition(!state.presentation.undoTitle.contains("Unwatched"))
        editor.undo()
        state.update(manager: editor)
        precondition(textValue.number == 0 && libraryValue.number == 1 && library.canUndo)
        precondition(state.presentation.canRedo && state.presentation.redoTitle == editor.redoMenuItemTitle)
        editor.redo()
        precondition(textValue.number == 2 && libraryValue.number == 1)
        library.undo()
        state.update(manager: library)
        precondition(libraryValue.number == 0 && state.presentation.redoTitle == library.redoMenuItemTitle)
        state.update(manager: nil)
        precondition(!state.presentation.canUndo && !state.presentation.canRedo)
        precondition(state.presentation.undoTitle == UndoManager().undoMenuItemTitle)
        state.start()
        state.start()
        state.stop()
        state.stop()
        print("Undo command names and availability follow the active manager; independent edits and lifecycle: OK")
    }

    @MainActor
    private static func register(_ manager: UndoManager, value: Value, replacement: Int, name: String) {
        let previous = value.number
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: value) { target in
            MainActor.assumeIsolated { register(manager, value: target, replacement: previous, name: name) }
        }
        manager.setActionName(name)
        manager.endUndoGrouping()
        value.number = replacement
    }

    @MainActor
    private final class Value { var number = 0 }
}
