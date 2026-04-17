import AppKit

struct PortEntry {
    let port: Int
    let process: String
    let label: String?
}

/// Displays configured ports from .cterm/ports.json.
/// Ports are only shown when explicitly configured per-project.
class PortManagerView: NSView {
    private var ports: [PortEntry] = []
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var headerLabel: NSTextField!
    private var topBorder: NSView!

    var workingDirectory: String? {
        didSet { refreshPorts() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = AppTheme.bgSecondary.cgColor

        topBorder = NSView()
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = AppTheme.border.cgColor
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        headerLabel = NSTextField(labelWithString: "PORTS")
        headerLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = AppTheme.textSecondary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerLabel)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let flipContainer = PortFlipView()
        flipContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = flipContainer

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        flipContainer.addSubview(stackView)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            headerLabel.topAnchor.constraint(equalTo: topBorder.bottomAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            flipContainer.topAnchor.constraint(equalTo: scrollView.topAnchor),
            flipContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            flipContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: flipContainer.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: flipContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: flipContainer.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: flipContainer.bottomAnchor),
        ])
    }

    @objc func refreshPorts() {
        let configured = loadConfiguredPorts()
        ports = configured.sorted { $0.port < $1.port }
        rebuildRows()
    }

    private func loadConfiguredPorts() -> [PortEntry] {
        guard let dir = workingDirectory else { return [] }
        let configPath = (dir as NSString).appendingPathComponent(".cterm/ports.json")
        guard FileManager.default.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return [] }

        struct PortConfig: Codable {
            let port: Int
            let label: String?
        }

        guard let configs = try? JSONDecoder().decode([PortConfig].self, from: data) else { return [] }
        return configs.map { PortEntry(port: $0.port, process: "", label: $0.label) }
    }

    private func rebuildRows() {
        for v in stackView.arrangedSubviews { stackView.removeArrangedSubview(v); v.removeFromSuperview() }

        if ports.isEmpty {
            // Show nothing — panel will be minimal height
            headerLabel.stringValue = "PORTS"
            isHidden = true
            return
        }

        isHidden = false
        headerLabel.stringValue = "PORTS (\(ports.count))"

        for entry in ports {
            let row = makePortRow(entry)
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    private func makePortRow(_ entry: PortEntry) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let portLabel = NSTextField(labelWithString: ":\(entry.port)")
        portLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        portLabel.textColor = AppTheme.accent
        portLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(portLabel)

        let desc = entry.label ?? entry.process
        if !desc.isEmpty {
            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 11)
            descLabel.textColor = AppTheme.textSecondary
            descLabel.lineBreakMode = .byTruncatingTail
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(descLabel)
            descLabel.leadingAnchor.constraint(equalTo: portLabel.trailingAnchor, constant: 6).isActive = true
            descLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor).isActive = true
        }

        let openBtn = NSButton(image: NSImage(systemSymbolName: "globe", accessibilityDescription: "Open")!, target: self, action: #selector(openPort(_:)))
        openBtn.bezelStyle = .inline
        openBtn.isBordered = false
        openBtn.contentTintColor = AppTheme.textSecondary
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        openBtn.tag = entry.port
        row.addSubview(openBtn)

        NSLayoutConstraint.activate([
            portLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            portLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            openBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openBtn.widthAnchor.constraint(equalToConstant: 18),
        ])

        return row
    }

    @objc private func openPort(_ sender: NSButton) {
        if let url = URL(string: "http://localhost:\(sender.tag)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private class PortFlipView: NSView {
    override var isFlipped: Bool { true }
}
