import AppKit

class QuickOpenPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?
    private var searchField: NSTextField!
    private var tableView: NSTableView!

    private var allFiles: [String] = []
    private var filteredFiles: [String] = []
    private var projectPath: String = ""
    private var editor: String = "code"

    func show(relativeTo window: NSWindow, projectPath: String, editor: String = "code") {
        self.parentWindow = window
        self.projectPath = projectPath
        self.editor = editor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
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
        searchField.placeholderString = "Search files..."
        searchField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        searchField.textColor = AppTheme.textPrimary
        searchField.backgroundColor = AppTheme.bgTertiary
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(searchField)

        // Results table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scrollView)

        tableView = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.title = ""
        col.width = 480
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
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

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        // Center on parent
        if let pFrame = parentWindow?.frame {
            let x = pFrame.midX - 250
            let y = pFrame.midY - 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)

        // Load file list
        loadFiles()
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    // MARK: - File Loading

    private func loadFiles() {
        DispatchQueue.global().async { [weak self] in
            guard let self, !self.projectPath.isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["ls-files"]
            process.currentDirectoryURL = URL(fileURLWithPath: self.projectPath)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let files = output.components(separatedBy: "\n").filter { !$0.isEmpty }

            DispatchQueue.main.async {
                self.allFiles = files
                self.filteredFiles = files
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Fuzzy Filter

    private func filterFiles(query: String) {
        if query.isEmpty {
            filteredFiles = allFiles
        } else {
            let q = query.lowercased()
            filteredFiles = allFiles.filter { fuzzyMatch(query: q, target: $0.lowercased()) }
                .sorted { scoreMatch(query: q, target: $0.lowercased()) > scoreMatch(query: q, target: $1.lowercased()) }
        }
        tableView.reloadData()
        if !filteredFiles.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        var qi = query.startIndex
        var ti = target.startIndex
        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
            }
            ti = target.index(after: ti)
        }
        return qi == query.endIndex
    }

    private func scoreMatch(query: String, target: String) -> Int {
        var score = 0
        var qi = query.startIndex
        var ti = target.startIndex
        var consecutive = 0

        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
                consecutive += 1
                score += consecutive * 2
                // Bonus for matching after separator
                if ti == target.startIndex || target[target.index(before: ti)] == "/" {
                    score += 5
                }
            } else {
                consecutive = 0
            }
            ti = target.index(after: ti)
        }
        // Prefer shorter paths
        score -= target.count / 10
        return score
    }

    // MARK: - Actions

    @objc private func openSelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredFiles.count else { return }
        let file = filteredFiles[row]
        let fullPath = (projectPath as NSString).appendingPathComponent(file)

        EditorLauncher.open(path: fullPath, editor: editor)

        dismiss()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        filterFiles(query: searchField.stringValue)
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
            let row = min(filteredFiles.count - 1, tableView.selectedRow + 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            return true
        }
        return false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { filteredFiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = filteredFiles[row]
        let cell = NSView()

        let icon = NSImageView()
        let fullPath = (projectPath as NSString).appendingPathComponent(file)
        icon.image = NSWorkspace.shared.icon(forFile: fullPath)
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)

        let label = NSTextField(labelWithString: file)
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = AppTheme.textPrimary
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        ])

        return cell
    }
}
