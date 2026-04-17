import AppKit

struct SearchResult {
    let workspace: String
    let filePath: String
    let line: Int
    let content: String
    let fullPath: String
}

class SearchPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?
    private var searchField: NSTextField!
    private var tableView: NSTableView!
    private var statusLabel: NSTextField!

    private var results: [SearchResult] = []
    private var searchPaths: [(name: String, path: String)] = []
    private var editor: String = "code"
    private var debounceTimer: Timer?

    func show(relativeTo window: NSWindow, searchPaths: [(name: String, path: String)], editor: String = "code") {
        self.parentWindow = window
        self.searchPaths = searchPaths
        self.editor = editor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = AppTheme.bgSecondary
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        self.panel = panel

        let cv = panel.contentView!
        cv.wantsLayer = true

        // Search field
        searchField = NSTextField()
        searchField.placeholderString = "Search across workspaces..."
        searchField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        searchField.textColor = AppTheme.textPrimary
        searchField.backgroundColor = AppTheme.bgTertiary
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(searchField)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = AppTheme.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(statusLabel)

        // Results table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scrollView)

        tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        col.title = ""
        col.width = 580
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 14),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        if let pFrame = parentWindow?.frame {
            let x = pFrame.midX - 300
            let y = pFrame.midY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func dismiss() {
        debounceTimer?.invalidate()
        panel?.close()
        panel = nil
    }

    // MARK: - Search

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            results = []
            tableView.reloadData()
            statusLabel.stringValue = ""
            return
        }

        statusLabel.stringValue = "Searching..."

        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            var allResults: [SearchResult] = []

            for (name, path) in self.searchPaths {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["grep", "-n", "--max-count=100", "-I", query]
                process.currentDirectoryURL = URL(fileURLWithPath: path)
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                for line in output.split(separator: "\n").prefix(100) {
                    let parts = line.split(separator: ":", maxSplits: 2)
                    if parts.count >= 3 {
                        let file = String(parts[0])
                        let lineNum = Int(parts[1]) ?? 0
                        let content = String(parts[2]).trimmingCharacters(in: .whitespaces)
                        let fullPath = (path as NSString).appendingPathComponent(file)
                        allResults.append(SearchResult(
                            workspace: name, filePath: file, line: lineNum,
                            content: content, fullPath: fullPath
                        ))
                    }
                }
            }

            DispatchQueue.main.async {
                self.results = allResults
                self.tableView.reloadData()
                self.statusLabel.stringValue = "\(allResults.count) result\(allResults.count == 1 ? "" : "s")"
            }
        }
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < results.count else { return }
        let result = results[row]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Use code -g for VS Code/Cursor to jump to line
        if editor == "code" || editor == "cursor" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, "-g", "\(result.fullPath):\(result.line)"]
        } else {
            process.arguments = ["-a", editor, result.fullPath]
        }
        try? process.run()

        dismiss()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.performSearch(query: self.searchField.stringValue)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            openSelected()
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let row = max(0, tableView.selectedRow - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let row = min(results.count - 1, tableView.selectedRow + 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        }
        return false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = results[row]
        let cell = NSView()

        // File:line
        let fileStr = "\(r.filePath):\(r.line)"
        let fileLabel = NSTextField(labelWithString: fileStr)
        fileLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        fileLabel.textColor = AppTheme.accent
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(fileLabel)

        // Content preview
        let contentLabel = NSTextField(labelWithString: r.content)
        contentLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        contentLabel.textColor = AppTheme.textSecondary
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(contentLabel)

        // Workspace badge
        let wsLabel = NSTextField(labelWithString: r.workspace)
        wsLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        wsLabel.textColor = AppTheme.textSecondary
        wsLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(wsLabel)

        NSLayoutConstraint.activate([
            fileLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            fileLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            fileLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 200),

            contentLabel.leadingAnchor.constraint(equalTo: fileLabel.trailingAnchor, constant: 8),
            contentLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: wsLabel.leadingAnchor, constant: -8),

            wsLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            wsLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}
