import AppKit

class FileNode: NSObject {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?
    var gitStatus: GitChange.ChangeStatus?

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }
}

class FileBrowserView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    private var outlineView: NSOutlineView!
    private var searchField: NSTextField!
    private var rootNodes: [FileNode] = []
    private var filteredNodes: [FileNode] = []
    private var gitStatusMap: [String: GitChange.ChangeStatus] = [:]
    var currentProject: ProjectItem?
    private var isFiltering = false
    private var reloadInFlight = false
    private var needsReload = false

    var projectPath: String? {
        didSet {
            guard projectPath != oldValue else { return }
            guard let projectPath, !projectPath.isEmpty, projectPath != "/" else {
                clearContents()
                return
            }

            needsReload = true
            startReloadIfNeeded()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reloadIfNeeded()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor

        // Search field — wrapped in container for consistent border style
        let searchContainer = NSView()
        searchContainer.wantsLayer = true
        searchContainer.layer?.cornerRadius = 6
        searchContainer.layer?.borderColor = NSColor(white: 0.30, alpha: 1).cgColor
        searchContainer.layer?.borderWidth = 1
        searchContainer.layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchContainer)

        searchField = NSTextField()
        let placeholderAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.38, alpha: 1),
            .font: NSFont.systemFont(ofSize: 12)
        ]
        searchField.placeholderAttributedString = NSAttributedString(string: "Filter files...", attributes: placeholderAttrs)
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.textColor = AppTheme.textPrimary
        searchField.backgroundColor = .clear
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
        ])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        outlineView = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.title = ""
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowHeight = 28
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)

        let menu = NSMenu()
        menu.font = NSFont.systemFont(ofSize: 12)
        menu.delegate = self
        menu.addItem(withTitle: "Open in Editor", action: #selector(openInEditor), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        menu.addItem(withTitle: "Copy Path", action: #selector(copyPath), keyEquivalent: "")
        menu.addItem(withTitle: "Open in Terminal", action: #selector(openInTerminal), keyEquivalent: "")
        outlineView.menu = menu

        scrollView.documentView = outlineView

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            searchContainer.heightAnchor.constraint(equalToConstant: 26),

            separator.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 6),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            isFiltering = false
            filteredNodes = []
        } else {
            isFiltering = true
            filteredNodes = filterNodes(rootNodes, query: query)
        }
        outlineView.reloadData()
    }

    private func filterNodes(_ nodes: [FileNode], query: String) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.name.lowercased().contains(query) {
                result.append(node)
            } else if node.isDirectory, let children = node.children {
                let filtered = filterNodes(children, query: query)
                if !filtered.isEmpty {
                    let copy = FileNode(name: node.name, path: node.path, isDirectory: true)
                    copy.children = filtered
                    copy.gitStatus = node.gitStatus
                    result.append(copy)
                }
            }
        }
        return result
    }

    // MARK: - Loading

    @objc func reload() {
        reloadIfNeeded(force: true)
    }

    func reloadIfNeeded(force: Bool = false) {
        if force {
            needsReload = true
        }
        startReloadIfNeeded()
    }

    private var shouldLoadContents: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor
    }

    private func clearContents() {
        reloadInFlight = false
        needsReload = false
        rootNodes = []
        filteredNodes = []
        gitStatusMap = [:]
        isFiltering = false
        searchField.stringValue = ""
        outlineView.reloadData()
    }

    private func startReloadIfNeeded() {
        guard shouldLoadContents, !reloadInFlight, needsReload, let path = projectPath, !path.isEmpty, path != "/" else { return }

        reloadInFlight = true
        needsReload = false

        DispatchQueue.global().async { [weak self] in
            let nodes = self?.loadDirectory(path) ?? []
            let statusMap = self?.loadGitStatus(path) ?? [:]

            DispatchQueue.main.async {
                guard let self else { return }

                self.reloadInFlight = false

                if self.projectPath == path {
                    self.rootNodes = nodes
                    self.gitStatusMap = statusMap
                    self.applyGitStatus(self.rootNodes, basePath: path)
                    self.isFiltering = false
                    self.searchField.stringValue = ""
                    self.outlineView.reloadData()
                }

                let shouldStartAnotherReload = self.projectPath != nil && (self.needsReload || self.projectPath != path)
                if shouldStartAnotherReload {
                    self.needsReload = true
                    self.startReloadIfNeeded()
                }
            }
        }
    }

    private func loadDirectory(_ dirPath: String) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        let skip = Set(["node_modules", ".build"])

        return contents
            .filter { !skip.contains($0) }
            .sorted { a, b in
                let aDir = isDir(dirPath, a)
                let bDir = isDir(dirPath, b)
                if aDir != bDir { return aDir }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
            .map { name in
                let fullPath = (dirPath as NSString).appendingPathComponent(name)
                let dir = isDir(dirPath, name)
                let node = FileNode(name: name, path: fullPath, isDirectory: dir)
                if dir { node.children = nil }
                return node
            }
    }

    private func isDir(_ parent: String, _ name: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: (parent as NSString).appendingPathComponent(name), isDirectory: &isDir)
        return isDir.boolValue
    }

    private func loadGitStatus(_ path: String) -> [String: GitChange.ChangeStatus] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var map: [String: GitChange.ChangeStatus] = [:]

        for line in output.split(separator: "\n") {
            let str = String(line)
            guard str.count >= 3 else { continue }
            let sc = str.prefix(2).trimmingCharacters(in: .whitespaces)
            let fp = String(str.dropFirst(3))
            switch sc {
            case "A", "??": map[fp] = sc == "A" ? .added : .untracked
            case "M", "MM": map[fp] = .modified
            case "D": map[fp] = .deleted
            case "R": map[fp] = .renamed
            default: map[fp] = .modified
            }
        }
        return map
    }

    private func applyGitStatus(_ nodes: [FileNode], basePath: String) {
        for node in nodes {
            let rel = node.path.hasPrefix(basePath) ? String(node.path.dropFirst(basePath.count + 1)) : node.name
            node.gitStatus = gitStatusMap[rel]
            if let children = node.children { applyGitStatus(children, basePath: basePath) }
        }
    }

    private var displayNodes: [FileNode] { isFiltering ? filteredNodes : rootNodes }

    // MARK: - Actions

    @objc private func doubleClicked() {
        guard let node = selectedNode(), !node.isDirectory else { return }
        EditorLauncher.open(path: node.path, editor: EditorLauncher.resolvedEditor(for: currentProject))
    }

    @objc private func openInEditor() {
        guard let node = selectedNode() else { return }
        EditorLauncher.open(path: node.path, editor: EditorLauncher.resolvedEditor(for: currentProject))
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let first = menu.items.first, first.action == #selector(openInEditor) else { return }
        let editorName = EditorLauncher.displayName(for: EditorLauncher.resolvedEditor(for: currentProject))
        first.title = "Open in \(editorName)"
    }

    @objc private func revealInFinder() {
        guard let node = selectedNode() else { return }
        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
    }

    @objc private func copyPath() {
        guard let node = selectedNode() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    @objc private func openInTerminal() {
        guard let node = selectedNode() else { return }
        let dir = node.isDirectory ? node.path : (node.path as NSString).deletingLastPathComponent
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("cd \"\(dir)\"", forType: .string)
    }

    private func selectedNode() -> FileNode? {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        return row >= 0 ? outlineView.item(atRow: row) as? FileNode : nil
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return displayNodes.count }
        guard let node = item as? FileNode, node.isDirectory else { return 0 }
        if node.children == nil {
            node.children = loadDirectory(node.path)
            if let bp = projectPath { applyGitStatus(node.children ?? [], basePath: bp) }
        }
        return node.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return displayNodes[index] }
        return (item as! FileNode).children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? FileNode)?.isDirectory ?? false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let cell = NSView()

        let icon = NSImageView()
        let fileIcon = NSWorkspace.shared.icon(forFile: node.path)
        fileIcon.size = NSSize(width: 16, height: 16)
        icon.image = fileIcon
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)

        let nameColor = node.gitStatus?.color ?? AppTheme.textPrimary

        let label = NSTextField(labelWithString: node.name)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = nameColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        ])

        return cell
    }

}
