import AppKit

struct CellAttributes: Equatable {
    var fg: NSColor = AppTheme.textPrimary
    var bg: NSColor = .clear
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var strikethrough: Bool = false
    var inverse: Bool = false
}

struct Cell: Equatable {
    var character: Character = " "
    var attributes: CellAttributes = CellAttributes()
    var dirty: Bool = true
}

class TerminalEmulator {
    private(set) var rows: Int
    private(set) var cols: Int
    var cells: [[Cell]]
    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var currentAttributes: CellAttributes = CellAttributes()
    var scrollbackBuffer: [[Cell]] = []
    let maxScrollback: Int = 10000

    var savedCursorRow: Int = 0
    var savedCursorCol: Int = 0
    var savedAttributes: CellAttributes = CellAttributes()

    var showCursor: Bool = true
    var applicationCursorKeys: Bool = false
    var autoWrapMode: Bool = true
    var bracketedPasteMode: Bool = false
    var alternateScreen: Bool = false
    var primaryCells: [[Cell]]?
    var needsDisplay: Bool = false
    var title: String = "CTerm"
    var onTitleChanged: ((String) -> Void)?
    var onWriteBack: ((String) -> Void)? // For DSR responses

    // Scroll region (top/bottom, 0-indexed)
    var scrollTop: Int = 0
    var scrollBottom: Int = 0 // 0 means "rows - 1"

    private var effectiveScrollBottom: Int { scrollBottom == 0 ? rows - 1 : scrollBottom }

    // Parser state
    private enum ParserState {
        case ground
        case escape
        case csiEntry
        case csiParam
        case oscString
        case oscParam
        case charset
    }

    private var state: ParserState = .ground
    private var csiParams: [Int] = []
    private var csiCurrentParam: String = ""
    private var csiIntermediate: String = ""
    private var oscString: String = ""
    private var oscParam: Int = 0

    // UTF-8 decoder
    private var utf8Buffer: [UInt8] = []
    private var utf8Remaining: Int = 0

    // 256-color palette
    private static let ansi256Colors: [NSColor] = {
        var colors: [NSColor] = []
        // Standard colors (0-7)
        colors.append(NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1))     // Black
        colors.append(NSColor(red: 0.8, green: 0.23, blue: 0.23, alpha: 1))   // Red
        colors.append(NSColor(red: 0.33, green: 0.73, blue: 0.36, alpha: 1))  // Green
        colors.append(NSColor(red: 0.83, green: 0.73, blue: 0.33, alpha: 1))  // Yellow
        colors.append(NSColor(red: 0.36, green: 0.51, blue: 0.90, alpha: 1))  // Blue
        colors.append(NSColor(red: 0.73, green: 0.40, blue: 0.80, alpha: 1))  // Magenta
        colors.append(NSColor(red: 0.33, green: 0.73, blue: 0.73, alpha: 1))  // Cyan
        colors.append(NSColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1))  // White
        // Bright colors (8-15)
        colors.append(NSColor(red: 0.45, green: 0.45, blue: 0.50, alpha: 1))  // Bright Black
        colors.append(NSColor(red: 1.0, green: 0.33, blue: 0.33, alpha: 1))   // Bright Red
        colors.append(NSColor(red: 0.43, green: 0.90, blue: 0.43, alpha: 1))  // Bright Green
        colors.append(NSColor(red: 1.0, green: 0.90, blue: 0.43, alpha: 1))   // Bright Yellow
        colors.append(NSColor(red: 0.53, green: 0.67, blue: 1.0, alpha: 1))   // Bright Blue
        colors.append(NSColor(red: 0.87, green: 0.53, blue: 0.93, alpha: 1))  // Bright Magenta
        colors.append(NSColor(red: 0.53, green: 0.90, blue: 0.90, alpha: 1))  // Bright Cyan
        colors.append(NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))  // Bright White
        // 216 colors (16-231)
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    let rf = r == 0 ? 0.0 : (CGFloat(r) * 40.0 + 55.0) / 255.0
                    let gf = g == 0 ? 0.0 : (CGFloat(g) * 40.0 + 55.0) / 255.0
                    let bf = b == 0 ? 0.0 : (CGFloat(b) * 40.0 + 55.0) / 255.0
                    colors.append(NSColor(red: rf, green: gf, blue: bf, alpha: 1))
                }
            }
        }
        // Grayscale (232-255)
        for i in 0..<24 {
            let level = (CGFloat(i) * 10.0 + 8.0) / 255.0
            colors.append(NSColor(red: level, green: level, blue: level, alpha: 1))
        }
        return colors
    }()

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.cells = Self.makeEmptyGrid(rows: rows, cols: cols)
    }

    private static func makeEmptyGrid(rows: Int, cols: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell(), count: cols), count: rows)
    }

    func resize(newRows: Int, newCols: Int) {
        guard newRows > 0 && newCols > 0 else { return }

        var newCells = Self.makeEmptyGrid(rows: newRows, cols: newCols)
        let copyRows = min(rows, newRows)
        let copyCols = min(cols, newCols)

        for r in 0..<copyRows {
            for c in 0..<copyCols {
                newCells[r][c] = cells[r][c]
            }
        }

        cells = newCells
        rows = newRows
        cols = newCols
        cursorRow = min(cursorRow, newRows - 1)
        cursorCol = min(cursorCol, newCols - 1)
        scrollTop = 0
        scrollBottom = 0
        needsDisplay = true
    }

    func feed(_ data: Data) {
        for byte in data {
            processByte(byte)
        }
        needsDisplay = true
    }

    private func processByte(_ byte: UInt8) {
        // UTF-8 continuation bytes always go to ground handler
        if utf8Remaining > 0 {
            processGround(byte)
            return
        }

        switch state {
        case .ground:
            processGround(byte)
        case .escape:
            processEscape(byte)
        case .csiEntry, .csiParam:
            processCSI(byte)
        case .oscString, .oscParam:
            processOSC(byte)
        case .charset:
            state = .ground
        }
    }

    private func processGround(_ byte: UInt8) {
        // If we're accumulating a UTF-8 sequence, continue
        if utf8Remaining > 0 {
            if byte & 0xC0 == 0x80 { // valid continuation byte
                utf8Buffer.append(byte)
                utf8Remaining -= 1
                if utf8Remaining == 0 {
                    flushUtf8()
                }
            } else {
                // Invalid continuation — discard buffer, reprocess this byte
                utf8Buffer.removeAll()
                utf8Remaining = 0
                processGround(byte)
            }
            return
        }

        switch byte {
        case 0x00...0x06, 0x0E...0x1A, 0x1C: break
        case 0x07: break // BEL
        case 0x08: // BS
            if cursorCol > 0 { cursorCol -= 1 }
        case 0x09: // TAB
            cursorCol = min(((cursorCol / 8) + 1) * 8, cols - 1)
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            lineFeed()
        case 0x0D: // CR
            cursorCol = 0
        case 0x1B: // ESC
            state = .escape
            csiParams = []
            csiCurrentParam = ""
            csiIntermediate = ""
        case 0x20...0x7E: // Printable ASCII
            putChar(Character(UnicodeScalar(byte)))
        case 0x7F: break // DEL
        case 0xC0...0xDF: // 2-byte UTF-8
            utf8Buffer = [byte]
            utf8Remaining = 1
        case 0xE0...0xEF: // 3-byte UTF-8
            utf8Buffer = [byte]
            utf8Remaining = 2
        case 0xF0...0xF7: // 4-byte UTF-8
            utf8Buffer = [byte]
            utf8Remaining = 3
        default:
            break // Invalid lead byte, ignore
        }
    }

    private func flushUtf8() {
        if let str = String(bytes: utf8Buffer, encoding: .utf8), let char = str.first {
            putChar(char)
        }
        utf8Buffer.removeAll()
    }

    private func processEscape(_ byte: UInt8) {
        switch byte {
        case 0x5B: // [  -> CSI
            state = .csiEntry
            csiParams = []
            csiCurrentParam = ""
            csiIntermediate = ""
        case 0x5D: // ] -> OSC
            state = .oscParam
            oscString = ""
            oscParam = 0
        case 0x28, 0x29: // ( ) -> charset
            state = .charset
        case 0x37: // 7 -> save cursor (DECSC)
            savedCursorRow = cursorRow
            savedCursorCol = cursorCol
            savedAttributes = currentAttributes
            state = .ground
        case 0x38: // 8 -> restore cursor (DECRC)
            cursorRow = savedCursorRow
            cursorCol = savedCursorCol
            currentAttributes = savedAttributes
            state = .ground
        case 0x4D: // M -> reverse index
            if cursorRow == 0 {
                scrollDown()
            } else {
                cursorRow -= 1
            }
            state = .ground
        case 0x63: // c -> reset
            resetTerminal()
            state = .ground
        default:
            state = .ground
        }
    }

    private func processCSI(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39: // 0-9
            csiCurrentParam.append(Character(UnicodeScalar(byte)))
            state = .csiParam
        case 0x3B: // ;
            csiParams.append(Int(csiCurrentParam) ?? 0)
            csiCurrentParam = ""
            state = .csiParam
        case 0x3F, 0x3E, 0x21: // ? > !
            csiIntermediate.append(Character(UnicodeScalar(byte)))
            state = .csiParam
        case 0x20: // SP
            csiIntermediate.append(" ")
        case 0x40...0x7E: // Final byte
            if !csiCurrentParam.isEmpty {
                csiParams.append(Int(csiCurrentParam) ?? 0)
            }
            executeCSI(byte)
            state = .ground
        default:
            state = .ground
        }
    }

    private func processOSC(_ byte: UInt8) {
        if state == .oscParam {
            if byte == 0x3B { // ;
                oscParam = Int(oscString) ?? 0
                oscString = ""
                state = .oscString
                return
            } else if byte >= 0x30 && byte <= 0x39 {
                oscString.append(Character(UnicodeScalar(byte)))
                return
            }
        }

        switch byte {
        case 0x07: // BEL - terminates OSC
            executeOSC()
            state = .ground
        case 0x1B: // ESC (might be followed by \)
            executeOSC()
            state = .ground
        case 0x9C: // ST
            executeOSC()
            state = .ground
        default:
            if state == .oscString {
                oscString.append(Character(UnicodeScalar(byte)))
            }
        }
    }

    private func executeCSI(_ final: UInt8) {
        let p = csiParams
        let n = p.first ?? 1
        let m = p.count > 1 ? p[1] : 1

        if csiIntermediate.contains("?") {
            executeDECPrivate(final, params: p)
            return
        }

        switch final {
        case 0x41: // A - Cursor Up
            cursorRow = max(0, cursorRow - max(n, 1))
        case 0x42: // B - Cursor Down
            cursorRow = min(rows - 1, cursorRow + max(n, 1))
        case 0x43: // C - Cursor Forward
            cursorCol = min(cols - 1, cursorCol + max(n, 1))
        case 0x44: // D - Cursor Back
            cursorCol = max(0, cursorCol - max(n, 1))
        case 0x45: // E - Cursor Next Line
            cursorRow = min(rows - 1, cursorRow + max(n, 1))
            cursorCol = 0
        case 0x46: // F - Cursor Previous Line
            cursorRow = max(0, cursorRow - max(n, 1))
            cursorCol = 0
        case 0x47: // G - Cursor Horizontal Absolute
            cursorCol = min(cols - 1, max(0, n - 1))
        case 0x48: // H - Cursor Position
            let row = p.isEmpty ? 1 : n
            let col = p.count > 1 ? m : 1
            cursorRow = min(rows - 1, max(0, row - 1))
            cursorCol = min(cols - 1, max(0, col - 1))
        case 0x4A: // J - Erase in Display
            eraseInDisplay(mode: n)
        case 0x4B: // K - Erase in Line
            eraseInLine(mode: n)
        case 0x4C: // L - Insert Lines
            insertLines(count: max(n, 1))
        case 0x4D: // M - Delete Lines
            deleteLines(count: max(n, 1))
        case 0x50: // P - Delete Characters
            deleteChars(count: max(n, 1))
        case 0x53: // S - Scroll Up
            for _ in 0..<max(n, 1) { scrollUp() }
        case 0x54: // T - Scroll Down
            for _ in 0..<max(n, 1) { scrollDown() }
        case 0x58: // X - Erase Characters
            let count = min(max(n, 1), cols - cursorCol)
            for i in 0..<count {
                cells[cursorRow][cursorCol + i] = Cell()
            }
        case 0x60: // ` - HPA
            cursorCol = min(cols - 1, max(0, n - 1))
        case 0x64: // d - VPA
            cursorRow = min(rows - 1, max(0, n - 1))
        case 0x66: // f - HVP (same as CUP)
            let row = p.isEmpty ? 1 : n
            let col = p.count > 1 ? m : 1
            cursorRow = min(rows - 1, max(0, row - 1))
            cursorCol = min(cols - 1, max(0, col - 1))
        case 0x6D: // m - SGR
            executeSGR(params: p.isEmpty ? [0] : p)
        case 0x6E: // n - DSR (Device Status Report)
            if n == 6 { // CPR - Cursor Position Report
                onWriteBack?("\u{1b}[\(cursorRow + 1);\(cursorCol + 1)R")
            } else if n == 5 { // Status report
                onWriteBack?("\u{1b}[0n")
            }
        case 0x72: // r - DECSTBM (Set Scrolling Region)
            let top = (p.isEmpty ? 1 : max(n, 1)) - 1
            let bot = (p.count > 1 ? m : rows) - 1
            scrollTop = max(0, min(top, rows - 1))
            scrollBottom = max(scrollTop, min(bot, rows - 1))
            cursorRow = 0
            cursorCol = 0
        case 0x73: // s - Save cursor
            savedCursorRow = cursorRow
            savedCursorCol = cursorCol
        case 0x75: // u - Restore cursor
            cursorRow = savedCursorRow
            cursorCol = savedCursorCol
        case 0x40: // @ - Insert Characters
            let count = max(n, 1)
            for _ in 0..<count {
                if cursorCol < cols {
                    cells[cursorRow].insert(Cell(), at: cursorCol)
                    cells[cursorRow].removeLast()
                }
            }
        default:
            break
        }
    }

    private func executeDECPrivate(_ final: UInt8, params: [Int]) {
        for mode in (params.isEmpty ? [0] : params) {
            switch final {
            case 0x68: // h - Set Mode
                switch mode {
                case 1: applicationCursorKeys = true
                case 7: autoWrapMode = true
                case 25: showCursor = true
                case 2004: bracketedPasteMode = true
                case 1049, 47, 1047: // Alternate screen
                    if !alternateScreen {
                        savedCursorRow = cursorRow
                        savedCursorCol = cursorCol
                        primaryCells = cells
                        cells = Self.makeEmptyGrid(rows: rows, cols: cols)
                        alternateScreen = true
                        scrollTop = 0
                        scrollBottom = 0
                    }
                default: break
                }
            case 0x6C: // l - Reset Mode
                switch mode {
                case 1: applicationCursorKeys = false
                case 7: autoWrapMode = false
                case 25: showCursor = false
                case 2004: bracketedPasteMode = false
                case 1049, 47, 1047: // Normal screen
                    if alternateScreen {
                        if let primary = primaryCells { cells = primary }
                        primaryCells = nil
                        alternateScreen = false
                        cursorRow = savedCursorRow
                        cursorCol = savedCursorCol
                        scrollTop = 0
                        scrollBottom = 0
                    }
                default: break
                }
            default: break
            }
        }
    }

    private func executeSGR(params: [Int]) {
        var i = 0
        while i < params.count {
            let p = params[i]
            switch p {
            case 0:
                currentAttributes = CellAttributes()
            case 1: currentAttributes.bold = true
            case 3: currentAttributes.italic = true
            case 4: currentAttributes.underline = true
            case 7: currentAttributes.inverse = true
            case 9: currentAttributes.strikethrough = true
            case 22: currentAttributes.bold = false
            case 23: currentAttributes.italic = false
            case 24: currentAttributes.underline = false
            case 27: currentAttributes.inverse = false
            case 29: currentAttributes.strikethrough = false
            case 30...37:
                currentAttributes.fg = Self.ansi256Colors[p - 30]
            case 38:
                if i + 1 < params.count && params[i + 1] == 5 && i + 2 < params.count {
                    let idx = min(params[i + 2], 255)
                    currentAttributes.fg = Self.ansi256Colors[idx]
                    i += 2
                } else if i + 1 < params.count && params[i + 1] == 2 && i + 4 < params.count {
                    let r = CGFloat(params[i + 2]) / 255.0
                    let g = CGFloat(params[i + 3]) / 255.0
                    let b = CGFloat(params[i + 4]) / 255.0
                    currentAttributes.fg = NSColor(red: r, green: g, blue: b, alpha: 1)
                    i += 4
                }
            case 39: currentAttributes.fg = AppTheme.textPrimary
            case 40...47:
                currentAttributes.bg = Self.ansi256Colors[p - 40]
            case 48:
                if i + 1 < params.count && params[i + 1] == 5 && i + 2 < params.count {
                    let idx = min(params[i + 2], 255)
                    currentAttributes.bg = Self.ansi256Colors[idx]
                    i += 2
                } else if i + 1 < params.count && params[i + 1] == 2 && i + 4 < params.count {
                    let r = CGFloat(params[i + 2]) / 255.0
                    let g = CGFloat(params[i + 3]) / 255.0
                    let b = CGFloat(params[i + 4]) / 255.0
                    currentAttributes.bg = NSColor(red: r, green: g, blue: b, alpha: 1)
                    i += 4
                }
            case 49: currentAttributes.bg = .clear
            case 90...97:
                currentAttributes.fg = Self.ansi256Colors[p - 90 + 8]
            case 100...107:
                currentAttributes.bg = Self.ansi256Colors[p - 100 + 8]
            default: break
            }
            i += 1
        }
    }

    private func executeOSC() {
        switch oscParam {
        case 0, 2: // Set window title
            title = oscString
            onTitleChanged?(oscString)
        default: break
        }
    }

    private func putChar(_ char: Character) {
        if cursorCol >= cols {
            if autoWrapMode {
                cursorCol = 0
                lineFeed()
            } else {
                cursorCol = cols - 1
            }
        }
        if cursorRow >= 0 && cursorRow < rows && cursorCol >= 0 && cursorCol < cols {
            cells[cursorRow][cursorCol] = Cell(character: char, attributes: currentAttributes, dirty: true)
        }
        cursorCol += 1
    }

    private func lineFeed() {
        let bottom = effectiveScrollBottom
        if cursorRow >= bottom {
            scrollUpInRegion()
        } else {
            cursorRow += 1
        }
    }

    private func scrollUp() {
        scrollUpInRegion()
    }

    private func scrollUpInRegion() {
        let top = scrollTop
        let bottom = effectiveScrollBottom
        if top == 0 && bottom == rows - 1 {
            // Full screen scroll — use scrollback
            if scrollbackBuffer.count >= maxScrollback { scrollbackBuffer.removeFirst() }
            scrollbackBuffer.append(cells[top])
        }
        cells.remove(at: top)
        cells.insert(Array(repeating: Cell(), count: cols), at: bottom)
    }

    private func scrollDown() {
        scrollDownInRegion()
    }

    private func scrollDownInRegion() {
        let top = scrollTop
        let bottom = effectiveScrollBottom
        cells.remove(at: bottom)
        cells.insert(Array(repeating: Cell(), count: cols), at: top)
    }

    private func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Erase below
            for c in cursorCol..<cols { cells[cursorRow][c] = Cell() }
            for r in (cursorRow + 1)..<rows {
                for c in 0..<cols { cells[r][c] = Cell() }
            }
        case 1: // Erase above
            for c in 0...cursorCol { cells[cursorRow][c] = Cell() }
            for r in 0..<cursorRow {
                for c in 0..<cols { cells[r][c] = Cell() }
            }
        case 2, 3: // Erase all
            for r in 0..<rows {
                for c in 0..<cols { cells[r][c] = Cell() }
            }
        default: break
        }
    }

    private func eraseInLine(mode: Int) {
        switch mode {
        case 0: // Erase to right
            for c in cursorCol..<cols { cells[cursorRow][c] = Cell() }
        case 1: // Erase to left
            for c in 0...min(cursorCol, cols - 1) { cells[cursorRow][c] = Cell() }
        case 2: // Erase line
            for c in 0..<cols { cells[cursorRow][c] = Cell() }
        default: break
        }
    }

    private func insertLines(count: Int) {
        for _ in 0..<min(count, rows - cursorRow) {
            cells.insert(Array(repeating: Cell(), count: cols), at: cursorRow)
            cells.removeLast()
        }
    }

    private func deleteLines(count: Int) {
        for _ in 0..<min(count, rows - cursorRow) {
            cells.remove(at: cursorRow)
            cells.append(Array(repeating: Cell(), count: cols))
        }
    }

    private func deleteChars(count: Int) {
        let cnt = min(count, cols - cursorCol)
        for _ in 0..<cnt {
            cells[cursorRow].remove(at: cursorCol)
            cells[cursorRow].append(Cell())
        }
    }

    private func resetTerminal() {
        cells = Self.makeEmptyGrid(rows: rows, cols: cols)
        cursorRow = 0
        cursorCol = 0
        currentAttributes = CellAttributes()
        scrollbackBuffer.removeAll()
        showCursor = true
        applicationCursorKeys = false
    }
}
