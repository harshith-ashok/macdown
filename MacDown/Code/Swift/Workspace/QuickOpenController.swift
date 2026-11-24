import AppKit

/// "Quick Open": a small panel with a search field. Typing narrows the Markdown
/// files of the workspace with fuzzy matching; Return opens the selected one.
/// The file list and the matching run off the main thread.
final class QuickOpenController: NSObject {
    static let shared = QuickOpenController()

    private let panel: NSPanel
    private let field = NSSearchField()
    private let table = NSTableView()
    private var root: URL?
    private var allFiles: [String] = []
    private var results: [String] = []
    private var generation = 0
    private var onOpen: ((URL) -> Void)?
    private let queue = DispatchQueue(label: "macdown.quickopen", qos: .userInitiated)

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        panel.title = "Quick Open"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        field.placeholderString = "Search Markdown files"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel("Matching files")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(field)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        panel.contentView = content
    }

    func show(root: URL, over window: NSWindow?, onOpen: @escaping (URL) -> Void) {
        self.root = root
        self.onOpen = onOpen
        allFiles = []
        results = []
        field.stringValue = ""
        table.reloadData()
        if let frame = window?.frame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 80))
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)

        let tree = WorkspaceTree(root: root)
        queue.async { [weak self] in
            let files = tree.allMarkdownFiles()
            DispatchQueue.main.async {
                guard let self = self, self.root == root else { return }
                self.allFiles = files
                self.search()
            }
        }
    }

    private func search() {
        generation += 1
        let current = generation
        let query = field.stringValue
        let files = allFiles
        queue.async { [weak self] in
            var scored: [(String, Int)] = []
            for path in files {
                if let score = FuzzyMatcher.score(query: query, candidate: path) { scored.append((path, score)) }
            }
            let top = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(100).map(\.0)
            DispatchQueue.main.async {
                guard let self = self, self.generation == current else { return }
                self.results = Array(top)
                self.table.reloadData()
                if !self.results.isEmpty { self.table.selectRowIndexes([0], byExtendingSelection: false) }
            }
        }
    }

    @objc private func openSelected() {
        let row = table.selectedRow
        guard row >= 0, row < results.count, let root = root else { return }
        // Build the URL from the root and the relative path (never strip prefixes).
        let url = results[row].split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
        panel.orderOut(nil)
        onOpen?(url)
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = min(max(table.selectedRow + delta, 0), results.count - 1)
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }
}

extension QuickOpenController: NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    func controlTextDidChange(_ obj: Notification) { search() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): openSelected(); return true
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1); return true
        case #selector(NSResponder.cancelOperation(_:)): panel.orderOut(nil); return true
        default: return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingHead
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let path = results[row]
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        let text = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        if !folder.isEmpty {
            text.append(NSAttributedString(string: "  " + folder, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        }
        cell.textField?.attributedStringValue = text
        return cell
    }
}
