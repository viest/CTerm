import AppKit

enum WorkspaceCreationMode: Int {
    case newBranch = 0
    case existingBranch = 1
    case pullRequest = 2
}

class NewWorkspaceSheet: NSObject {
    var onConfirm: ((ProjectItem, String, String, AgentPresetItem) -> Void)?
    // For existing branch mode (no -b flag)
    var onConfirmExisting: ((ProjectItem, String, String, AgentPresetItem) -> Void)?

    private let projects: [ProjectItem]
    private let presets: [AgentPresetItem]
    private let selectedProjectIndex: Int?

    private var sheet: NSPanel?
    private weak var parentWindow: NSWindow?
    private var projectPopup: NSPopUpButton!
    private var modeControl: NSSegmentedControl!

    // New Branch mode
    private var branchField: NSTextField!
    // Existing Branch mode
    private var branchListPopup: NSPopUpButton!
    // PR mode
    private var prField: NSTextField!

    private var promptTextView: NSTextView!
    private var agentPopup: NSPopUpButton!

    private var currentMode: WorkspaceCreationMode = .newBranch

    init(projects: [ProjectItem], presets: [AgentPresetItem], selectedProject: ProjectItem? = nil) {
        self.projects = projects
        self.presets = presets
        self.selectedProjectIndex = selectedProject.flatMap { sel in projects.firstIndex { $0.id == sel.id } }
        super.init()
    }

    func show(relativeTo window: NSWindow) {
        self.parentWindow = window

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        self.sheet = panel

        let cv = panel.contentView!
        cv.wantsLayer = true

        let pad: CGFloat = 24
        let fieldW: CGFloat = 412
        var y: CGFloat = 400

        // Title
        let title = makeLabel("New Workspace", size: 17, weight: .bold, color: AppTheme.textPrimary)
        title.frame = NSRect(x: pad, y: y, width: 300, height: 22)
        cv.addSubview(title)
        y -= 36

        // Mode selector
        modeControl = NSSegmentedControl(labels: ["New Branch", "Existing Branch", "Pull Request"],
                                          trackingMode: .selectOne,
                                          target: self,
                                          action: #selector(modeChanged(_:)))
        modeControl.selectedSegment = 0
        modeControl.frame = NSRect(x: pad, y: y, width: fieldW, height: 24)
        modeControl.segmentDistribution = .fillEqually
        cv.addSubview(modeControl)
        y -= 30

        // Project
        cv.addSubview(makeSectionLabel("PROJECT", y: y))
        y -= 26
        projectPopup = makePopup(frame: NSRect(x: pad, y: y, width: fieldW, height: 26))
        for p in projects { projectPopup.addItem(withTitle: p.name) }
        if let idx = selectedProjectIndex { projectPopup.selectItem(at: idx) }
        projectPopup.target = self
        projectPopup.action = #selector(projectChanged(_:))
        cv.addSubview(projectPopup)
        y -= 34

        // Branch (New Branch mode)
        cv.addSubview(makeSectionLabel("BRANCH", y: y))
        y -= 26
        branchField = makeTextField(placeholder: "auto-generated from prompt", frame: NSRect(x: pad, y: y, width: fieldW, height: 24))
        cv.addSubview(branchField)

        // Branch list (Existing Branch mode) — same position, hidden initially
        branchListPopup = makePopup(frame: NSRect(x: pad, y: y, width: fieldW, height: 26))
        branchListPopup.isHidden = true
        cv.addSubview(branchListPopup)

        // PR field (Pull Request mode) — same position, hidden initially
        prField = makeTextField(placeholder: "PR number or URL (e.g. 123)", frame: NSRect(x: pad, y: y, width: fieldW, height: 24))
        prField.isHidden = true
        cv.addSubview(prField)
        y -= 34

        // Prompt
        cv.addSubview(makeSectionLabel("TASK DESCRIPTION", y: y))
        y -= 78
        let scrollView = NSScrollView(frame: NSRect(x: pad, y: y, width: fieldW, height: 70))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        scrollView.layer?.borderWidth = 1
        scrollView.drawsBackground = false

        promptTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: fieldW - 4, height: 70))
        promptTextView.font = NSFont.systemFont(ofSize: 12)
        promptTextView.textColor = AppTheme.textPrimary
        promptTextView.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1)
        promptTextView.insertionPointColor = AppTheme.textPrimary
        promptTextView.isRichText = false
        promptTextView.textContainerInset = NSSize(width: 6, height: 6)
        promptTextView.delegate = self
        scrollView.documentView = promptTextView
        cv.addSubview(scrollView)
        y -= 34

        // Agent
        cv.addSubview(makeSectionLabel("AGENT", y: y))
        y -= 26
        agentPopup = makePopup(frame: NSRect(x: pad, y: y, width: fieldW, height: 26))
        for preset in presets { agentPopup.addItem(withTitle: preset.name) }
        cv.addSubview(agentPopup)
        y -= 44

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: pad + fieldW - 168, y: y, width: 78, height: 28)
        cv.addSubview(cancelBtn)

        let createBtn = NSButton(title: "Create", target: self, action: #selector(createClicked))
        createBtn.bezelStyle = .rounded
        createBtn.hasDestructiveAction = false
        createBtn.keyEquivalent = "\r"
        createBtn.contentTintColor = .white
        createBtn.frame = NSRect(x: pad + fieldW - 84, y: y, width: 84, height: 28)
        if #available(macOS 11.0, *) {
            createBtn.bezelColor = AppTheme.accent
        }
        cv.addSubview(createBtn)

        window.beginSheet(panel)
    }

    // MARK: - Mode Switching

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        currentMode = WorkspaceCreationMode(rawValue: sender.selectedSegment) ?? .newBranch
        branchField.isHidden = (currentMode != .newBranch)
        branchListPopup.isHidden = (currentMode != .existingBranch)
        prField.isHidden = (currentMode != .pullRequest)

        if currentMode == .existingBranch {
            loadBranches()
        }
    }

    @objc private func projectChanged(_ sender: NSPopUpButton) {
        if currentMode == .existingBranch {
            loadBranches()
        }
    }

    private func loadBranches() {
        branchListPopup.removeAllItems()
        let projIdx = projectPopup.indexOfSelectedItem
        guard projIdx >= 0 && projIdx < projects.count else { return }
        let project = projects[projIdx]

        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["branch", "--list", "--format=%(refname:short)"]
            process.currentDirectoryURL = URL(fileURLWithPath: project.path)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let branches = output.components(separatedBy: "\n").filter { !$0.isEmpty }

            DispatchQueue.main.async {
                self?.branchListPopup.removeAllItems()
                for branch in branches {
                    self?.branchListPopup.addItem(withTitle: branch)
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func cancelClicked() {
        dismiss()
    }

    @objc private func createClicked() {
        let projIdx = projectPopup.indexOfSelectedItem
        guard projIdx >= 0 && projIdx < projects.count else { return }
        let project = projects[projIdx]

        let agentIdx = agentPopup.indexOfSelectedItem
        guard agentIdx >= 0 && agentIdx < presets.count else { return }
        let agent = presets[agentIdx]

        let prompt = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        switch currentMode {
        case .newBranch:
            var branch = branchField.stringValue.trimmingCharacters(in: .whitespaces)
            if branch.isEmpty {
                let suffix = String(format: "%04x", arc4random_uniform(65536))
                let base = prompt.isEmpty ? "workspace-\(suffix)" :
                    String(prompt.lowercased()
                        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                        .prefix(36)) + "-" + suffix
                branch = "cterm/\(base)"
            }
            dismiss()
            onConfirm?(project, branch, prompt, agent)

        case .existingBranch:
            guard let selectedBranch = branchListPopup.selectedItem?.title else { return }
            dismiss()
            onConfirmExisting?(project, selectedBranch, prompt, agent)

        case .pullRequest:
            let prInput = prField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !prInput.isEmpty else { return }
            dismiss()
            resolvePRBranch(project: project, prInput: prInput, prompt: prompt, agent: agent)
        }
    }

    private func resolvePRBranch(project: ProjectItem, prInput: String, prompt: String, agent: AgentPresetItem) {
        // Extract PR number from URL or direct input
        let prNumber: String
        if let range = prInput.range(of: #"/pull/(\d+)"#, options: .regularExpression) {
            let match = prInput[range]
            prNumber = String(match.split(separator: "/").last ?? "")
        } else {
            prNumber = prInput.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        }

        guard !prNumber.isEmpty else { return }

        DispatchQueue.global().async { [weak self] in
            // Try gh CLI first
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "pr", "view", prNumber, "--json", "headRefName", "--jq", ".headRefName"]
            process.currentDirectoryURL = URL(fileURLWithPath: project.path)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 && !branch.isEmpty {
                    // Fetch the branch first
                    let fetchProcess = Process()
                    fetchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                    fetchProcess.arguments = ["fetch", "origin", branch]
                    fetchProcess.currentDirectoryURL = URL(fileURLWithPath: project.path)
                    fetchProcess.standardOutput = Pipe()
                    fetchProcess.standardError = Pipe()
                    try? fetchProcess.run()
                    fetchProcess.waitUntilExit()

                    DispatchQueue.main.async {
                        self?.onConfirmExisting?(project, branch, prompt, agent)
                    }
                } else {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "PR Not Found"
                        alert.informativeText = "Could not resolve PR #\(prNumber). Make sure 'gh' CLI is installed and authenticated."
                        alert.runModal()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Error"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func dismiss() {
        guard let sheet = sheet, let parent = parentWindow else { return }
        parent.endSheet(sheet)
        self.sheet = nil
    }

    // MARK: - UI Builders

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func makeSectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        l.textColor = NSColor(white: 0.45, alpha: 1)
        l.frame = NSRect(x: 24, y: y, width: 200, height: 14)
        return l
    }

    private func makeTextField(placeholder: String, frame: NSRect) -> NSTextField {
        let f = NSTextField(frame: frame)
        f.placeholderString = placeholder
        f.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        f.textColor = AppTheme.textPrimary
        f.backgroundColor = NSColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1)
        f.isBezeled = true
        f.bezelStyle = .roundedBezel
        f.focusRingType = .none
        return f
    }

    private func makePopup(frame: NSRect) -> NSPopUpButton {
        let p = NSPopUpButton(frame: frame)
        p.font = NSFont.systemFont(ofSize: 12)
        return p
    }
}

extension NewWorkspaceSheet: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard currentMode == .newBranch else { return }
        let prompt = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if branchField.stringValue.isEmpty && !prompt.isEmpty {
            let suffix = String(format: "%04x", arc4random_uniform(65536))
            let slug = String(prompt.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                .prefix(36))
            branchField.placeholderString = "cterm/\(slug)-\(suffix)"
        }
    }
}
