import AppKit

protocol TerminalViewDelegate: AnyObject {
    func terminalDidUpdateTitle(_ title: String)
    func terminalDidExit(status: Int32)
}

class TerminalView: NSView {
    let emulator: TerminalEmulator
    let pty: PTYManager
    weak var delegate: TerminalViewDelegate?

    private var cellWidth: CGFloat = 8
    private var cellHeight: CGFloat = 16
    private var displayTimer: Timer?
    private var cursorBlinkTimer: Timer?
    private var cursorVisible: Bool = true

    var tokenTracker: TokenTrackerBridge?
    var sessionId: String = UUID().uuidString

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(frame: NSRect, shell: String = "/bin/zsh", workingDir: String? = nil) {
        let tempEmulator = TerminalEmulator(rows: 24, cols: 80)
        self.emulator = tempEmulator
        self.pty = PTYManager()
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = AppTheme.bgPrimary.cgColor
        calculateCellSize()

        emulator.onTitleChanged = { [weak self] title in
            self?.delegate?.terminalDidUpdateTitle(title)
        }

        pty.onDataReceived = { [weak self] data in
            self?.emulator.feed(data)
        }

        pty.onProcessExit = { [weak self] status in
            self?.delegate?.terminalDidExit(status: status)
        }

        emulator.onWriteBack = { [weak self] response in
            self?.pty.writeString(response)
        }

        // Spawn immediately with default 24x80, will resize once view gets real layout
        pty.spawn(command: shell, workingDir: workingDir, size: (24, 80))

        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            if s.emulator.needsDisplay {
                s.emulator.needsDisplay = false
                s.setNeedsDisplay(s.bounds)
            }
        }

        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            s.cursorVisible.toggle()
            let x = CGFloat(s.emulator.cursorCol) * s.cellWidth
            let y = CGFloat(s.emulator.cursorRow) * s.cellHeight
            s.setNeedsDisplay(NSRect(x: x, y: y, width: s.cellWidth, height: s.cellHeight))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayTimer?.invalidate()
        cursorBlinkTimer?.invalidate()
        pty.terminate()
    }

    private func calculateCellSize() {
        let font = AppTheme.terminalFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = ("M" as NSString).size(withAttributes: attrs)
        cellWidth = ceil(size.width)
        cellHeight = ceil(font.ascender - font.descender + font.leading) + 2
    }

    private func calculateGridSize() -> (rows: Int, cols: Int) {
        let cols = max(1, Int(bounds.width / cellWidth))
        let rows = max(1, Int(bounds.height / cellHeight))
        return (rows, cols)
    }

    private var hasResized = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width > 50 && newSize.height > 50 else { return }

        let gridSize = calculateGridSize()
        guard gridSize.rows >= 2 && gridSize.cols >= 10 else { return }
        guard gridSize.rows != emulator.rows || gridSize.cols != emulator.cols else { return }

        emulator.resize(newRows: gridSize.rows, newCols: gridSize.cols)
        pty.resize(rows: UInt16(gridSize.rows), cols: UInt16(gridSize.cols))
        hasResized = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw background
        context.setFillColor(AppTheme.bgPrimary.cgColor)
        context.fill(bounds)

        let font = AppTheme.terminalFont

        for row in 0..<emulator.rows {
            for col in 0..<emulator.cols {
                let cell = emulator.cells[row][col]
                let x = CGFloat(col) * cellWidth
                let y = CGFloat(row) * cellHeight

                let effectiveFg = cell.attributes.inverse ? cell.attributes.bg : cell.attributes.fg
                let effectiveBg = cell.attributes.inverse ? cell.attributes.fg : cell.attributes.bg

                // Draw cell background
                if effectiveBg != .clear {
                    context.setFillColor(effectiveBg.cgColor)
                    context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
                }

                // Draw cursor
                if row == emulator.cursorRow && col == emulator.cursorCol && emulator.showCursor {
                    if cursorVisible {
                        context.setFillColor(AppTheme.accent.withAlphaComponent(0.7).cgColor)
                        context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
                    }
                }

                // Draw character
                if cell.character != " " {
                    let drawFont = cell.attributes.bold ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold) : font
                    let fg = (row == emulator.cursorRow && col == emulator.cursorCol && cursorVisible) ?
                        AppTheme.bgPrimary : (effectiveFg == .clear ? AppTheme.textPrimary : effectiveFg)

                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: drawFont,
                        .foregroundColor: fg
                    ]
                    if cell.attributes.underline {
                        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    }
                    if cell.attributes.strikethrough {
                        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    }

                    let str = String(cell.character) as NSString
                    let baseline = y + font.ascender + 1
                    str.draw(at: NSPoint(x: x, y: baseline - font.ascender), withAttributes: attrs)
                }
            }
        }
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags

        // Handle Cmd+V (paste)
        if modifiers.contains(.command) && event.charactersIgnoringModifiers == "v" {
            let pb = NSPasteboard.general

            // Check for image first
            if let img = NSImage(pasteboard: pb) {
                if let path = saveImageToTemp(img) {
                    pty.writeString(path)
                }
                return
            }

            // Check for file URLs
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                let paths = urls.map { $0.path }.joined(separator: " ")
                pty.writeString(paths)
                return
            }

            // Plain text
            if let string = pb.string(forType: .string) {
                pty.writeString(string)
            }
            return
        }

        // Handle Cmd+C (copy if selection, otherwise pass through)
        if modifiers.contains(.command) && event.charactersIgnoringModifiers == "c" {
            // Pass to responder chain for menu handling
            super.keyDown(with: event)
            return
        }

        if let chars = event.characters {
            // Handle special keys
            switch event.keyCode {
            case 36: pty.writeString("\r") // Return
            case 51: pty.writeString("\u{7f}") // Backspace
            case 53: pty.writeString("\u{1b}") // Escape
            case 48: pty.writeString("\t") // Tab
            case 123: // Left arrow
                pty.writeString(emulator.applicationCursorKeys ? "\u{1b}OD" : "\u{1b}[D")
            case 124: // Right arrow
                pty.writeString(emulator.applicationCursorKeys ? "\u{1b}OC" : "\u{1b}[C")
            case 125: // Down arrow
                pty.writeString(emulator.applicationCursorKeys ? "\u{1b}OB" : "\u{1b}[B")
            case 126: // Up arrow
                pty.writeString(emulator.applicationCursorKeys ? "\u{1b}OA" : "\u{1b}[A")
            case 115: pty.writeString("\u{1b}[H") // Home
            case 119: pty.writeString("\u{1b}[F") // End
            case 116: pty.writeString("\u{1b}[5~") // Page Up
            case 121: pty.writeString("\u{1b}[6~") // Page Down
            case 117: pty.writeString("\u{1b}[3~") // Delete
            default:
                if modifiers.contains(.control) {
                    if let scalar = chars.unicodeScalars.first {
                        let value = scalar.value
                        if value >= 0x61 && value <= 0x7A { // a-z
                            let ctrl = Character(UnicodeScalar(value - 0x60)!)
                            pty.writeString(String(ctrl))
                        }
                    }
                } else {
                    pty.writeString(chars)
                }
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {}

    // MARK: - Image paste

    private func saveImageToTemp(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cterm-images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let filename = "paste-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let url = dir.appendingPathComponent(filename)

        do {
            try pngData.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }
}
