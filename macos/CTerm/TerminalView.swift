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
    private var cursorVisible: Bool = true
    private var cursorBlinkCounter: Int = 0
    // Cursor cell last drawn — used to invalidate on cursor move.
    private var lastCursorRow: Int = 0
    private var lastCursorCol: Int = 0
    // Cached fonts (rebuilt in calculateCellSize).
    private var regularFont: NSFont = AppTheme.terminalFont
    private var boldFont: NSFont = AppTheme.terminalFont

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
            self?.tick()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayTimer?.invalidate()
        pty.terminate()
    }

    private func tick() {
        // Blink cursor every 18 ticks (≈0.6s at 30fps).
        cursorBlinkCounter += 1
        var blinkFlipped = false
        if cursorBlinkCounter >= 18 {
            cursorBlinkCounter = 0
            cursorVisible.toggle()
            blinkFlipped = true
        }

        var invalidRect: NSRect? = nil
        let mergeRect: (NSRect) -> Void = { rect in
            if let r = invalidRect { invalidRect = r.union(rect) } else { invalidRect = rect }
        }

        if let (top, bot) = emulator.consumeDirtyRange() {
            let y = CGFloat(top) * cellHeight
            let h = CGFloat(bot - top + 1) * cellHeight
            mergeRect(NSRect(x: 0, y: y, width: bounds.width, height: h))
            emulator.needsDisplay = false
        } else if emulator.needsDisplay {
            emulator.needsDisplay = false
            mergeRect(bounds)
        }

        // Cursor moved — invalidate old + new cells.
        if emulator.cursorRow != lastCursorRow || emulator.cursorCol != lastCursorCol {
            mergeRect(cellRect(row: lastCursorRow, col: lastCursorCol))
            mergeRect(cellRect(row: emulator.cursorRow, col: emulator.cursorCol))
            lastCursorRow = emulator.cursorRow
            lastCursorCol = emulator.cursorCol
        } else if blinkFlipped {
            mergeRect(cellRect(row: emulator.cursorRow, col: emulator.cursorCol))
        }

        if let rect = invalidRect {
            setNeedsDisplay(rect)
        }
    }

    private func cellRect(row: Int, col: Int) -> NSRect {
        NSRect(x: CGFloat(col) * cellWidth, y: CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
    }

    private func calculateCellSize() {
        let font = AppTheme.terminalFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = ("M" as NSString).size(withAttributes: attrs)
        cellWidth = ceil(size.width)
        cellHeight = ceil(font.ascender - font.descender + font.leading) + 2
        regularFont = font
        boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
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

        context.setFillColor(AppTheme.bgPrimary.cgColor)
        context.fill(dirtyRect)

        let rows = emulator.rows
        let cols = emulator.cols
        guard rows > 0 && cols > 0 else { return }

        let rowStart = max(0, Int(dirtyRect.minY / cellHeight))
        let rowEnd = min(rows, Int((dirtyRect.maxY / cellHeight).rounded(.up)))
        let colStart = max(0, Int(dirtyRect.minX / cellWidth))
        let colEnd = min(cols, Int((dirtyRect.maxX / cellWidth).rounded(.up)))
        guard rowStart < rowEnd && colStart < colEnd else { return }

        for row in rowStart..<rowEnd {
            let rowCells = emulator.cells[row]
            let y = CGFloat(row) * cellHeight

            // Pass 1: coalesced background fills.
            var bgCol = colStart
            while bgCol < colEnd {
                let cell = rowCells[bgCol]
                let bg = cell.attributes.inverse ? cell.attributes.fg : cell.attributes.bg
                if bg == .clear { bgCol += 1; continue }
                var end = bgCol + 1
                while end < colEnd {
                    let c = rowCells[end]
                    let bg2 = c.attributes.inverse ? c.attributes.fg : c.attributes.bg
                    if bg2 != bg { break }
                    end += 1
                }
                context.setFillColor(bg.cgColor)
                context.fill(CGRect(
                    x: CGFloat(bgCol) * cellWidth, y: y,
                    width: CGFloat(end - bgCol) * cellWidth, height: cellHeight))
                bgCol = end
            }

            // Pass 2: coalesced text runs (same attributes, no spaces).
            var col = colStart
            while col < colEnd {
                let cell = rowCells[col]
                if cell.character == " " { col += 1; continue }
                let attrs = cell.attributes
                var end = col + 1
                var runString = String(cell.character)
                while end < colEnd {
                    let c = rowCells[end]
                    if c.character == " " || c.attributes != attrs { break }
                    runString.append(c.character)
                    end += 1
                }
                drawTextRun(runString, at: NSPoint(x: CGFloat(col) * cellWidth, y: y + 1), attrs: attrs)
                col = end
            }
        }

        // Cursor overlay.
        if emulator.showCursor && cursorVisible {
            let cr = emulator.cursorRow
            let cc = emulator.cursorCol
            if cr >= rowStart && cr < rowEnd && cc >= colStart && cc < colEnd {
                let x = CGFloat(cc) * cellWidth
                let y = CGFloat(cr) * cellHeight
                context.setFillColor(AppTheme.accent.withAlphaComponent(0.7).cgColor)
                context.fill(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
                let cell = emulator.cells[cr][cc]
                if cell.character != " " {
                    let drawFont = cell.attributes.bold ? boldFont : regularFont
                    let str = String(cell.character) as NSString
                    str.draw(at: NSPoint(x: x, y: y + 1),
                             withAttributes: [.font: drawFont, .foregroundColor: AppTheme.bgPrimary])
                }
            }
        }
    }

    private func drawTextRun(_ text: String, at point: NSPoint, attrs: CellAttributes) {
        let drawFont = attrs.bold ? boldFont : regularFont
        let raw = attrs.inverse ? attrs.bg : attrs.fg
        let fg: NSColor = (raw == .clear) ? AppTheme.textPrimary : raw
        var drawAttrs: [NSAttributedString.Key: Any] = [.font: drawFont, .foregroundColor: fg]
        if attrs.underline {
            drawAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if attrs.strikethrough {
            drawAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        (text as NSString).draw(at: point, withAttributes: drawAttrs)
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
