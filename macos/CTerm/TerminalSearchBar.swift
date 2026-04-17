import AppKit

protocol TerminalSearchBarDelegate: AnyObject {
    func searchBarDidUpdateQuery(_ query: String)
    func searchBarDidRequestNext()
    func searchBarDidRequestPrevious()
    func searchBarDidClose()
}

/// Thin search bar overlay for terminal in-search (Cmd+F).
/// Appears at the top of the terminal content area.
class TerminalSearchBar: NSView {
    weak var delegate: TerminalSearchBarDelegate?

    private var searchField: NSTextField!
    private var matchLabel: NSTextField!
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var closeButton: NSButton!

    private var totalMatches: Int = 0
    private var selectedMatch: Int = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = AppTheme.bgSecondary.cgColor
        layer?.borderColor = AppTheme.border.cgColor
        layer?.borderWidth = 1

        // Search field
        searchField = NSTextField()
        searchField.placeholderString = "Search..."
        searchField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        searchField.textColor = AppTheme.textPrimary
        searchField.backgroundColor = AppTheme.bgTertiary
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        // Match count label
        matchLabel = NSTextField(labelWithString: "")
        matchLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        matchLabel.textColor = AppTheme.textSecondary
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(matchLabel)

        // Previous button
        prevButton = makeButton(title: "\u{25B2}", action: #selector(previousClicked(_:)))
        addSubview(prevButton)

        // Next button
        nextButton = makeButton(title: "\u{25BC}", action: #selector(nextClicked(_:)))
        addSubview(nextButton)

        // Close button
        closeButton = makeButton(title: "\u{2715}", action: #selector(closeClicked(_:)))
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 220),
            searchField.heightAnchor.constraint(equalToConstant: 22),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            prevButton.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 6),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = NSFont.systemFont(ofSize: 11)
        btn.contentTintColor = AppTheme.textSecondary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    // MARK: - Public

    func activate() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateMatchInfo(total: Int, selected: Int) {
        totalMatches = total
        selectedMatch = selected
        if total < 0 {
            matchLabel.stringValue = ""
        } else if total == 0 {
            matchLabel.stringValue = "No matches"
        } else {
            matchLabel.stringValue = "\(selected + 1) of \(total)"
        }
    }

    // MARK: - Actions

    @objc private func searchFieldChanged(_ sender: NSTextField) {
        delegate?.searchBarDidUpdateQuery(sender.stringValue)
    }

    @objc private func previousClicked(_ sender: Any?) {
        delegate?.searchBarDidRequestPrevious()
    }

    @objc private func nextClicked(_ sender: Any?) {
        delegate?.searchBarDidRequestNext()
    }

    @objc private func closeClicked(_ sender: Any?) {
        delegate?.searchBarDidClose()
    }

    // Handle Escape key to close
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            delegate?.searchBarDidClose()
        } else {
            super.keyDown(with: event)
        }
    }

    // Allow Escape from search field
    override func cancelOperation(_ sender: Any?) {
        delegate?.searchBarDidClose()
    }
}
