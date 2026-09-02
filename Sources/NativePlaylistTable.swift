import AppKit
import SwiftUI

/// A mature AppKit table is used here deliberately. It owns hit-testing,
/// insertion feedback and edge autoscroll, and only commits the model once
/// when the drag is released.
@MainActor
struct NativePlaylistTable: NSViewRepresentable {
    let streamCoordinator: StreamCoordinator

    func makeCoordinator() -> TableCoordinator {
        TableCoordinator(streamCoordinator: streamCoordinator)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = PlaylistNSTableView()
        let column = NSTableColumn(identifier: TableCoordinator.columnIdentifier)
        column.resizingMask = .autoresizingMask
        column.minWidth = 180
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 62
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.allowsTypeSelect = true
        tableView.focusRingType = .default
        tableView.registerForDraggedTypes([TableCoordinator.rowDragType])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask([], forLocal: false)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.action = #selector(TableCoordinator.selectClickedRow(_:))
        tableView.contextMenuProvider = { [weak tableCoordinator = context.coordinator] row in
            tableCoordinator?.contextMenu(for: row)
        }
        tableView.moveFocusedItem = { [weak tableCoordinator = context.coordinator] offset in
            tableCoordinator?.moveFocusedItem(by: offset) ?? false
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView

        context.coordinator.attach(to: tableView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.update(streamCoordinator: streamCoordinator, tableView: tableView)
    }

    @MainActor
    final class TableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        nonisolated static let columnIdentifier = NSUserInterfaceItemIdentifier("AirCillerPlaylistColumn")
        nonisolated static let cellIdentifier = NSUserInterfaceItemIdentifier("AirCillerPlaylistCell")
        nonisolated static let rowDragType = NSPasteboard.PasteboardType("local.carlosciller.AirCiller.playlist-row")

        private var streamCoordinator: StreamCoordinator
        private weak var tableView: NSTableView?
        private var renderedItems: [QueueMediaItem] = []
        private var renderedSelectionPath: String?
        private var renderedFocusedItemID: String?
        private var contextualItemID: String?
        private var isSynchronizingSelection = false
        let contextMenu: NSMenu

        init(streamCoordinator: StreamCoordinator) {
            self.streamCoordinator = streamCoordinator
            contextMenu = NSMenu(title: L10n.text("Playlist"))
            super.init()
        }

        func attach(to tableView: NSTableView) {
            self.tableView = tableView
            refresh(tableView, force: true)
        }

        func update(streamCoordinator: StreamCoordinator, tableView: NSTableView) {
            self.streamCoordinator = streamCoordinator
            self.tableView = tableView
            refresh(tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            renderedItems.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard renderedItems.indices.contains(row) else { return nil }
            let item = renderedItems[row]
            let cell =
                (tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? PlaylistHostingCell)
                ?? PlaylistHostingCell(identifier: Self.cellIdentifier)

            cell.setRootView(
                AnyView(
                    PlaylistMediaRow(
                        index: row,
                        item: item,
                        isSelected: renderedSelectionPath == item.path,
                        isKeyboardFocused: renderedFocusedItemID == item.id
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                )
            )
            return cell
        }

        @objc func selectClickedRow(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard renderedItems.indices.contains(row) else { return }
            streamCoordinator.selectQueueItem(renderedItems[row])
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSynchronizingSelection,
                let tableView = notification.object as? NSTableView,
                renderedItems.indices.contains(tableView.selectedRow)
            else {
                return
            }
            streamCoordinator.focusQueueItem(renderedItems[tableView.selectedRow])
        }

        func contextMenu(for row: Int) -> NSMenu? {
            contextMenu.removeAllItems()
            guard renderedItems.indices.contains(row) else {
                contextualItemID = nil
                return nil
            }

            contextualItemID = renderedItems[row].id
            select(row: row)
            contextMenu.addItem(menuItem(L10n.text("Reproducir"), action: #selector(playContextualItem)))
            contextMenu.addItem(
                menuItem(L10n.text("Reproducir desde el inicio"), action: #selector(restartContextualItem)))
            contextMenu.addItem(.separator())
            let moveUp = menuItem(L10n.text("Mover arriba"), action: #selector(moveContextualItemUp))
            moveUp.isEnabled = row > 0
            contextMenu.addItem(moveUp)
            let moveDown = menuItem(L10n.text("Mover abajo"), action: #selector(moveContextualItemDown))
            moveDown.isEnabled = row < renderedItems.count - 1
            contextMenu.addItem(moveDown)
            contextMenu.addItem(.separator())
            let moveToBeginning = menuItem(
                L10n.text("Mover al principio"), action: #selector(moveContextualItemToBeginning))
            moveToBeginning.isEnabled = row > 0
            contextMenu.addItem(moveToBeginning)
            let moveToEnd = menuItem(L10n.text("Mover al final"), action: #selector(moveContextualItemToEnd))
            moveToEnd.isEnabled = row < renderedItems.count - 1
            contextMenu.addItem(moveToEnd)
            contextMenu.addItem(.separator())
            contextMenu.addItem(
                menuItem(L10n.text("Quitar de la playlist"), action: #selector(removeContextualItem)))
            return contextMenu
        }

        @objc private func playContextualItem() {
            guard let item = contextualItem else { return }
            streamCoordinator.playQueueItem(item)
        }

        @objc private func restartContextualItem() {
            guard let item = contextualItem else { return }
            streamCoordinator.playQueueItemFromBeginning(item)
        }

        @objc private func moveContextualItemToBeginning() {
            guard let item = contextualItem else { return }
            _ = moveItem(id: item.id, by: -renderedItems.count)
        }

        @objc private func moveContextualItemUp() {
            guard let contextualItem else { return }
            _ = moveItem(id: contextualItem.id, by: -1)
        }

        @objc private func moveContextualItemDown() {
            guard let contextualItem else { return }
            _ = moveItem(id: contextualItem.id, by: 1)
        }

        @objc private func moveContextualItemToEnd() {
            guard let item = contextualItem else { return }
            _ = moveItem(id: item.id, by: renderedItems.count)
        }

        @objc private func removeContextualItem() {
            guard let item = contextualItem else { return }
            streamCoordinator.removeQueueItem(item)
            refreshAfterAction()
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard renderedItems.indices.contains(row) else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(renderedItems[row].id, forType: Self.rowDragType)
            return pasteboardItem
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard let source = info.draggingSource as? NSTableView,
                source === tableView,
                info.draggingPasteboard.availableType(from: [Self.rowDragType]) != nil
            else {
                return []
            }
            let destination = min(max(row, 0), renderedItems.count)
            tableView.setDropRow(destination, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard dropOperation == .above,
                let itemID = info.draggingPasteboard.string(forType: Self.rowDragType),
                renderedItems.contains(where: { $0.id == itemID })
            else {
                return false
            }

            let destination = min(max(row, 0), renderedItems.count)
            let destinationID = destination < renderedItems.count ? renderedItems[destination].id : nil
            if let item = renderedItems.first(where: { $0.id == itemID }) {
                streamCoordinator.focusQueueItem(item)
            }
            streamCoordinator.moveQueueItems(ids: [itemID], before: destinationID)
            refresh(tableView, force: true)
            return true
        }

        func moveFocusedItem(by offset: Int) -> Bool {
            guard let itemID = streamCoordinator.focusedQueueItemID else { return false }
            return moveItem(id: itemID, by: offset)
        }

        private func moveItem(id: String, by offset: Int) -> Bool {
            guard let item = streamCoordinator.queueItems.first(where: { $0.id == id }) else { return false }
            streamCoordinator.focusQueueItem(item)
            guard streamCoordinator.moveFocusedQueueItem(by: offset) else { return false }
            refreshAfterAction()
            return true
        }

        private func select(row: Int) {
            guard let tableView, renderedItems.indices.contains(row) else { return }
            isSynchronizingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSynchronizingSelection = false
            streamCoordinator.focusQueueItem(renderedItems[row])
        }

        private func refreshAfterAction() {
            guard let tableView else { return }
            refresh(tableView, force: true)
        }

        private var contextualItem: QueueMediaItem? {
            guard let contextualItemID else { return nil }
            return streamCoordinator.queueItems.first(where: { $0.id == contextualItemID })
        }

        private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func refresh(_ tableView: NSTableView, force: Bool = false) {
            let currentItems = streamCoordinator.queueItems
            let currentSelectionPath = streamCoordinator.selectedURL?.path
            let currentFocusedItemID = streamCoordinator.focusedQueueItemID
            guard
                force || currentItems != renderedItems || currentSelectionPath != renderedSelectionPath
                    || currentFocusedItemID != renderedFocusedItemID
            else {
                return
            }
            renderedItems = currentItems
            renderedSelectionPath = currentSelectionPath
            renderedFocusedItemID = currentFocusedItemID
            tableView.reloadData()
            isSynchronizingSelection = true
            if let currentFocusedItemID,
                let row = renderedItems.firstIndex(where: { $0.id == currentFocusedItemID })
            {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            } else {
                tableView.deselectAll(nil)
            }
            isSynchronizingSelection = false
        }
    }
}

@MainActor
private final class PlaylistHostingCell: NSTableCellView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func setRootView(_ rootView: AnyView) {
        hostingView.rootView = rootView
    }
}

@MainActor
private final class PlaylistNSTableView: NSTableView {
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var moveFocusedItem: ((Int) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep all primary mouse handling in NSTableView. SwiftUI still draws
        // each rich row, but cannot intercept selection or native drag events.
        self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(row(at: point))
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == [.command, .option] else {
            super.keyDown(with: event)
            return
        }

        let offset: Int?
        switch event.specialKey {
        case .upArrow:
            offset = -1
        case .downArrow:
            offset = 1
        default:
            offset = nil
        }
        guard let offset else {
            super.keyDown(with: event)
            return
        }
        if moveFocusedItem?(offset) != true {
            NSSound.beep()
        }
    }
}
