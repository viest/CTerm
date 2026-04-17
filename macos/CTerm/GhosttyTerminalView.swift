import AppKit

/// Terminal view powered by libghostty — Ghostty's terminal engine with Metal rendering.
class GhosttyTerminalView: NSView, NSTextInputClient {
    private struct TerminalPalette {
        let background: NSColor
        let foreground: String
        let cursor: String
        let selectionBackground: String
    }

    private struct ClipboardItem {
        let mime: String
        let data: String
    }

    private static let surfaceRightGuardPoints: CGFloat = 8
    private static let returnKeyCode: UInt32 = 36

    private var ghosttyApp: ghostty_app_t?
    private(set) var ghosttySurface: ghostty_surface_t?
    private var tickTimer: Timer?
    private var lastSurfaceSizePx: (width: UInt32, height: UInt32)?

    // For NSTextInputClient / IME
    private var markedText = NSMutableAttributedString()
    private var markedSelectedRange = NSRange(location: 0, length: 0)
    private var keyTextAccumulator: [String]?

    weak var delegate: TerminalViewDelegate?
    var tokenTracker: TokenTrackerBridge?
    var sessionId: String = UUID().uuidString

    private(set) var launchCommand: String?
    private(set) var launchWorkingDir: String?
    private(set) var launchInitialInput: String?
    private(set) var launchExtraEnv: [String: String] = [:]

    // Tracked state from ghostty actions
    var currentWorkingDir: String?
    var hoveredLink: String?
    var onTitleChanged: ((String) -> Void)?
    var onCellSizeChanged: ((UInt32, UInt32) -> Void)?
    var onPaneClicked: ((GhosttyTerminalView) -> Void)?
    var onSearchTotal: ((Int) -> Void)?
    var onSearchSelected: ((Int) -> Void)?
    var onCommandFinished: ((Int16, UInt64) -> Void)?  // exit_code, duration_ns
    var onTerminalExit: (() -> Void)?
    var onUserInterrupt: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Shared Ghostty runtime (one per app)

    private static var ghosttyReady = false
    private static var sharedApp: ghostty_app_t?
    static var defaultBackgroundColor: NSColor {
        backgroundColor(for: SettingsManager.shared.settings)
    }

    private static func ensureInit() {
        guard !ghosttyReady else { return }
        ghosttyReady = true
        let carg = strdup("cterm")!
        var argv: [UnsafeMutablePointer<CChar>?] = [carg, nil]
        ghostty_init(1, &argv)
        free(carg)
    }

    private static func themeKey(for settings: AppSettings) -> String {
        settings.terminalTheme == "light" ? "light" : "dark"
    }

    private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
        NSColor(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: 1.0
        )
    }

    private static func palette(for settings: AppSettings) -> TerminalPalette {
        switch themeKey(for: settings) {
        case "light":
            return TerminalPalette(
                background: color(red: 247, green: 247, blue: 250),
                foreground: "#1E1E24",
                cursor: "#2563EB",
                selectionBackground: "#D7E4FF"
            )
        default:
            return TerminalPalette(
                background: color(red: 28, green: 28, blue: 36),
                foreground: "#E6E6EB",
                cursor: "#738CFF",
                selectionBackground: "#34405F"
            )
        }
    }

    static func backgroundColor(for settings: AppSettings) -> NSColor {
        palette(for: settings).background
    }

    private static func colorScheme(for settings: AppSettings) -> ghostty_color_scheme_e {
        themeKey(for: settings) == "light" ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
    }

    private static func cursorStyleValue(for settings: AppSettings) -> String {
        switch settings.cursorStyle {
        case "beam":
            return "bar"
        case "underline":
            return "underline"
        default:
            return "block"
        }
    }

    private static func escapedConfigString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func cleanedClipboardText(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var value = String(line)
                while value.last?.isWhitespace == true && value.last != "\n" { value.removeLast() }
                return value
            }
            .joined(separator: "\n")
    }

    private static func clipboardItems(
        from content: UnsafePointer<ghostty_clipboard_content_s>,
        count: Int
    ) -> [ClipboardItem] {
        (0..<count).compactMap { index in
            guard let mime = content[index].mime,
                  let data = content[index].data else {
                return nil
            }

            return ClipboardItem(
                mime: String(cString: mime),
                data: String(cString: data)
            )
        }
    }

    private static func pasteboardType(for mime: String) -> NSPasteboard.PasteboardType? {
        switch mime {
        case "text/plain":
            return .string
        case "text/html":
            return .html
        default:
            return NSPasteboard.PasteboardType(mime)
        }
    }

    private static func scrollbackLimitBytes(for settings: AppSettings, referenceColumns: Int) -> Int {
        let columns = max(referenceColumns, 80)
        let bytesPerLine = max(columns * 32, 1024)
        let targetBytes = max(settings.scrollbackLines, 1000) * bytesPerLine
        return max(targetBytes, 1_048_576)
    }

    private static func fallbackConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_finalize(cfg)
        return cfg
    }

    private static func makeRuntimeConfig(from settings: AppSettings, referenceColumns: Int = 80) -> ghostty_config_t? {
        ensureInit()

        let palette = palette(for: settings)
        let scrollbackLimit = scrollbackLimitBytes(for: settings, referenceColumns: referenceColumns)
        let configContents = [
            "font-family = \"\(escapedConfigString(settings.fontFamily))\"",
            "font-size = \(settings.fontSize)",
            "cursor-style = \(cursorStyleValue(for: settings))",
            "scrollback-limit = \(scrollbackLimit)",
            "background = \(palette.background.toHexString())",
            "foreground = \(palette.foreground)",
            "cursor-color = \(palette.cursor)",
            "selection-background = \(palette.selectionBackground)",
        ].joined(separator: "\n")

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cterm-ghostty-\(UUID().uuidString).conf")

        do {
            try configContents.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            return fallbackConfig()
        }

        defer { try? FileManager.default.removeItem(at: configURL) }

        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_file(cfg, configURL.path)
        ghostty_config_finalize(cfg)
        return cfg
    }

    static func applySharedSettings(_ settings: AppSettings) {
        guard let app = sharedApp else { return }
        guard let cfg = makeRuntimeConfig(from: settings) else { return }
        defer { ghostty_config_free(cfg) }

        ghostty_app_update_config(app, cfg)
        ghostty_app_set_color_scheme(app, colorScheme(for: settings))
    }

    private static func ensureApp() -> ghostty_app_t? {
        if let app = sharedApp { return app }
        ensureInit()

        guard let cfg = makeRuntimeConfig(from: SettingsManager.shared.settings) ?? fallbackConfig() else { return nil }
        defer { ghostty_config_free(cfg) }

        var rt = ghostty_runtime_config_s()
        rt.supports_selection_clipboard = false
        rt.wakeup_cb = { _ in
            DispatchQueue.main.async { GhosttyTerminalView.tickAll() }
        }
        rt.action_cb = { appHandle, target, action in
            // Resolve the surface's userdata to find the GhosttyTerminalView
            var surface: ghostty_surface_t? = nil
            if target.tag == GHOSTTY_TARGET_SURFACE {
                surface = target.target.surface
            }

            var view: GhosttyTerminalView? = nil
            if let s = surface {
                let ud = ghostty_surface_userdata(s)
                if let ud { view = Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue() }
            }

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                if let v = view, let cTitle = action.action.set_title.title {
                    let title = String(cString: cTitle)
                    DispatchQueue.main.async {
                        v.onTitleChanged?(title)
                        v.delegate?.terminalDidUpdateTitle(title)
                    }
                }
                return true

            case GHOSTTY_ACTION_PWD:
                if let v = view, let cPwd = action.action.pwd.pwd {
                    let pwd = String(cString: cPwd)
                    DispatchQueue.main.async { v.currentWorkingDir = pwd }
                }
                return true

            case GHOSTTY_ACTION_CELL_SIZE:
                if let v = view {
                    let cs = action.action.cell_size
                    DispatchQueue.main.async { v.onCellSizeChanged?(cs.width, cs.height) }
                }
                return true

            case GHOSTTY_ACTION_MOUSE_OVER_LINK:
                if let v = view {
                    let link = action.action.mouse_over_link
                    if let url = link.url, link.len > 0 {
                        let str = String(cString: url)
                        DispatchQueue.main.async { v.hoveredLink = str }
                    } else {
                        DispatchQueue.main.async { v.hoveredLink = nil }
                    }
                }
                return true

            case GHOSTTY_ACTION_OPEN_URL:
                let urlAction = action.action.open_url
                if let cUrl = urlAction.url, urlAction.len > 0 {
                    let urlStr = String(cString: cUrl)
                    DispatchQueue.main.async {
                        if let url = URL(string: urlStr) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                return true

            case GHOSTTY_ACTION_CLOSE_WINDOW:
                if let v = view {
                    DispatchQueue.main.async {
                        v.onTerminalExit?()
                        v.delegate?.terminalDidExit(status: 0)
                    }
                }
                return true

            case GHOSTTY_ACTION_SEARCH_TOTAL:
                if let v = view {
                    let total = Int(action.action.search_total.total)
                    DispatchQueue.main.async { v.onSearchTotal?(total) }
                }
                return true

            case GHOSTTY_ACTION_SEARCH_SELECTED:
                if let v = view {
                    let selected = Int(action.action.search_selected.selected)
                    DispatchQueue.main.async { v.onSearchSelected?(selected) }
                }
                return true

            case GHOSTTY_ACTION_COMMAND_FINISHED:
                if let v = view {
                    let finished = action.action.command_finished
                    DispatchQueue.main.async {
                        v.onCommandFinished?(finished.exit_code, finished.duration)
                    }
                }
                return true

            default:
                return false
            }
        }

        rt.write_clipboard_cb = { ud, clipType, content, count, confirm in
            guard count > 0, let content else { return }
            let items = GhosttyTerminalView.clipboardItems(from: content, count: count)
            guard !items.isEmpty else { return }

            DispatchQueue.main.async {
                let pb = NSPasteboard.general
                pb.clearContents()

                let declaredTypes = items.compactMap { GhosttyTerminalView.pasteboardType(for: $0.mime) }
                if !declaredTypes.isEmpty {
                    pb.declareTypes(declaredTypes, owner: nil)
                }

                for item in items {
                    guard let type = GhosttyTerminalView.pasteboardType(for: item.mime) else { continue }
                    let value = item.mime == "text/plain"
                        ? GhosttyTerminalView.cleanedClipboardText(item.data)
                        : item.data
                    pb.setString(value, forType: type)
                }
            }
        }

        rt.read_clipboard_cb = { ud, clipType, statePtr in
            guard let ud, let statePtr else { return false }
            let view = Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                guard let surface = view.ghosttySurface else { return }
                let pb = NSPasteboard.general
                let text = pb.string(forType: .string) ?? ""
                text.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, statePtr, true)
                }
            }
            return true
        }
        rt.close_surface_cb = { ud, _ in
            guard let ud else { return }
            let view = Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue()
            DispatchQueue.main.async {
                view.onTerminalExit?()
                view.delegate?.terminalDidExit(status: 0)
            }
        }

        guard let app = ghostty_app_new(&rt, cfg) else {
            return nil
        }
        ghostty_app_set_color_scheme(app, colorScheme(for: SettingsManager.shared.settings))
        sharedApp = app
        return app
    }

    private static func tickAll() {
        guard let app = sharedApp else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Init

    init(
        frame: NSRect,
        command: String? = nil,
        workingDir: String? = nil,
        initialInput: String? = nil,
        extraEnv: [String: String] = [:]
    ) {
        launchCommand = command
        launchWorkingDir = workingDir
        launchInitialInput = initialInput
        launchExtraEnv = extraEnv
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Self.backgroundColor(for: SettingsManager.shared.settings).cgColor

        guard let app = Self.ensureApp() else { return }
        self.ghosttyApp = app

        if tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60, repeats: true) { _ in
                GhosttyTerminalView.tickAll()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.createSurface(command: command, workingDir: workingDir, initialInput: initialInput)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func rememberShellReplay(initialInput: String, workingDir: String? = nil) {
        launchCommand = "/bin/zsh"
        launchWorkingDir = workingDir ?? currentWorkingDir ?? launchWorkingDir
        launchInitialInput = initialInput
    }

    func executeShellCommand(_ command: String) {
        guard let surface = ghosttySurface, !command.isEmpty else { return }

        let body = command.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        let trailingNewlineCount = command.reversed().prefix { $0 == "\n" || $0 == "\r" }.count

        if !body.isEmpty {
            ghostty_surface_text(surface, body, UInt(body.utf8.count))
        }

        if trailingNewlineCount > 0 {
            for _ in 0..<trailingNewlineCount {
                sendReturnKey(to: surface)
            }
        }
    }

    private func pasteString(_ text: String) {
        guard let surface = ghosttySurface, !text.isEmpty else { return }
        ghostty_surface_text(surface, text, UInt(text.utf8.count))
    }

    @discardableResult
    private func handlePasteboardContents() -> Bool {
        let pb = NSPasteboard.general

        if let image = NSImage(pasteboard: pb),
           let path = saveImageToTemp(image) {
            pasteString(path)
            return true
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            pasteString(urls.map(\.path).joined(separator: " "))
            return true
        }

        if let text = pb.string(forType: .string),
           !text.isEmpty {
            pasteString(text)
            return true
        }

        return false
    }

    private func createSurface(command: String?, workingDir: String?, initialInput: String? = nil) {
        guard let app = ghosttyApp, ghosttySurface == nil else { return }
        guard bounds.width > 10, bounds.height > 10 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.createSurface(command: command, workingDir: workingDir, initialInput: initialInput)
            }
            return
        }

        // strdup all C strings before surface creation to keep them alive
        let cmdPtr = command.map { strdup($0) }
        let dirPtr = workingDir.map { strdup($0) }
        let inputPtr = initialInput.map { strdup($0) }

        // Env vars are passed as an array of {key,value} C-string pairs. We
        // strdup each, hold them in a local array, and free after surface
        // creation (ghostty copies the struct contents internally).
        var envKeyPtrs: [UnsafeMutablePointer<CChar>] = []
        var envValPtrs: [UnsafeMutablePointer<CChar>] = []
        var envPairs: [ghostty_env_var_s] = []
        for (k, v) in launchExtraEnv where !k.isEmpty {
            guard let kp = strdup(k), let vp = strdup(v) else { continue }
            envKeyPtrs.append(kp)
            envValPtrs.append(vp)
            envPairs.append(
                ghostty_env_var_s(key: UnsafePointer(kp), value: UnsafePointer(vp))
            )
        }

        defer {
            cmdPtr.map { free($0) }
            dirPtr.map { free($0) }
            inputPtr.map { free($0) }
            envKeyPtrs.forEach { free($0) }
            envValPtrs.forEach { free($0) }
        }

        var scfg = ghostty_surface_config_new()
        let settings = SettingsManager.shared.settings
        scfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        scfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        scfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        let scale = Double(window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        scfg.scale_factor = scale
        scfg.font_size = Float(settings.fontSize)
        if let p = cmdPtr { scfg.command = UnsafePointer(p) }
        if let p = dirPtr { scfg.working_directory = UnsafePointer(p) }

        ghosttySurface = envPairs.withUnsafeMutableBufferPointer { buf -> ghostty_surface_t? in
            if let base = buf.baseAddress, !buf.isEmpty {
                scfg.env_vars = base
                scfg.env_var_count = buf.count
            }
            return ghostty_surface_new(app, &scfg)
        }

        // Send initial input (agent command) after surface is created
        if let surface = ghosttySurface, let input = initialInput, !input.isEmpty {
            // Delay slightly to let shell initialize
            let inputCopy = input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard self?.ghosttySurface == surface else { return }
                self?.executeShellCommand(inputCopy)
            }
        }

        guard let surface = ghosttySurface else { return }
        applyTerminalSettings(settings)
        applySurfaceSize(bounds.size, to: surface)
        ghostty_surface_set_content_scale(surface, scale, scale)
        ghostty_surface_set_focus(surface, true)
    }

    deinit {
        tickTimer?.invalidate()
        if let s = ghosttySurface { ghostty_surface_free(s) }
    }

    // MARK: - View lifecycle

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let s = ghosttySurface else { return }
        applySurfaceSize(newSize, to: s)
        inputContext?.invalidateCharacterCoordinates()
    }

    private func surfaceDrawableSize(from size: NSSize) -> NSSize {
        NSSize(
            width: max(1, size.width - Self.surfaceRightGuardPoints),
            height: size.height
        )
    }

    private func clampedMousePointForSurface(from point: NSPoint) -> NSPoint {
        let drawableSize = surfaceDrawableSize(from: bounds.size)
        let clampedX = min(max(point.x, 0), drawableSize.width)
        let clampedY = min(max(point.y, 0), drawableSize.height)

        return NSPoint(
            x: clampedX,
            y: drawableSize.height - clampedY
        )
    }

    private func updateMousePosition(for event: NSEvent, on surface: ghostty_surface_t) {
        let point = convert(event.locationInWindow, from: nil)
        let surfacePoint = clampedMousePointForSurface(from: point)
        ghostty_surface_mouse_pos(surface, surfacePoint.x, surfacePoint.y, ghosttyMods(event.modifierFlags))
    }

    private func applySurfaceSize(_ size: NSSize, to surface: ghostty_surface_t) {
        guard size.width > 10, size.height > 10 else { return }

        let backed = convertToBacking(surfaceDrawableSize(from: size))
        let width = UInt32(backed.width)
        let height = UInt32(backed.height)

        if let lastSurfaceSizePx, lastSurfaceSizePx.width == width, lastSurfaceSizePx.height == height {
            return
        }

        lastSurfaceSizePx = (width: width, height: height)
        ghostty_surface_set_size(surface, width, height)
    }

    func applyTerminalSettings(_ settings: AppSettings) {
        layer?.backgroundColor = Self.backgroundColor(for: settings).cgColor

        guard let surface = ghosttySurface else { return }
        let size = ghostty_surface_size(surface)
        let referenceColumns = max(Int(size.columns), 80)
        guard let cfg = Self.makeRuntimeConfig(from: settings, referenceColumns: referenceColumns) else {
            ghostty_surface_set_color_scheme(surface, Self.colorScheme(for: settings))
            ghostty_surface_refresh(surface)
            return
        }
        defer { ghostty_config_free(cfg) }

        ghostty_surface_update_config(surface, cfg)
        ghostty_surface_set_color_scheme(surface, Self.colorScheme(for: settings))
        ghostty_surface_refresh(surface)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let s = ghosttySurface, let scr = window?.screen else { return }
        let scale = Double(scr.backingScaleFactor)
        ghostty_surface_set_content_scale(s, scale, scale)
        ghostty_surface_refresh(s)
        inputContext?.invalidateCharacterCoordinates()
    }

    override func becomeFirstResponder() -> Bool {
        ghosttySurface.map { ghostty_surface_set_focus($0, true) }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        ghosttySurface.map { ghostty_surface_set_focus($0, false) }
        return super.resignFirstResponder()
    }

    // MARK: - Keyboard (matching Ghostty's own macOS input handling)

    override func keyDown(with event: NSEvent) {
        guard ghosttySurface != nil else { return }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v",
           handlePasteboardContents() {
            return
        }

        // Treat Ctrl+C as a user-initiated interrupt. Still pass through to
        // the PTY so ^C reaches the agent; the callback just lets the UI
        // clear a stale "running" indicator when the agent halts without
        // firing a Stop hook (common for interrupted Claude Code turns).
        if event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "c" {
            onUserInterrupt?()
        }

        let hadMarkedText = hasMarkedText()
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        // Use interpretKeyEvents to support IME, dead keys, etc.
        interpretKeyEvents([event])

        // Now send the key event with accumulated text
        let text = keyTextAccumulator?.joined()
        let hasCommittedText = text?.isEmpty == false
        if hasMarkedText() || (hadMarkedText && !hasCommittedText) {
            return
        }
        sendKeyEvent(action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS,
                     event: event, text: text)
    }

    override func keyUp(with event: NSEvent) {
        sendKeyEvent(action: GHOSTTY_ACTION_RELEASE, event: event, text: nil)
    }

    override func flagsChanged(with event: NSEvent) {
        if hasMarkedText() {
            return
        }
        // Ghostty handles modifier-only events
        sendKeyEvent(action: GHOSTTY_ACTION_PRESS, event: event, text: nil)
    }

    override func doCommand(by commandSelector: Selector) {
        // interpretKeyEvents maps terminal keys like arrows, return, and
        // delete/backspace into selectors. Ghostty already receives the raw
        // key events below, so AppKit fallback here only causes NSBeep().
        _ = commandSelector
        return
    }

    @IBAction func paste(_ sender: Any?) {
        _ = sender
        _ = handlePasteboardContents()
    }

    private func sendKeyEvent(action: ghostty_input_action_e, event: NSEvent, text: String?) {
        guard let surface = ghosttySurface else { return }

        var keyEv = ghostty_input_key_s()
        keyEv.action = action
        keyEv.keycode = UInt32(event.keyCode)
        keyEv.mods = ghosttyMods(event.modifierFlags)
        keyEv.consumed_mods = ghosttyMods(event.modifierFlags.subtracting([.control, .command]))
        keyEv.composing = false
        keyEv.text = nil

        // Set unshifted codepoint
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let cp = chars.unicodeScalars.first {
                keyEv.unshifted_codepoint = cp.value
            }
        }

        if let text, !text.isEmpty,
           let first = text.utf8.first, first >= 0x20 {
            text.withCString { ptr in
                keyEv.text = ptr
                ghostty_surface_key(surface, keyEv)
            }
        } else {
            ghostty_surface_key(surface, keyEv)
        }
    }

    private func sendReturnKey(to surface: ghostty_surface_t) {
        var keyEv = ghostty_input_key_s()
        keyEv.action = GHOSTTY_ACTION_PRESS
        keyEv.mods = GHOSTTY_MODS_NONE
        keyEv.consumed_mods = GHOSTTY_MODS_NONE
        keyEv.keycode = Self.returnKeyCode
        keyEv.unshifted_codepoint = 13
        keyEv.composing = false
        ghostty_surface_key(surface, keyEv)
    }

    private func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(mods)
    }

    // MARK: - NSTextInputClient (required for IME + interpretKeyEvents)

    func insertText(_ string: Any, replacementRange: NSRange) {
        let str: String
        if let s = string as? NSAttributedString { str = s.string }
        else if let s = string as? String { str = s }
        else { return }

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(str)
        } else {
            // Direct text input (e.g. from IME commit outside keyDown)
            guard let surface = ghosttySurface else { return }
            updatePreeditText("")
            ghostty_surface_text(surface, str, UInt(str.utf8.count))
        }

        // Clear marked text on commit
        markedText = NSMutableAttributedString()
        markedSelectedRange = NSRange(location: 0, length: 0)
        updatePreeditText("")
        inputContext?.invalidateCharacterCoordinates()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let s = string as? NSAttributedString { markedText = NSMutableAttributedString(attributedString: s) }
        else if let s = string as? String { markedText = NSMutableAttributedString(string: s) }
        let location = max(0, min(selectedRange.location, markedText.length))
        let length = max(0, min(selectedRange.length, markedText.length - location))
        markedSelectedRange = NSRange(location: location, length: length)
        updatePreeditText(markedText.string)
        inputContext?.invalidateCharacterCoordinates()
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        markedSelectedRange = NSRange(location: 0, length: 0)
        updatePreeditText("")
        inputContext?.invalidateCharacterCoordinates()
    }
    func selectedRange() -> NSRange {
        if markedText.length > 0 {
            let location = max(0, min(markedSelectedRange.location, markedText.length))
            let length = max(0, min(markedSelectedRange.length, markedText.length - location))
            return NSRange(location: location, length: length)
        }
        return NSRange(location: 0, length: 0)
    }
    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }
    func hasMarkedText() -> Bool { markedText.length > 0 }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = markedRange()

        guard let surface = ghosttySurface else {
            return window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
        }

        var x = 0.0
        var y = 0.0
        var width = 0.0
        var height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let backingRect = NSRect(
            x: x,
            y: y,
            width: max(width, 1),
            height: max(height, 1)
        )
        let localRect = convertFromBacking(backingRect)
        let windowRect = convert(localRect, to: nil)
        return window?.convertToScreen(windowRect) ?? localRect
    }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    private func updatePreeditText(_ text: String) {
        guard let surface = ghosttySurface else { return }
        ghostty_surface_preedit(surface, text, UInt(text.utf8.count))
    }

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

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onPaneClicked?(self)

        // Cmd+Click: open hovered link
        if event.modifierFlags.contains(.command), let link = hoveredLink, !link.isEmpty {
            if link.hasPrefix("http://") || link.hasPrefix("https://") {
                if let url = URL(string: link) { NSWorkspace.shared.open(url) }
            } else {
                // Treat as file path — open in default editor
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [link]
                try? process.run()
            }
            return
        }

        guard let s = ghosttySurface else { return }
        updateMousePosition(for: event, on: s)
        ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT,
                                     ghosttyMods(event.modifierFlags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = ghosttySurface else { return }
        updateMousePosition(for: event, on: s)
        ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT,
                                     ghosttyMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = ghosttySurface else { return }
        updateMousePosition(for: event, on: s)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let s = ghosttySurface else { return }
        updateMousePosition(for: event, on: s)

        // Update cursor for Cmd+hover links
        if event.modifierFlags.contains(.command) && hoveredLink != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let s = ghosttySurface else { return }
        ghostty_surface_mouse_scroll(s, event.scrollingDeltaX, event.scrollingDeltaY,
                                     event.hasPreciseScrollingDeltas ? 1 : 0)
    }
}

private extension NSColor {
    func toHexString() -> String {
        guard let converted = usingColorSpace(.deviceRGB) else { return "#000000" }
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
