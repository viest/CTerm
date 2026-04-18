import AppKit

protocol PresetBarDelegate: AnyObject {
    func presetSelected(_ preset: AgentPresetItem)
    func presetRunInCurrent(_ preset: AgentPresetItem)
    func presetOpenInSplit(_ preset: AgentPresetItem)
    func newTerminalRequested()
    func presetBarOpenInEditorRequested()
    func presetBarOpenInEditorPickerRequested(from sourceView: NSView)
}

class PresetBarView: NSView {
    private static let leadingInsetWithTrafficLights: CGFloat = 80
    private static let leadingInsetWithoutTrafficLights: CGFloat = 14

    weak var delegate: PresetBarDelegate?
    private var presets: [AgentPresetItem] = []
    private var buttons: [NSView] = []
    private var contentView: NSView!
    private(set) var sidebarToggle: NSButton!
    private(set) var settingsButton: NSButton!
    private(set) var rightSidebarToggle: NSButton!
    private(set) var openInEditorButton: OpenInEditorSplitButton!
    private var sidebarLeadingConstraint: NSLayoutConstraint!

    private let barHeight: CGFloat = 34

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1).cgColor

        // Bottom border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = AppTheme.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        sidebarToggle = NSButton()
        sidebarToggle.bezelStyle = .inline
        sidebarToggle.isBordered = false
        sidebarToggle.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: nil)
        sidebarToggle.contentTintColor = AppTheme.textSecondary
        sidebarToggle.imageScaling = .scaleProportionallyDown
        sidebarToggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebarToggle)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        settingsButton = NSButton()
        settingsButton.bezelStyle = .inline
        settingsButton.isBordered = false
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.contentTintColor = AppTheme.textSecondary
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsButton)

        // Open-in-editor split button (sits to the left of the right-sidebar toggle)
        openInEditorButton = OpenInEditorSplitButton()
        openInEditorButton.translatesAutoresizingMaskIntoConstraints = false
        openInEditorButton.onOpen = { [weak self] in
            self?.delegate?.presetBarOpenInEditorRequested()
        }
        openInEditorButton.onChevron = { [weak self] in
            guard let self else { return }
            self.delegate?.presetBarOpenInEditorPickerRequested(from: self.openInEditorButton)
        }
        addSubview(openInEditorButton)

        // Divider between the Open button and the right-sidebar toggle.
        let divider3 = NSView()
        divider3.wantsLayer = true
        divider3.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        divider3.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider3)

        // Right sidebar toggle button
        rightSidebarToggle = NSButton()
        rightSidebarToggle.bezelStyle = .inline
        rightSidebarToggle.isBordered = false
        rightSidebarToggle.image = NSImage(systemSymbolName: "sidebar.trailing", accessibilityDescription: nil)
        rightSidebarToggle.contentTintColor = AppTheme.textSecondary
        rightSidebarToggle.imageScaling = .scaleProportionallyDown
        rightSidebarToggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightSidebarToggle)

        let divider2 = NSView()
        divider2.wantsLayer = true
        divider2.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        divider2.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider2)

        contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: barHeight),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            sidebarToggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            sidebarToggle.widthAnchor.constraint(equalToConstant: 20),
            sidebarToggle.heightAnchor.constraint(equalToConstant: 20),

            divider.leadingAnchor.constraint(equalTo: sidebarToggle.trailingAnchor, constant: 8),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16),

            settingsButton.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 8),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 20),
            settingsButton.heightAnchor.constraint(equalToConstant: 20),

            divider2.leadingAnchor.constraint(equalTo: settingsButton.trailingAnchor, constant: 8),
            divider2.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider2.widthAnchor.constraint(equalToConstant: 1),
            divider2.heightAnchor.constraint(equalToConstant: 16),

            contentView.leadingAnchor.constraint(equalTo: divider2.trailingAnchor, constant: 8),
            contentView.trailingAnchor.constraint(equalTo: openInEditorButton.leadingAnchor, constant: -10),

            openInEditorButton.trailingAnchor.constraint(equalTo: divider3.leadingAnchor, constant: -8),
            openInEditorButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            divider3.trailingAnchor.constraint(equalTo: rightSidebarToggle.leadingAnchor, constant: -8),
            divider3.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider3.widthAnchor.constraint(equalToConstant: 1),
            divider3.heightAnchor.constraint(equalToConstant: 16),

            rightSidebarToggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightSidebarToggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightSidebarToggle.widthAnchor.constraint(equalToConstant: 20),
            rightSidebarToggle.heightAnchor.constraint(equalToConstant: 20),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        sidebarLeadingConstraint = sidebarToggle.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Self.leadingInsetWithTrafficLights
        )
        sidebarLeadingConstraint.isActive = true
    }

    func setPresets(_ presets: [AgentPresetItem]) {
        self.presets = presets
        rebuildButtons()
    }

    func setShowsTrafficLightSpacing(_ showsTrafficLights: Bool) {
        sidebarLeadingConstraint.constant = showsTrafficLights
            ? Self.leadingInsetWithTrafficLights
            : Self.leadingInsetWithoutTrafficLights
    }

    func setOpenInEditor(_ editorId: String) {
        openInEditorButton.setEditor(editorId)
    }

    private func rebuildButtons() {
        for btn in buttons { btn.removeFromSuperview() }
        buttons = []

        var x: CGFloat = 0
        let btnHeight: CGFloat = 22
        let y: CGFloat = (barHeight - btnHeight) / 2

        // Terminal button
        let termBtn = TerminalPillButton()
        termBtn.target = self
        termBtn.action = #selector(terminalClicked(_:))
        let termWidth = termBtn.intrinsicContentSize.width
        termBtn.frame = NSRect(x: x, y: y, width: termWidth, height: btnHeight)
        contentView.addSubview(termBtn)
        buttons.append(termBtn)
        x += termWidth + 10

        for (index, preset) in presets.enumerated() {
            let pill = AgentPillButton(preset: preset, index: index)
            pill.target = self
            pill.action = #selector(presetClicked(_:))
            let pillWidth = pill.intrinsicContentSize.width
            pill.frame = NSRect(x: x, y: y, width: pillWidth, height: btnHeight)
            contentView.addSubview(pill)
            buttons.append(pill)
            x += pillWidth + 10
        }
    }

    @objc private func terminalClicked(_ sender: Any?) {
        delegate?.newTerminalRequested()
    }

    @objc private func presetClicked(_ sender: AgentPillButton) {
        guard sender.index >= 0 && sender.index < presets.count else { return }
        delegate?.presetSelected(presets[sender.index])
    }

    /// Right-click pops up a native NSMenu anchored to the bottom-left of
    /// the pill so the menu reads as a standard macOS context menu — the
    /// popover we used before was centered on the pill, which put the
    /// menu's left edge floating a few dozen points to the left of the
    /// button it belonged to.
    fileprivate func presetRightClicked(_ sender: AgentPillButton) {
        guard sender.index >= 0 && sender.index < presets.count else { return }
        let preset = presets[sender.index]

        let menu = NSMenu()
        menu.font = NSFont.systemFont(ofSize: 12)
        menu.autoenablesItems = false

        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(
            string: preset.name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        func add(_ title: String, _ symbol: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            menu.addItem(item)
        }
        add("Run in Current Terminal", "terminal",                #selector(onMenuRunInCurrent(_:)))
        add("Open in New Tab",        "square.on.square",         #selector(onMenuOpenInNewTab(_:)))
        add("Open in Split Pane",     "rectangle.split.2x1",      #selector(onMenuOpenInSplit(_:)))

        // Non-flipped NSView coords: (0, 0) is the view's bottom-left, so
        // that's where we want the menu's top-left corner to appear.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }

    @objc private func onMenuRunInCurrent(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? AgentPresetItem else { return }
        delegate?.presetRunInCurrent(preset)
    }

    @objc private func onMenuOpenInNewTab(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? AgentPresetItem else { return }
        delegate?.presetSelected(preset)
    }

    @objc private func onMenuOpenInSplit(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? AgentPresetItem else { return }
        delegate?.presetOpenInSplit(preset)
    }
}

// MARK: - Agent pill button

class AgentPillButton: NSControl {
    let preset: AgentPresetItem
    let index: Int
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    let providerColor: NSColor
    let labelText: String

    private let iconSize: CGFloat = 12
    private let hPad: CGFloat = 6
    private let iconTextGap: CGFloat = 4

    init(preset: AgentPresetItem, index: Int) {
        self.preset = preset
        self.index = index
        self.labelText = preset.name
        self.providerColor = Self.colorForProvider(preset.provider)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textW = (labelText as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(hPad + iconSize + iconTextGap + textW + hPad), height: 22)
    }

    // MARK: - Mouse handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateAppearance() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; updateAppearance() }
    override func mouseDown(with event: NSEvent)     { layer?.opacity = 0.75 }
    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Find parent PresetBarView and call right-click handler
        var responder: NSView? = superview
        while let r = responder {
            if let bar = r as? PresetBarView {
                bar.presetRightClicked(self)
                return
            }
            responder = r.superview
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? providerColor.withAlphaComponent(0.15).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = 0
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconX = hPad
        let iconY = (bounds.height - iconSize) / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

        // Icon rounded-rect background
        let iconBg = NSBezierPath(roundedRect: iconRect, xRadius: 3, yRadius: 3)
        providerColor.withAlphaComponent(isHovered ? 1.0 : 0.85).setFill()
        iconBg.fill()

        // White vector logo inside (scale from original 16px design)
        NSGraphicsContext.saveGraphicsState()
        let scale = iconSize / 16.0
        let xform = NSAffineTransform()
        xform.translateX(by: iconRect.midX, yBy: iconRect.midY)
        xform.scale(by: scale)
        xform.translateX(by: -iconRect.midX, yBy: -iconRect.midY)
        xform.concat()
        NSColor.white.setFill()
        NSColor.white.setStroke()
        drawProviderLogo(in: iconRect, provider: preset.provider)
        NSGraphicsContext.restoreGraphicsState()

        // Text label
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textColor = isHovered ? NSColor.white : AppTheme.textPrimary
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str = labelText as NSString
        let strSize = str.size(withAttributes: attrs)
        let textX = iconX + iconSize + iconTextGap
        let textY = (bounds.height - strSize.height) / 2
        str.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }

    // MARK: - Vector provider logos

    private func drawProviderLogo(in rect: NSRect, provider: String) {
        let cx = rect.midX, cy = rect.midY
        switch provider {
        case "anthropic": drawAnthropic(cx: cx, cy: cy)
        case "openai":    drawOpenAI(cx: cx, cy: cy)
        case "google":    drawGemini(cx: cx, cy: cy)
        case "multiple":  drawAider(cx: cx, cy: cy)
        case "github":    drawCopilot(cx: cx, cy: cy)
        default:          drawTerminal(cx: cx, cy: cy)
        }
    }

    /// Anthropic — sunburst / starburst
    private func drawAnthropic(cx: CGFloat, cy: CGFloat) {
        let path = NSBezierPath()
        let rays = 8
        let outerR: CGFloat = 5.5
        let innerR: CGFloat = 2.2
        for i in 0..<(rays * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(rays) - .pi / 2
            let r: CGFloat = (i % 2 == 0) ? outerR : innerR
            let px = cx + cos(angle) * r
            let py = cy + sin(angle) * r
            if i == 0 { path.move(to: NSPoint(x: px, y: py)) }
            else      { path.line(to: NSPoint(x: px, y: py)) }
        }
        path.close()
        path.fill()
    }

    /// OpenAI — hexagonal outline with center dot
    private func drawOpenAI(cx: CGFloat, cy: CGFloat) {
        let path = NSBezierPath()
        let r: CGFloat = 5.5
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3.0 - .pi / 6.0
            let pt = NSPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        path.lineWidth = 1.5
        path.stroke()

        NSBezierPath(ovalIn: NSRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3)).fill()
    }

    /// Gemini — four-pointed sparkle
    private func drawGemini(cx: CGFloat, cy: CGFloat) {
        let path = NSBezierPath()
        let outer: CGFloat = 5.5
        let inner: CGFloat = 2.0
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4.0 - .pi / 2
            let r: CGFloat = (i % 2 == 0) ? outer : inner
            let pt = NSPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
        }
        path.close()
        path.fill()
    }

    /// Aider — angle brackets  < >
    private func drawAider(cx: CGFloat, cy: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: cx - 1.5, y: cy - 4))
        path.line(to: NSPoint(x: cx - 5, y: cy))
        path.line(to: NSPoint(x: cx - 1.5, y: cy + 4))
        path.move(to: NSPoint(x: cx + 1.5, y: cy - 4))
        path.line(to: NSPoint(x: cx + 5, y: cy))
        path.line(to: NSPoint(x: cx + 1.5, y: cy + 4))
        path.stroke()
    }

    /// Copilot — pilot goggles / dual lens
    private func drawCopilot(cx: CGFloat, cy: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: cx - 5.5, y: cy - 2.5, width: 5, height: 5)).fill()
        NSBezierPath(ovalIn: NSRect(x: cx + 0.5, y: cy - 2.5, width: 5, height: 5)).fill()
        let bridge = NSBezierPath()
        bridge.lineWidth = 1.5
        bridge.lineCapStyle = .round
        bridge.move(to: NSPoint(x: cx - 0.5, y: cy + 0.5))
        bridge.line(to: NSPoint(x: cx + 0.5, y: cy + 0.5))
        bridge.stroke()
    }

    /// Fallback — terminal prompt  >_
    private func drawTerminal(cx: CGFloat, cy: CGFloat) {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: cx - 3.5, y: cy - 3.5))
        path.line(to: NSPoint(x: cx + 0.5, y: cy))
        path.line(to: NSPoint(x: cx - 3.5, y: cy + 3.5))
        path.stroke()
        let ul = NSBezierPath()
        ul.lineWidth = 1.6
        ul.lineCapStyle = .round
        ul.move(to: NSPoint(x: cx + 1.5, y: cy + 3.5))
        ul.line(to: NSPoint(x: cx + 5, y: cy + 3.5))
        ul.stroke()
    }

    // MARK: - Provider colors

    static func colorForProvider(_ provider: String) -> NSColor {
        switch provider {
        case "anthropic":  return NSColor(red: 0.91, green: 0.52, blue: 0.24, alpha: 1)
        case "openai":     return NSColor(red: 0.20, green: 0.80, blue: 0.50, alpha: 1)
        case "google":     return NSColor(red: 0.30, green: 0.52, blue: 1.00, alpha: 1)
        case "github":     return NSColor(red: 0.58, green: 0.58, blue: 0.68, alpha: 1)
        case "multiple":   return NSColor(red: 0.65, green: 0.42, blue: 0.90, alpha: 1)
        default:           return AppTheme.accent
        }
    }
}

// MARK: - Terminal pill button

class TerminalPillButton: NSControl {
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private let iconSize: CGFloat = 12
    private let hPad: CGFloat = 6
    private let iconTextGap: CGFloat = 4
    private let tintColor = NSColor(white: 0.75, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textW = ("Terminal" as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(hPad + iconSize + iconTextGap + textW + hPad), height: 22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; updateAppearance() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; updateAppearance() }
    override func mouseDown(with event: NSEvent)     { layer?.opacity = 0.75 }
    override func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = isHovered ? NSColor(white: 0.3, alpha: 0.3).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconX = hPad
        let iconY = (bounds.height - iconSize) / 2
        let iconRect = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

        // Icon background
        let iconBg = NSBezierPath(roundedRect: iconRect, xRadius: 3, yRadius: 3)
        tintColor.withAlphaComponent(isHovered ? 1.0 : 0.85).setFill()
        iconBg.fill()

        // Terminal prompt icon >_
        NSGraphicsContext.saveGraphicsState()
        let scale = iconSize / 16.0
        let cx = iconRect.midX, cy = iconRect.midY
        let xform = NSAffineTransform()
        xform.translateX(by: cx, yBy: cy)
        xform.scale(by: scale)
        xform.translateX(by: -cx, yBy: -cy)
        xform.concat()
        NSColor.white.setStroke()
        let chevron = NSBezierPath()
        chevron.lineWidth = 1.6
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.move(to: NSPoint(x: cx - 3.5, y: cy - 3.5))
        chevron.line(to: NSPoint(x: cx + 0.5, y: cy))
        chevron.line(to: NSPoint(x: cx - 3.5, y: cy + 3.5))
        chevron.stroke()
        let underline = NSBezierPath()
        underline.lineWidth = 1.6
        underline.lineCapStyle = .round
        underline.move(to: NSPoint(x: cx + 1.5, y: cy + 3.5))
        underline.line(to: NSPoint(x: cx + 5, y: cy + 3.5))
        underline.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Text
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textColor = isHovered ? NSColor.white : AppTheme.textPrimary
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let str = "Terminal" as NSString
        let strSize = str.size(withAttributes: attrs)
        let textX = iconX + iconSize + iconTextGap
        let textY = (bounds.height - strSize.height) / 2
        str.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }
}

// MARK: - Open-in-editor split button

/// Split-pill button: IDE name on the left, chevron on the right.
/// Static styling — no hover or press effects.
class OpenInEditorSplitButton: NSView {
    var onOpen: (() -> Void)?
    var onChevron: (() -> Void)?

    private var editorId: String = "code"
    private var pressedOnLeft = false
    private var pressedOnRight = false

    private let totalHeight: CGFloat = 22
    private let hPad: CGFloat = 8
    private let chevronWidth: CGFloat = 18

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setEditor(_ id: String) {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = normalized.isEmpty ? "code" : normalized
        guard editorId != resolved else { return }
        editorId = resolved
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var currentLabel: String {
        EditorLauncher.displayName(for: editorId)
    }

    override var intrinsicContentSize: NSSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textW = (currentLabel as NSString).size(withAttributes: [.font: font]).width
        let leftW = hPad + textW + hPad
        return NSSize(width: ceil(leftW + chevronWidth), height: totalHeight)
    }

    private var splitX: CGFloat { bounds.width - chevronWidth }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressedOnLeft = p.x < splitX
        pressedOnRight = !pressedOnLeft
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let wasLeft = pressedOnLeft
        let wasRight = pressedOnRight
        pressedOnLeft = false
        pressedOnRight = false
        guard bounds.contains(p) else { return }
        let upOnLeft = p.x < splitX
        if wasLeft && upOnLeft { onOpen?() }
        else if wasRight && !upOnLeft { onChevron?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // IDE-name label
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: AppTheme.textPrimary,
        ]
        let label = currentLabel as NSString
        let labelSize = label.size(withAttributes: labelAttrs)
        label.draw(
            at: NSPoint(
                x: hPad,
                y: (bounds.height - labelSize.height) / 2
            ),
            withAttributes: labelAttrs
        )

        // Chevron
        let cy = bounds.midY
        let cx = splitX + chevronWidth / 2
        let chev = NSBezierPath()
        chev.lineWidth = 1.2
        chev.lineCapStyle = .round
        chev.lineJoinStyle = .round
        chev.move(to: NSPoint(x: cx - 3, y: cy + 1.8))
        chev.line(to: NSPoint(x: cx,     y: cy - 1.8))
        chev.line(to: NSPoint(x: cx + 3, y: cy + 1.8))
        AppTheme.textSecondary.setStroke()
        chev.stroke()
    }
}
