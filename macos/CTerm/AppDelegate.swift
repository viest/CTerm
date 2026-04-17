import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    private var aboutWindow: AboutWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveCurrentLayout()
        AgentHookServer.shared.stop()
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About CTerm", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CTerm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Workspace...", action: #selector(MainWindowController.newWorkspace(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Terminal Tab", action: #selector(MainWindowController.newTerminalTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeCurrentTab(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Quick Open...", action: #selector(MainWindowController.showQuickOpen(_:)), keyEquivalent: "p")
        fileMenu.items.last?.keyEquivalentModifierMask = .command
        fileMenu.addItem(withTitle: "Search in Workspaces...", action: #selector(MainWindowController.showSearch(_:)), keyEquivalent: "f")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Add Project...", action: #selector(MainWindowController.addProject(_:)), keyEquivalent: "o")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Toggle Left Sidebar", action: #selector(MainWindowController.toggleLeftSidebar(_:)), keyEquivalent: "b")
        viewMenu.items.last?.keyEquivalentModifierMask = .command
        viewMenu.addItem(withTitle: "Toggle Right Sidebar", action: #selector(MainWindowController.toggleRightSidebar(_:)), keyEquivalent: "l")
        viewMenu.items.last?.keyEquivalentModifierMask = .command
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Save Layout...", action: #selector(MainWindowController.saveLayout(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "Load Layout...", action: #selector(MainWindowController.loadLayout(_:)), keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Terminal menu
        let termMenuItem = NSMenuItem()
        let termMenu = NSMenu(title: "Terminal")
        termMenu.addItem(withTitle: "Split Right", action: #selector(MainWindowController.splitHorizontal(_:)), keyEquivalent: "d")
        termMenu.items.last?.keyEquivalentModifierMask = .command
        termMenu.addItem(withTitle: "Split Down", action: #selector(MainWindowController.splitVertical(_:)), keyEquivalent: "d")
        termMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        termMenu.addItem(.separator())
        termMenu.addItem(withTitle: "Equalize Panes", action: #selector(MainWindowController.equalizePanes(_:)), keyEquivalent: "0")
        termMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        termMenu.addItem(withTitle: "Next Pane", action: #selector(MainWindowController.focusNextPane(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        termMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        termMenu.addItem(withTitle: "Previous Pane", action: #selector(MainWindowController.focusPreviousPane(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        termMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        termMenu.addItem(.separator())
        termMenu.addItem(withTitle: "Find...", action: #selector(MainWindowController.findInTerminal(_:)), keyEquivalent: "f")
        termMenu.items.last?.keyEquivalentModifierMask = .command
        termMenu.addItem(withTitle: "Clear Screen", action: #selector(MainWindowController.clearScreen(_:)), keyEquivalent: "k")
        termMenu.items.last?.keyEquivalentModifierMask = .command
        termMenu.addItem(withTitle: "Scroll to Bottom", action: #selector(MainWindowController.scrollToBottom(_:)), keyEquivalent: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
        termMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        termMenu.addItem(.separator())
        termMenu.addItem(withTitle: "Run Workspace Scripts", action: #selector(MainWindowController.runWorkspaceScripts(_:)), keyEquivalent: "g")
        termMenu.items.last?.keyEquivalentModifierMask = .command
        termMenuItem.submenu = termMenu
        mainMenu.addItem(termMenuItem)

        // IDE menu
        let ideMenuItem = NSMenuItem()
        let ideMenu = NSMenu(title: "IDE")
        ideMenu.addItem(withTitle: "Open in Editor", action: #selector(MainWindowController.openInEditor(_:)), keyEquivalent: "o")
        ideMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        ideMenu.addItem(withTitle: "Copy Workspace Path", action: #selector(MainWindowController.copyWorkspacePath(_:)), keyEquivalent: "c")
        ideMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        ideMenu.addItem(.separator())
        // Cmd+Shift+1-9 for presets
        for i in 1...9 {
            let item = NSMenuItem(title: "Open Preset \(i)", action: #selector(MainWindowController.openPresetByIndex(_:)), keyEquivalent: "\(i)")
            item.keyEquivalentModifierMask = [.command, .shift]
            item.tag = i - 1
            ideMenu.addItem(item)
        }
        ideMenuItem.submenu = ideMenu
        mainMenu.addItem(ideMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
    }

    @objc func showSettings(_ sender: Any?) {
        mainWindowController?.showSettings(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        if aboutWindow == nil {
            aboutWindow = AboutWindow()
        }
        aboutWindow?.present(attachedTo: mainWindowController?.window)
    }
}
