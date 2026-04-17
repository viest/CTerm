import AppKit

struct FileChange {
    let filePath: String
    let staged: Bool
    let status: GitChange.ChangeStatus
    var additions: Int = 0
    var deletions: Int = 0
}

class ChangesPanel: NSView {
    private struct GitStatusSnapshot {
        let staged: [FileChange]
        let unstaged: [FileChange]
        let hasRemote: Bool
    }

    private var stagedChanges: [FileChange] = []
    private var unstagedChanges: [FileChange] = []

    // Commit area (top)
    private var commitTextView: NSTextView!
    private var commitScrollView: NSScrollView!
    private var pushButton: NSButton!

    // File list (below commit)
    private var fileScrollView: NSScrollView!
    private var fileStackView: NSStackView!

    // Empty state
    private var emptyLabel: NSTextField!
    private var refreshInFlight = false
    private var needsRefresh = false
    var onGitRepositoryMutated: (() -> Void)?

    var currentProjectPath: String? {
        didSet {
            guard currentProjectPath != oldValue else { return }
            if currentProjectPath == nil {
                clearChanges()
                return
            }
            needsRefresh = true
            startRefreshIfNeeded()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshIfNeeded()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1).cgColor

        // -- Commit message text view (top) --
        // Wrap in a container for visible border (NSScrollView layer border is unreliable)
        let commitContainer = NSView()
        commitContainer.wantsLayer = true
        commitContainer.layer?.cornerRadius = 6
        commitContainer.layer?.borderColor = NSColor(white: 0.30, alpha: 1).cgColor
        commitContainer.layer?.borderWidth = 1
        commitContainer.layer?.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1).cgColor
        commitContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(commitContainer)

        commitScrollView = NSScrollView()
        commitScrollView.hasVerticalScroller = false
        commitScrollView.borderType = .noBorder
        commitScrollView.drawsBackground = false
        commitScrollView.translatesAutoresizingMaskIntoConstraints = false
        commitContainer.addSubview(commitScrollView)

        NSLayoutConstraint.activate([
            commitScrollView.topAnchor.constraint(equalTo: commitContainer.topAnchor, constant: 1),
            commitScrollView.leadingAnchor.constraint(equalTo: commitContainer.leadingAnchor, constant: 1),
            commitScrollView.trailingAnchor.constraint(equalTo: commitContainer.trailingAnchor, constant: -1),
            commitScrollView.bottomAnchor.constraint(equalTo: commitContainer.bottomAnchor, constant: -1),
        ])

        commitTextView = NSTextView()
        commitTextView.font = NSFont.systemFont(ofSize: 12)
        commitTextView.textColor = AppTheme.textPrimary
        commitTextView.backgroundColor = .clear
        commitTextView.insertionPointColor = AppTheme.textPrimary
        commitTextView.isEditable = true
        commitTextView.isSelectable = true
        commitTextView.isRichText = false
        commitTextView.isVerticallyResizable = true
        commitTextView.textContainerInset = NSSize(width: 6, height: 6)
        commitTextView.textContainer?.widthTracksTextView = true
        commitTextView.isAutomaticQuoteSubstitutionEnabled = false
        commitTextView.isAutomaticDashSubstitutionEnabled = false

        commitScrollView.documentView = commitTextView
        commitTextView.delegate = self

        // Placeholder label — added to container so it doesn't block text input
        let placeholder = NSTextField(labelWithString: "Commit message")
        placeholder.font = NSFont.systemFont(ofSize: 12)
        placeholder.textColor = NSColor(white: 0.38, alpha: 1)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.tag = 999
        commitContainer.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: commitContainer.topAnchor, constant: 8),
            placeholder.leadingAnchor.constraint(equalTo: commitContainer.leadingAnchor, constant: 10),
        ])

        // -- Publish/Push button (full width) --
        pushButton = NSButton(title: "  \u{2191}  Publish Branch", target: self, action: #selector(pushClicked))
        pushButton.bezelStyle = .rounded
        pushButton.wantsLayer = true
        pushButton.layer?.cornerRadius = 6
        pushButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pushButton)

        // -- File list --
        fileScrollView = NSScrollView()
        fileScrollView.hasVerticalScroller = true
        fileScrollView.borderType = .noBorder
        fileScrollView.drawsBackground = false
        fileScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fileScrollView)

        let flip = ChangesFlipView()
        flip.translatesAutoresizingMaskIntoConstraints = false
        fileScrollView.documentView = flip

        fileStackView = NSStackView()
        fileStackView.orientation = .vertical
        fileStackView.spacing = 0
        fileStackView.alignment = .leading
        fileStackView.translatesAutoresizingMaskIntoConstraints = false
        flip.addSubview(fileStackView)

        NSLayoutConstraint.activate([
            flip.topAnchor.constraint(equalTo: fileScrollView.topAnchor),
            flip.leadingAnchor.constraint(equalTo: fileScrollView.leadingAnchor),
            flip.trailingAnchor.constraint(equalTo: fileScrollView.trailingAnchor),
            fileStackView.topAnchor.constraint(equalTo: flip.topAnchor),
            fileStackView.leadingAnchor.constraint(equalTo: flip.leadingAnchor),
            fileStackView.trailingAnchor.constraint(equalTo: flip.trailingAnchor),
            fileStackView.bottomAnchor.constraint(equalTo: flip.bottomAnchor),
        ])

        // Empty label
        emptyLabel = NSTextField(labelWithString: "No changes")
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = AppTheme.textSecondary
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        // Separator below push button
        let pushSeparator = NSView()
        pushSeparator.wantsLayer = true
        pushSeparator.layer?.backgroundColor = AppTheme.border.cgColor
        pushSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pushSeparator)

        // -- Layout --
        NSLayoutConstraint.activate([
            // Commit text area at top
            commitContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            commitContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            commitContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            commitContainer.heightAnchor.constraint(equalToConstant: 68),

            // Push button below commit
            pushButton.topAnchor.constraint(equalTo: commitContainer.bottomAnchor, constant: 6),
            pushButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            pushButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pushButton.heightAnchor.constraint(equalToConstant: 28),

            // Separator below push button
            pushSeparator.topAnchor.constraint(equalTo: pushButton.bottomAnchor, constant: 6),
            pushSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            pushSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            pushSeparator.heightAnchor.constraint(equalToConstant: 1),

            // File list fills remaining space
            fileScrollView.topAnchor.constraint(equalTo: pushSeparator.bottomAnchor),
            fileScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fileScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fileScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Empty label centered in file area
            emptyLabel.centerXAnchor.constraint(equalTo: fileScrollView.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: fileScrollView.topAnchor, constant: 40),
        ])
    }

    // MARK: - Data

    private var shouldPollForChanges: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor && currentProjectPath != nil
    }

    @objc func refreshChanges() {
        refreshIfNeeded(force: true)
    }

    func refreshIfNeeded(force: Bool = false) {
        guard currentProjectPath != nil else {
            clearChanges()
            return
        }

        if force {
            needsRefresh = true
        }
        startRefreshIfNeeded()
    }

    private func startRefreshIfNeeded() {
        guard shouldPollForChanges, !refreshInFlight, needsRefresh, let path = currentProjectPath else { return }

        refreshInFlight = true
        needsRefresh = false

        DispatchQueue.global().async { [weak self] in
            let snapshot = self?.parseGitStatus(at: path) ?? GitStatusSnapshot(
                staged: [],
                unstaged: [],
                hasRemote: false
            )

            DispatchQueue.main.async {
                guard let self else { return }

                self.refreshInFlight = false

                if self.currentProjectPath == path {
                    self.stagedChanges = snapshot.staged
                    self.unstagedChanges = snapshot.unstaged
                    self.pushButton.title = snapshot.hasRemote ? "  \u{2191}  Push" : "  \u{2191}  Publish Branch"
                    self.rebuildFileList()
                }

                let shouldStartAnotherRefresh = self.currentProjectPath != nil && (self.needsRefresh || self.currentProjectPath != path)
                if shouldStartAnotherRefresh {
                    self.needsRefresh = true
                    self.startRefreshIfNeeded()
                }
            }
        }
    }

    private func clearChanges() {
        needsRefresh = false
        refreshInFlight = false
        stagedChanges = []
        unstagedChanges = []
        rebuildFileList()
    }

    private func parseGitStatus(at path: String) -> GitStatusSnapshot {
        let output = runGit(["status", "--porcelain=1", "--branch"], at: path)
        var lines = output.split(separator: "\n")
        var hasRemote = false

        if let firstLine = lines.first, firstLine.hasPrefix("## ") {
            lines.removeFirst()
            let branchInfo = String(firstLine.dropFirst(3))
            let branchToken = branchInfo.split(separator: " ").first.map(String.init) ?? branchInfo
            if branchToken.range(of: "...") != nil {
                hasRemote = true
            }
        }

        var rawChanges: [(filePath: String, indexStatus: Character, worktreeStatus: Character)] = []
        var stagedPaths: Set<String> = []
        var unstagedPaths: Set<String> = []
        for line in lines {
            let s = String(line)
            guard s.count >= 3 else { continue }
            let indexStatus = s[s.startIndex]
            let worktreeStatus = s[s.index(s.startIndex, offsetBy: 1)]
            let filePath = String(s.dropFirst(3))

            rawChanges.append((filePath: filePath, indexStatus: indexStatus, worktreeStatus: worktreeStatus))
            if indexStatus != " " && indexStatus != "?" {
                stagedPaths.insert(filePath)
            }
            if worktreeStatus != " " {
                unstagedPaths.insert(filePath)
            }
        }

        let stagedStats = loadNumstat(["diff", "--cached", "--numstat", "--"], paths: stagedPaths, at: path)
        let unstagedStats = loadNumstat(["diff", "--numstat", "--"], paths: unstagedPaths, at: path)

        var staged: [FileChange] = []
        var unstaged: [FileChange] = []
        for change in rawChanges {
            let stagedStat = stagedStats[change.filePath] ?? (0, 0)
            let unstagedStat = unstagedStats[change.filePath] ?? (0, 0)

            if change.indexStatus != " " && change.indexStatus != "?" {
                staged.append(FileChange(
                    filePath: change.filePath,
                    staged: true,
                    status: parseStatus(change.indexStatus),
                    additions: stagedStat.0,
                    deletions: stagedStat.1
                ))
            }
            if change.worktreeStatus != " " {
                let status: GitChange.ChangeStatus = (change.indexStatus == "?" && change.worktreeStatus == "?")
                    ? .untracked
                    : parseStatus(change.worktreeStatus)
                unstaged.append(FileChange(
                    filePath: change.filePath,
                    staged: false,
                    status: status,
                    additions: unstagedStat.0,
                    deletions: unstagedStat.1
                ))
            }
        }

        return GitStatusSnapshot(staged: staged, unstaged: unstaged, hasRemote: hasRemote)
    }

    private func loadNumstat(_ baseArgs: [String], paths: Set<String>, at path: String) -> [String: (Int, Int)] {
        guard !paths.isEmpty else { return [:] }

        var args = baseArgs
        args.append(contentsOf: paths.sorted())
        let output = runGit(args, at: path)

        var stats: [String: (Int, Int)] = [:]
        for line in output.split(separator: "\n") {
            let p = line.split(separator: "\t")
            if p.count >= 3 { stats[String(p[2])] = (Int(p[0]) ?? 0, Int(p[1]) ?? 0) }
        }
        return stats
    }

    private func parseStatus(_ c: Character) -> GitChange.ChangeStatus {
        switch c {
        case "A": return .added; case "M": return .modified
        case "D": return .deleted; case "R": return .renamed
        default: return .modified
        }
    }

    // MARK: - File List

    private func rebuildFileList() {
        for v in fileStackView.arrangedSubviews { fileStackView.removeArrangedSubview(v); v.removeFromSuperview() }

        let total = stagedChanges.count + unstagedChanges.count
        emptyLabel.isHidden = total > 0
        fileScrollView.isHidden = total == 0

        if !stagedChanges.isEmpty {
            addSection("Staged", count: stagedChanges.count, changes: stagedChanges, stageAll: false)
        }
        if !unstagedChanges.isEmpty {
            addSection("Unstaged", count: unstagedChanges.count, changes: unstagedChanges, stageAll: true)
        }
    }

    private func addSection(_ title: String, count: Int, changes: [FileChange], stageAll: Bool) {
        // Section header: "Unstaged 63" with +/- button
        let header = SectionHeaderRow(title: title, count: count, showStageAll: stageAll)
        header.onStageAll = { [weak self] in
            guard let self, let path = self.currentProjectPath else { return }
            DispatchQueue.global().async {
                if stageAll {
                    _ = self.runGit(["add", "-A"], at: path)
                } else {
                    _ = self.runGit(["reset", "HEAD"], at: path)
                }
                DispatchQueue.main.async {
                    self.onGitRepositoryMutated?()
                    self.refreshChanges()
                }
            }
        }
        fileStackView.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: fileStackView.widthAnchor).isActive = true

        // Group files by directory
        var dirs: [String: [FileChange]] = [:]
        var rootFiles: [FileChange] = []
        for change in changes {
            let comps = change.filePath.split(separator: "/")
            if comps.count > 1 {
                let dir = String(comps[0])
                dirs[dir, default: []].append(change)
            } else {
                rootFiles.append(change)
            }
        }

        for dir in dirs.keys.sorted() {
            // Directory header
            let dirRow = makeDirRow(dir)
            fileStackView.addArrangedSubview(dirRow)
            dirRow.widthAnchor.constraint(equalTo: fileStackView.widthAnchor).isActive = true

            for change in dirs[dir]! {
                let row = ChangeFileRow(change: change, indent: 24)
                row.onStageToggle = { [weak self] c in self?.toggleStage(c) }
                fileStackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: fileStackView.widthAnchor).isActive = true
            }
        }

        for change in rootFiles {
            let row = ChangeFileRow(change: change, indent: 8)
            row.onStageToggle = { [weak self] c in self?.toggleStage(c) }
            fileStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: fileStackView.widthAnchor).isActive = true
        }
    }

    private func makeDirRow(_ name: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let arrow = NSTextField(labelWithString: "\u{25BE}") // ▾
        arrow.font = NSFont.systemFont(ofSize: 10)
        arrow.textColor = AppTheme.textSecondary
        arrow.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(arrow)

        let label = NSTextField(labelWithString: name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            arrow.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            arrow.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    // MARK: - Git Actions

    private func toggleStage(_ change: FileChange) {
        guard let path = currentProjectPath else { return }
        DispatchQueue.global().async { [weak self] in
            _ = change.staged
                ? self?.runGit(["restore", "--staged", "--", change.filePath], at: path)
                : self?.runGit(["add", "--", change.filePath], at: path)
            DispatchQueue.main.async {
                self?.onGitRepositoryMutated?()
                self?.refreshChanges()
            }
        }
    }

    @objc private func commitClicked() {
        let msg = commitTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, let path = currentProjectPath else { return }
        DispatchQueue.global().async { [weak self] in
            _ = self?.runGit(["commit", "-m", msg], at: path)
            DispatchQueue.main.async {
                self?.onGitRepositoryMutated?()
                self?.commitTextView.string = ""
                self?.refreshChanges()
            }
        }
    }

    @objc private func pushClicked() {
        // If has commit message, commit first then push
        let msg = commitTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = currentProjectPath else { return }

        DispatchQueue.global().async { [weak self] in
            if !msg.isEmpty && !(self?.stagedChanges.isEmpty ?? true) {
                _ = self?.runGit(["commit", "-m", msg], at: path)
            }
            let br = self?.runGit(["rev-parse", "--abbrev-ref", "HEAD"], at: path)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            _ = self?.runGit(["push", "-u", "origin", br], at: path)
            DispatchQueue.main.async {
                self?.onGitRepositoryMutated?()
                self?.commitTextView.string = ""
                self?.refreshChanges()
            }
        }
    }

    private func runGit(_ args: [String], at path: String) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit(); return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" }
        catch { return "" }
    }
}

// MARK: - NSTextViewDelegate (placeholder handling)

extension ChangesPanel: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if let placeholder = commitScrollView.superview?.viewWithTag(999) {
            placeholder.isHidden = !commitTextView.string.isEmpty
        }
    }
}

private class ChangesFlipView: NSView { override var isFlipped: Bool { true } }

// MARK: - Section header row ("Unstaged 63" with + button)

private class SectionHeaderRow: NSView {
    var onStageAll: (() -> Void)?

    init(title: String, count: Int, showStageAll: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true

        let label = NSTextField(labelWithString: "\(title)  \(count)")
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = AppTheme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if showStageAll {
            let btn = NSButton(title: "+", target: self, action: #selector(stageAllClicked))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            btn.contentTintColor = AppTheme.textSecondary
            btn.translatesAutoresizingMaskIntoConstraints = false
            addSubview(btn)
            NSLayoutConstraint.activate([
                btn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                btn.centerYAnchor.constraint(equalTo: centerYAnchor),
                btn.widthAnchor.constraint(equalToConstant: 22),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func stageAllClicked() { onStageAll?() }
}

// MARK: - File row

private class ChangeFileRow: NSView {
    var onStageToggle: ((FileChange) -> Void)?
    private let change: FileChange
    private let indent: CGFloat
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(change: FileChange, indent: CGFloat = 8) {
        self.change = change
        self.indent = indent
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        onStageToggle?(change)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered { NSColor(white: 0.14, alpha: 1).setFill(); bounds.fill() }
        let h = bounds.height

        // Status icon (colored square)
        let iconFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let icon = change.staged ? "\u{25A0}" : "\u{25A1}" // ■ or □
        (icon as NSString).draw(at: NSPoint(x: indent, y: (h - 12) / 2),
            withAttributes: [.font: iconFont, .foregroundColor: change.status.color])

        // File name
        let name = (change.filePath as NSString).lastPathComponent
        (name as NSString).draw(at: NSPoint(x: indent + 16, y: (h - 13) / 2),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: AppTheme.textPrimary])

        // +N / -N on right
        let numFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        var rx = bounds.width - 8.0
        if change.deletions > 0 {
            let s = "-\(change.deletions)" as NSString
            let w = s.size(withAttributes: [.font: numFont]).width
            rx -= w
            s.draw(at: NSPoint(x: rx, y: (h - 12) / 2), withAttributes: [.font: numFont, .foregroundColor: NSColor.systemRed])
            rx -= 4
        }
        if change.additions > 0 {
            let s = "+\(change.additions)" as NSString
            let w = s.size(withAttributes: [.font: numFont]).width
            rx -= w
            s.draw(at: NSPoint(x: rx, y: (h - 12) / 2), withAttributes: [.font: numFont, .foregroundColor: NSColor.systemGreen])
        }
    }
}
