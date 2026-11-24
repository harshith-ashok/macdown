import AppKit
import UniformTypeIdentifiers

/// One row of the sidebar. Children load the first time the folder is expanded.
final class SidebarNode: NSObject {
    let url: URL
    let isFolder: Bool
    /// Path relative to the workspace root, built while walking. Used to remember
    /// which folders are open (never compare absolute URLs: /var vs /private/var).
    let key: String
    var children: [SidebarNode]?
    var name: String { url.lastPathComponent }

    init(_ node: WorkspaceNode, parentKey: String) {
        url = node.url
        isFolder = node.isFolder
        key = parentKey + "/" + node.url.lastPathComponent
    }
}

/// A source-list sidebar next to the editor of one document window.
///
/// It lists the Markdown files of a folder (the workspace), loads folders lazily,
/// follows file changes and opens a file in its own window when clicked.
/// Hidden by default; the shown/hidden state is remembered. With no workspace
/// chosen it shows the folder of the document.
@objc(MPSidebarController)
final class SidebarController: NSObject {
    /// The folder last chosen (Open Folder) or last used to open a file from a sidebar.
    /// New windows for files inside it show the same workspace.
    static var workspaceRoot: URL?
    private static let visibleKey = "MPSidebarVisible"

    private weak var document: NSDocument?
    private weak var window: NSWindow?
    private let split = NSSplitView()
    private let sidebarView = SolidSidebarView()
    private let outline = SidebarOutlineView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private var tree: WorkspaceTree?
    private var rootNodes: [SidebarNode] = []
    private var watcher: DirectoryWatcher?
    private var expandedKeys: Set<String> = []
    private var reloadWork: DispatchWorkItem?
    @objc private(set) var rootURL: URL?

    @objc init(document: NSDocument, window: NSWindow) {
        self.document = document
        self.window = window
        super.init()
        install(in: window)
        chooseRootForDocument()
        sidebarView.isHidden = !UserDefaults.standard.bool(forKey: Self.visibleKey)
    }

    deinit { watcher?.stop() }

    // MARK: Layout

    private func install(in window: NSWindow) {
        guard let content = window.contentView else { return }
        split.isVertical = true
        split.dividerStyle = .thin
        split.autosaveName = "MPDocumentSidebarSplit"
        window.contentView = split

        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        sidebarView.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        // Classic push button, small. No symbols or glass.
        let openButton = NSButton(title: "Open…", target: self, action: #selector(chooseFolder))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        openButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        openButton.toolTip = "Open Folder…"
        let header = NSStackView(views: [titleLabel, openButton])
        header.orientation = .horizontal
        header.distribution = .fill
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 6, right: 10)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .fullWidth
        outline.selectionHighlightStyle = .regular
        outline.backgroundColor = SolidSidebarView.color
        outline.usesAlternatingRowBackgroundColors = false
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 14
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.setAccessibilityLabel("Markdown files")
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        emptyLabel.stringValue = "Open a folder to browse its Markdown files."
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(stack)
        sidebarView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sidebarView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: sidebarView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: sidebarView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: sidebarView.widthAnchor, constant: -32),
        ])

        split.addArrangedSubview(sidebarView)
        split.addArrangedSubview(content)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.adjustSubviews()
        // First launch: a comfortable width. Later launches use the saved one.
        if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames MPDocumentSidebarSplit") == nil {
            split.setPosition(230, ofDividerAt: 0)
        }
    }

    // MARK: Showing and hiding

    @objc var isVisible: Bool { !sidebarView.isHidden }

    @objc func toggle() {
        let show = sidebarView.isHidden
        sidebarView.isHidden = !show
        UserDefaults.standard.set(show, forKey: Self.visibleKey)
        if show { reload() }
    }

    // MARK: Choosing the workspace

    /// Call after the document's file moved (Save As).
    @objc func documentURLDidChange() {
        if let root = rootURL, let file = document?.fileURL, Self.isInside(file, folder: root) {
            selectCurrentDocument()
        } else {
            chooseRootForDocument()
        }
    }

    private func chooseRootForDocument() {
        let file = document?.fileURL
        if let shared = Self.workspaceRoot, let file = file, Self.isInside(file, folder: shared) {
            setRoot(shared)
        } else {
            setRoot(file.map(Self.defaultRoot(for:)))
        }
    }

    /// The nearest folder above the file that holds a `.git` or `.obsidian` folder
    /// (a repository or a vault), looking at most 10 levels up. Otherwise the
    /// folder of the file.
    static func defaultRoot(for file: URL) -> URL {
        let fileManager = FileManager.default
        var folder = file.deletingLastPathComponent()
        let start = folder
        for _ in 0..<10 {
            for marker in [".git", ".obsidian"]
            where fileManager.fileExists(atPath: folder.appendingPathComponent(marker).path) {
                return folder
            }
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path || parent.path == "/" { break }
            folder = parent
        }
        return start
    }

    @objc func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.directoryURL = rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Self.workspaceRoot = url
        setRoot(url)
        if sidebarView.isHidden { toggle() }
    }

    private func setRoot(_ url: URL?) {
        rootURL = url
        expandedKeys = []
        watcher?.stop()
        watcher = nil
        if let url = url {
            watcher = DirectoryWatcher(root: url, latency: 0.4, queue: .main) { [weak self] _ in self?.scheduleReload() }
        }
        reload()
    }

    /// Opens the Quick Open panel for this workspace.
    @objc func quickOpen() {
        guard let root = rootURL else { return }
        QuickOpenController.shared.show(root: root, over: window) { [weak self] url in
            Self.workspaceRoot = self?.rootURL
            self?.open(url)
        }
    }

    // MARK: Loading

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func reload() {
        guard let root = rootURL else {
            tree = nil
            rootNodes = []
            titleLabel.stringValue = ""
            emptyLabel.isHidden = false
            outline.reloadData()
            return
        }
        emptyLabel.isHidden = true
        titleLabel.stringValue = root.lastPathComponent.uppercased()
        guard !sidebarView.isHidden || UserDefaults.standard.bool(forKey: Self.visibleKey) else { return }
        let tree = WorkspaceTree(root: root)
        self.tree = tree
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let nodes = tree.children(of: root).map { SidebarNode($0, parentKey: "") }
            DispatchQueue.main.async {
                guard let self = self, self.tree === tree else { return }
                self.rootNodes = nodes
                self.outline.reloadData()
                self.restoreExpansion(of: nodes)
                self.selectCurrentDocument()
            }
        }
    }

    private func restoreExpansion(of nodes: [SidebarNode]) {
        for node in nodes where node.isFolder && expandedKeys.contains(node.key) {
            outline.expandItem(node)
            restoreExpansion(of: node.children ?? [])
        }
    }

    private func loadChildren(of node: SidebarNode) -> [SidebarNode] {
        if let loaded = node.children { return loaded }
        let loaded = (tree?.children(of: node.url) ?? []).map { SidebarNode($0, parentKey: node.key) }
        node.children = loaded
        return loaded
    }

    // MARK: Current document

    /// Reveals and selects the open document's row, if it is inside the workspace.
    private func selectCurrentDocument() {
        guard let file = document?.fileURL?.resolvingSymlinksInPath().path else { return }
        func search(_ nodes: [SidebarNode]) -> SidebarNode? {
            for node in nodes {
                let path = node.url.resolvingSymlinksInPath().path
                if !node.isFolder, path == file { return node }
                if node.isFolder, file.hasPrefix(path + "/") {
                    outline.expandItem(node)
                    if let found = search(loadChildren(of: node)) { return found }
                }
            }
            return nil
        }
        if let node = search(rootNodes) {
            let row = outline.row(forItem: node)
            if row >= 0 {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }
    }

    private static func isInside(_ file: URL, folder: URL) -> Bool {
        file.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
    }

    // MARK: Actions

    @objc private func rowClicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? SidebarNode else { return }
        if node.isFolder {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            Self.workspaceRoot = rootURL
            open(node.url)
        }
    }

    private func open(_ url: URL) {
        if let current = document?.fileURL, current.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error = error { NSApp.presentError(error) }
        }
    }

    private func clickedNode() -> SidebarNode? {
        outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) as? SidebarNode : nil
    }

    @objc private func menuOpen() { if let node = clickedNode(), !node.isFolder { open(node.url) } }

    @objc private func menuReveal() {
        if let node = clickedNode() { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        else if let root = rootURL { NSWorkspace.shared.activateFileViewerSelecting([root]) }
    }

    @objc private func menuNewFile() {
        let folder: URL
        if let node = clickedNode() { folder = node.isFolder ? node.url : node.url.deletingLastPathComponent() }
        else if let root = rootURL { folder = root } else { return }
        var url = folder.appendingPathComponent("Untitled.md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Untitled \(counter).md")
            counter += 1
        }
        do {
            try Data().write(to: url, options: .withoutOverwriting)
        } catch {
            NSApp.presentError(error)
            return
        }
        reload()
        Self.workspaceRoot = rootURL
        open(url)
    }

    @objc private func menuRename() {
        guard outline.clickedRow >= 0 else { return }
        outline.editColumn(0, row: outline.clickedRow, with: nil, select: true)
    }

    @objc private func menuTrash() {
        guard let node = clickedNode() else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            NSApp.presentError(error)
        }
        reload()
    }
}

// MARK: - Data source and delegate

extension SidebarController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return rootNodes.count }
        return loadChildren(of: node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else { return rootNodes[index] }
        return loadChildren(of: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let image = NSImageView()
            let text = NSTextField()
            text.isBordered = false
            text.drawsBackground = false
            text.isEditable = true
            text.lineBreakMode = .byTruncatingTail
            text.delegate = self
            image.translatesAutoresizingMaskIntoConstraints = false
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.addSubview(text)
            cell.imageView = image
            cell.textField = text
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = node.name
        cell.imageView?.image = SidebarIcons.icon(isFolder: node.isFolder, fileExtension: node.url.pathExtension)
        cell.imageView?.contentTintColor = nil
        return cell
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? SidebarNode { expandedKeys.insert(node.key) }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? SidebarNode { expandedKeys.remove(node.key) }
    }
}

// MARK: - Renaming

extension SidebarController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let row = outline.row(for: field)
        guard row >= 0, let node = outline.item(atRow: row) as? SidebarNode else { return }
        var name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != node.name else {
            field.stringValue = node.name
            return
        }
        if !node.isFolder, !WorkspaceOptions().isMarkdown(URL(fileURLWithPath: name)) { name += ".md" }
        let target = node.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: node.url, to: target)
        } catch {
            field.stringValue = node.name
            NSApp.presentError(error)
        }
        reload()
    }
}

// MARK: - Context menu

extension SidebarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let node = clickedNode()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if let node = node, !node.isFolder { add("Open", #selector(menuOpen)) }
        add("New Markdown File", #selector(menuNewFile))
        if node != nil {
            add("Rename", #selector(menuRename))
            menu.addItem(.separator())
        }
        add("Reveal in Finder", #selector(menuReveal))
        if node != nil { add("Move to Trash", #selector(menuTrash)) }
    }
}

/// Outline view where right-click reports which row was hit.
final class SidebarOutlineView: NSOutlineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { selectRowIndexes([row], byExtendingSelection: false) }
        return super.menu(for: event)
    }
}


/// A flat, solid sidebar background. No blur or translucency.
final class SolidSidebarView: NSView {
    static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.18, green: 0.18, blue: 0.19, alpha: 1)
            : NSColor(srgbRed: 0.91, green: 0.92, blue: 0.93, alpha: 1)
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Self.color.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// The icons Finder shows: the system folder icon and the document icon for the
/// file type. Cached, because the sidebar asks for one per row.
enum SidebarIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(isFolder: Bool, fileExtension: String) -> NSImage {
        let key = isFolder ? "/folder" : fileExtension.lowercased()
        if let cached = cache[key] { return cached }
        let type: UTType = isFolder ? .folder : (UTType(filenameExtension: fileExtension) ?? .plainText)
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}
