import AppKit
import SwiftUI

@MainActor
struct NativeSeasonOutline: NSViewRepresentable {
    let streamCoordinator: StreamCoordinator

    func makeCoordinator() -> Coordinator { Coordinator(streamCoordinator) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = SeasonOutlineView()
        // Automatic sidebar styling resets outline row metrics when attached.
        // Set the native sidebar style first, then the two-line row metrics.
        outline.style = .sourceList
        outline.rowSizeStyle = .custom
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Library"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.rowHeight = 58
        outline.usesAutomaticRowHeights = false
        outline.indentationPerLevel = 16
        outline.selectionHighlightStyle = .regular
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.registerForDraggedTypes([Coordinator.dragType, .fileURL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.doubleAction = #selector(Coordinator.activate)
        outline.activateRow = { [weak coordinator = context.coordinator] in coordinator?.activate() }
        outline.moveRow = { [weak coordinator = context.coordinator] offset in coordinator?.moveSelection(offset) }
        outline.menuForRow = { [weak coordinator = context.coordinator] row in coordinator?.menu(row) }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = outline
        context.coordinator.refresh(outline)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let outline = scroll.documentView as? NSOutlineView else { return }
        context.coordinator.owner = streamCoordinator
        context.coordinator.refresh(outline)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let dragType = NSPasteboard.PasteboardType("local.carlosciller.AirCiller.season-row")
        var owner: StreamCoordinator
        private var roots: [Node] = []
        private var nodes: [String: Node] = [:]
        private weak var outline: NSOutlineView?
        private var syncing = false
        private var selectedID: String?
        private var contextual: Node?
        private var lastItems: [QueueMediaItem] = []
        private var lastGroups: [SeasonFolder] = []
        private var lastCurrent: String?
        private var lastFocus: String?
        private var lastUnavailable: Set<String> = []

        init(_ owner: StreamCoordinator) { self.owner = owner }

        func refresh(_ outline: NSOutlineView) {
            self.outline = outline
            guard
                lastItems != owner.queueItems || lastGroups != owner.seasonFolders
                    || lastCurrent != owner.selectedURL?.path || lastFocus != owner.focusedQueueItemID
                    || lastUnavailable != owner.unavailableLibraryPaths || roots.isEmpty
            else { return }
            lastItems = owner.queueItems
            lastGroups = owner.seasonFolders
            lastCurrent = owner.selectedURL?.path
            lastFocus = owner.focusedQueueItemID
            lastUnavailable = owner.unavailableLibraryPaths
            roots = []
            var groupsSeen = Set<String>()
            var used = Set<String>()
            for item in lastItems {
                if let groupID = item.seasonID, let group = lastGroups.first(where: { $0.id == groupID }) {
                    guard groupsSeen.insert(groupID).inserted else { continue }
                    let node = node(id: "season:" + groupID)
                    node.group = group
                    node.movie = nil
                    node.children = lastItems.filter { $0.seasonID == groupID }.map { movie in
                        let child = self.node(id: movie.id)
                        child.movie = movie
                        child.group = nil
                        child.children = []
                        used.insert(child.id)
                        return child
                    }
                    roots.append(node)
                    used.insert(node.id)
                } else {
                    let node = node(id: item.id)
                    node.movie = item
                    node.group = nil
                    node.children = []
                    roots.append(node)
                    used.insert(node.id)
                }
            }
            nodes = nodes.filter { used.contains($0.key) }
            syncing = true
            outline.reloadData()
            for node in roots where node.group?.isExpanded == true { outline.expandItem(node) }
            for node in roots where node.group?.isExpanded == false { outline.collapseItem(node) }
            let selection = owner.focusedQueueItemID ?? selectedID
            if let selection, let node = nodes[selection], outline.row(forItem: node) >= 0 {
                outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: node)), byExtendingSelection: false)
            } else {
                outline.deselectAll(nil)
            }
            syncing = false
        }

        private func node(id: String) -> Node {
            if let node = nodes[id] { return node }
            let node = Node(id)
            nodes[id] = node
            return node
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node)?.children.count ?? roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Node)?.children ?? roots)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.group != nil
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let cell = SeasonCell()
            if let group = node.group {
                cell.title.stringValue = group.title
                let watched = node.children.filter { $0.movie?.watched == true }.count
                let episodes = L10n.format(
                    node.children.count == 1 ? "%lld episodio" : "%lld episodios", Int64(node.children.count))
                let viewed = L10n.format(watched == 1 ? "%lld visto" : "%lld vistos", Int64(watched))
                cell.subtitle.stringValue = "\(episodes) · \(viewed)"
                cell.symbol.image = NSImage(
                    systemSymbolName: "folder", accessibilityDescription: L10n.text("Temporada"))
            } else if let movie = node.movie {
                cell.title.stringValue = movie.title
                cell.title.toolTip = movie.title
                cell.subtitle.stringValue =
                    movie.watched == true
                    ? L10n.text("Visto")
                    : (movie.progress > 0 && movie.progress < 1
                        ? L10n.format("Continuar en %@", TimeFormatting.duration(movie.lastPosition ?? 0))
                        : L10n.text("Pendiente"))
                let symbol =
                    owner.unavailableLibraryPaths.contains(movie.path)
                    ? "exclamationmark.triangle"
                    : (owner.selectedURL?.path == movie.path
                        ? "film" : (movie.watched == true ? "checkmark.circle" : "play.circle"))
                cell.symbol.image = NSImage(
                    systemSymbolName: symbol, accessibilityDescription: cell.subtitle.stringValue)
            }
            return cell
        }
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            selectedID = node.id
            if let movie = node.movie { owner.focusQueueItem(movie) } else { owner.clearQueueFocus() }
        }
        func outlineViewItemDidExpand(_ notification: Notification) { expansion(notification, expanded: true) }
        func outlineViewItemDidCollapse(_ notification: Notification) { expansion(notification, expanded: false) }
        private func expansion(_ notification: Notification, expanded: Bool) {
            guard !syncing, let node = notification.userInfo?["NSObject"] as? Node,
                let group = node.group
            else { return }
            if !expanded, node.children.contains(where: { $0.movie?.id == owner.focusedQueueItemID }) {
                selectedID = node.id
                owner.clearQueueFocus()
            }
            owner.setSeasonExpanded(group.id, expanded: expanded)
        }
        @objc func activate() {
            guard let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            if let movie = node.movie {
                owner.playQueueItem(movie)
            } else if outline.isItemExpanded(node) {
                outline.collapseItem(node)
            } else {
                outline.expandItem(node)
            }
        }
        func menu(_ row: Int) -> NSMenu? {
            guard let outline, let node = outline.item(atRow: row) as? Node else { return nil }
            contextual = node
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            let menu = NSMenu()
            menu.autoenablesItems = false
            if let movie = node.movie {
                add(menu, "Reproducir", #selector(play))
                add(menu, "Reproducir desde el inicio", #selector(restart))
                add(menu, "Localizar archivo…", #selector(locate))
                add(
                    menu, movie.watched == true ? "Marcar como pendiente" : "Marcar como visto",
                    #selector(toggleWatched))
            } else {
                add(menu, "Reproducir", #selector(play))
                add(menu, "Marcar como visto", #selector(markGroupWatched))
                add(menu, "Marcar como pendiente", #selector(markGroupPending))
            }
            menu.addItem(.separator())
            let siblings = (outline.parent(forItem: node) as? Node)?.children ?? roots
            let position = siblings.firstIndex(where: { $0 === node }) ?? 0
            add(menu, "Mover arriba", #selector(moveUp)).isEnabled = position > 0
            add(menu, "Mover abajo", #selector(moveDown)).isEnabled = position + 1 < siblings.count
            menu.addItem(.separator())
            add(menu, "Quitar de la playlist", #selector(remove))
            return menu
        }
        @discardableResult
        private func add(_ menu: NSMenu, _ key: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: L10n.text(key), action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            return item
        }
        @objc private func play() {
            if let movie = contextual?.movie ?? contextual?.children.first(where: { $0.movie?.watched != true })?.movie
                ?? contextual?.children.first?.movie
            {
                owner.playQueueItem(movie)
            }
        }
        @objc private func restart() { if let movie = contextual?.movie { owner.playQueueItemFromBeginning(movie) } }
        @objc private func locate() { if let movie = contextual?.movie { owner.locateLibraryFile(movie.url) } }
        @objc private func toggleWatched() {
            if let movie = contextual?.movie { owner.setWatched(movie, watched: movie.watched != true) }
        }
        @objc private func markGroupWatched() { markGroup(true) }
        @objc private func markGroupPending() { markGroup(false) }
        private func markGroup(_ watched: Bool) {
            for movie in contextual?.children.compactMap(\.movie) ?? [] { owner.setWatched(movie, watched: watched) }
        }
        @objc private func remove() {
            if let movie = contextual?.movie {
                owner.removeQueueItem(movie)
            } else if let group = contextual?.group {
                owner.removeSeason(group.id)
            }
        }
        @objc private func moveUp() { move(-1) }
        @objc private func moveDown() { move(1) }
        func moveSelection(_ offset: Int) {
            guard let outline, let node = outline.item(atRow: outline.selectedRow) as? Node else { return }
            contextual = node
            move(offset)
        }
        private func move(_ offset: Int) {
            guard let node = contextual else { return }
            if let movie = node.movie {
                owner.focusQueueItem(movie)
                _ = owner.moveFocusedQueueItem(by: offset)
            } else if let group = node.group, let index = roots.firstIndex(where: { $0 === node }) {
                let destination = offset < 0 ? index - 1 : index + 2
                guard destination >= 0 else { return }
                let before = destination < roots.count ? roots[destination].firstMovieID : nil
                owner.moveQueueItems(ids: owner.queueItems.filter { $0.seasonID == group.id }.map(\.id), before: before)
            }
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)?
        {
            guard let node = item as? Node else { return nil }
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(node.id, forType: Self.dragType)
            return pasteboard
        }
        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
            proposedItem item: Any?, proposedChildIndex index: Int
        ) -> NSDragOperation {
            if info.draggingPasteboard.availableType(from: [.fileURL]) != nil { return .copy }
            guard info.draggingSource as? NSOutlineView === outlineView,
                let id = info.draggingPasteboard.string(forType: Self.dragType), let source = nodes[id],
                let destination = resolvedDrop(
                    source: source, item: item, index: index, outline: outlineView, location: info.draggingLocation)
            else { return [] }
            outlineView.setDropItem(destination.parent, dropChildIndex: destination.index)
            return .move
        }

        private func resolvedDrop(
            source: Node, item: Any?, index: Int, outline: NSOutlineView, location: NSPoint
        ) -> (parent: Node?, index: Int)? {
            var parent = item as? Node
            var insertion = index
            if index == NSOutlineViewDropOnItemIndex {
                guard let target = parent else { return nil }
                if let season = source.movie?.seasonID, target.group?.id == season {
                    return (target, target.children.count)
                }
                parent = outline.parent(forItem: target) as? Node
                let siblings = parent?.children ?? roots
                guard let targetIndex = siblings.firstIndex(where: { $0 === target }) else { return nil }
                let row = outline.row(forItem: target)
                guard row >= 0 else { return nil }
                let point = outline.convert(location, from: nil)
                let frame = outline.rect(ofRow: row)
                let before = outline.isFlipped ? point.y < frame.midY : point.y > frame.midY
                insertion = targetIndex + (before ? 0 : 1)
            }
            if let season = source.movie?.seasonID {
                // The root boundaries around this season also accept its first/last insertion.
                if parent == nil, let rootIndex = roots.firstIndex(where: { $0.group?.id == season }) {
                    if insertion == rootIndex {
                        parent = roots[rootIndex]
                        insertion = 0
                    } else if insertion == rootIndex + 1 {
                        parent = roots[rootIndex]
                        insertion = roots[rootIndex].children.count
                    }
                }
                guard parent?.group?.id == season else { return nil }
            } else {
                guard parent == nil else { return nil }
            }
            let count = parent?.children.count ?? roots.count
            guard (0...count).contains(insertion) else { return nil }
            return (parent, insertion)
        }
        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
            item: Any?, childIndex index: Int
        ) -> Bool {
            if let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
            {
                owner.handleURLs(urls, analyzeFirst: false)
                return true
            }
            guard info.draggingSource as? NSOutlineView === outlineView,
                let id = info.draggingPasteboard.string(forType: Self.dragType), let source = nodes[id],
                let destination = resolvedDrop(
                    source: source, item: item, index: index, outline: outlineView, location: info.draggingLocation)
            else { return false }
            let siblings = destination.parent?.children ?? roots
            let before = destination.index < siblings.count ? siblings[destination.index].firstMovieID : nil
            let ids =
                source.group.map { group in owner.queueItems.filter { $0.seasonID == group.id }.map(\.id) }
                ?? [source.id]
            owner.moveQueueItems(ids: ids, before: before)
            return true
        }
    }
}

@MainActor
private final class Node: NSObject {
    let id: String
    var group: SeasonFolder?
    var movie: QueueMediaItem?
    var children: [Node] = []
    var firstMovieID: String? { movie?.id ?? children.first?.movie?.id }
    init(_ id: String) { self.id = id }
}

@MainActor
private final class SeasonCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    let symbol = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.imageScaling = .scaleProportionallyDown
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        addSubview(stack)
        textField = title
        imageView = symbol
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 20), symbol.heightAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    convenience init() { self.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
private final class SeasonOutlineView: NSOutlineView {
    var activateRow: (() -> Void)?
    var moveRow: ((Int) -> Void)?
    var menuForRow: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? {
        menuForRow?(row(at: convert(event.locationInWindow, from: nil)))
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == [.command, .option], event.specialKey == .upArrow {
            moveRow?(-1)
            return
        }
        if modifiers == [.command, .option], event.specialKey == .downArrow {
            moveRow?(1)
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            [36, 76].contains(event.keyCode)
        {
            activateRow?()
            return
        }
        super.keyDown(with: event)
    }
}
