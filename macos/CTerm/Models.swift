import Foundation
import AppKit

struct ProjectItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: String
    var editor: String
    var description: String
    var lastOpened: Date
    var pinned: Bool

    init(name: String, path: String, editor: String = "", description: String = "", pinned: Bool = false) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.editor = editor
        self.description = description
        self.lastOpened = Date()
        self.pinned = pinned
    }
}

struct AgentPresetItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var command: String
    var description: String
    var provider: String
    var icon: String
    var workingDir: String
    var shortcut: String
    var autoApply: Bool
    var isDefault: Bool
    var pinned: Bool

    init(name: String, command: String, description: String = "", provider: String = "",
         icon: String = "terminal", workingDir: String = "", shortcut: String = "",
         autoApply: Bool = false, isDefault: Bool = false, pinned: Bool = true) {
        self.id = UUID()
        self.name = name
        self.command = command
        self.description = description
        self.provider = provider
        self.icon = icon
        self.workingDir = workingDir
        self.shortcut = shortcut
        self.autoApply = autoApply
        self.isDefault = isDefault
        self.pinned = pinned
    }
}

struct TokenUsage: Codable {
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var cacheWriteTokens: Int64 = 0
    var costUSD: Double = 0.0
    var entryCount: Int32 = 0

    var totalTokens: Int64 { inputTokens + outputTokens }

    var formattedCost: String {
        String(format: "$%.4f", costUSD)
    }

    var formattedTokens: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let input = formatter.string(from: NSNumber(value: inputTokens)) ?? "0"
        let output = formatter.string(from: NSNumber(value: outputTokens)) ?? "0"
        return "\(input) in / \(output) out"
    }
}

struct WorkspaceItem: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var name: String
    var branchName: String
    var worktreePath: String
    var prompt: String
    var agentCommand: String
    var agentProvider: String
    var status: WorkspaceStatus
    var createdAt: Date

    enum WorkspaceStatus: String, Codable {
        case running
        case idle
        case completed
        case error
    }

    init(projectId: UUID, name: String, branchName: String, worktreePath: String,
         prompt: String, agentCommand: String, agentProvider: String) {
        self.id = UUID()
        self.projectId = projectId
        self.name = name
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.prompt = prompt
        self.agentCommand = agentCommand
        self.agentProvider = agentProvider
        self.status = .running
        self.createdAt = Date()
    }
}

struct GitChange: Identifiable {
    let id = UUID()
    let status: ChangeStatus
    let filePath: String
    let diff: String

    enum ChangeStatus: String {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case untracked = "?"

        var color: NSColor {
            switch self {
            case .added: return .systemGreen
            case .modified: return .systemOrange
            case .deleted: return .systemRed
            case .renamed: return .systemBlue
            case .untracked: return .systemGray
            }
        }

        var icon: String {
            switch self {
            case .added: return "+"
            case .modified: return "~"
            case .deleted: return "-"
            case .renamed: return ">"
            case .untracked: return "?"
            }
        }
    }
}

struct WorkspaceConfig: Codable {
    var setup: [String]?
    var teardown: [String]?
    var run: [String]?
}

// MARK: - App Settings

struct AppSettings: Codable {
    // General
    var worktreeBaseDir: String = "~/.cterm/worktrees/"
    var defaultShell: String = "/bin/zsh"
    var defaultEditor: String = "code"
    var agentAutoRun: Bool = true
    var autoApplyOnNewTab: Bool = false
    var confirmOnQuit: Bool = false

    // Terminal
    var fontFamily: String = "SF Mono"
    var fontSize: Double = 13
    var scrollbackLines: Int = 10000
    var cursorStyle: String = "block"
    var terminalTheme: String = "dark"

    // Keyboard shortcuts: action name -> shortcut string
    var shortcuts: [String: String] = [:]
}

class SettingsManager {
    static let shared = SettingsManager()
    var settings: AppSettings

    var onSettingsChanged: (() -> Void)?

    private let settingsURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CTerm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        settingsURL = dir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(settings) {
            try? data.write(to: settingsURL)
        }
        onSettingsChanged?()
    }
}

struct EditorDefinition {
    enum LineStyle {
        case none       // no line-number support
        case vscode     // `<cli> -g path:line`
        case zed        // `<cli> path:line`
        case intellij   // `<cli> --line <n> path`
        case sublime    // `<cli> path:line`
        case xed        // `xed --line <n> path`
        case terminal   // spawn `<cli> +<n> path` inside Terminal.app
    }

    let id: String              // stable key stored in settings / ProjectItem.editor
    let displayName: String     // shown in UI
    let applicationName: String?// macOS .app name for `open -a`; nil = terminal-only
    let cliCommand: String?     // CLI binary to try first (if on PATH)
    let lineStyle: LineStyle
}

enum EditorLauncher {
    static let catalog: [EditorDefinition] = [
        .init(id: "code",           displayName: "VS Code",            applicationName: "Visual Studio Code",          cliCommand: "code",          lineStyle: .vscode),
        .init(id: "code-insiders",  displayName: "VS Code Insiders",   applicationName: "Visual Studio Code - Insiders", cliCommand: "code-insiders", lineStyle: .vscode),
        .init(id: "cursor",         displayName: "Cursor",             applicationName: "Cursor",                      cliCommand: "cursor",        lineStyle: .vscode),
        .init(id: "windsurf",       displayName: "Windsurf",           applicationName: "Windsurf",                    cliCommand: "windsurf",      lineStyle: .vscode),
        .init(id: "zed",            displayName: "Zed",                applicationName: "Zed",                         cliCommand: "zed",           lineStyle: .zed),
        .init(id: "fleet",          displayName: "Fleet",              applicationName: "Fleet",                       cliCommand: "fleet",         lineStyle: .none),
        .init(id: "idea",           displayName: "IntelliJ IDEA",      applicationName: "IntelliJ IDEA",               cliCommand: "idea",          lineStyle: .intellij),
        .init(id: "webstorm",       displayName: "WebStorm",           applicationName: "WebStorm",                    cliCommand: "webstorm",      lineStyle: .intellij),
        .init(id: "pycharm",        displayName: "PyCharm",            applicationName: "PyCharm",                     cliCommand: "pycharm",       lineStyle: .intellij),
        .init(id: "goland",         displayName: "GoLand",             applicationName: "GoLand",                      cliCommand: "goland",        lineStyle: .intellij),
        .init(id: "rider",          displayName: "Rider",              applicationName: "Rider",                       cliCommand: "rider",         lineStyle: .intellij),
        .init(id: "phpstorm",       displayName: "PhpStorm",           applicationName: "PhpStorm",                    cliCommand: "phpstorm",      lineStyle: .intellij),
        .init(id: "clion",          displayName: "CLion",              applicationName: "CLion",                       cliCommand: "clion",         lineStyle: .intellij),
        .init(id: "rubymine",       displayName: "RubyMine",           applicationName: "RubyMine",                    cliCommand: "rubymine",      lineStyle: .intellij),
        .init(id: "subl",           displayName: "Sublime Text",       applicationName: "Sublime Text",                cliCommand: "subl",          lineStyle: .sublime),
        .init(id: "xcode",          displayName: "Xcode",              applicationName: "Xcode",                       cliCommand: "xed",           lineStyle: .xed),
        .init(id: "nova",           displayName: "Nova",               applicationName: "Nova",                        cliCommand: "nova",          lineStyle: .none),
        .init(id: "bbedit",         displayName: "BBEdit",             applicationName: "BBEdit",                      cliCommand: "bbedit",        lineStyle: .sublime),
        .init(id: "vim",            displayName: "Vim (Terminal)",     applicationName: nil,                           cliCommand: "vim",           lineStyle: .terminal),
        .init(id: "nvim",           displayName: "Neovim (Terminal)",  applicationName: nil,                           cliCommand: "nvim",          lineStyle: .terminal),
    ]

    private static let byId: [String: EditorDefinition] = Dictionary(
        uniqueKeysWithValues: catalog.map { ($0.id, $0) }
    )

    static let fallbackAccentColor: NSColor = NSColor(white: 0.55, alpha: 1)

    static func definition(for id: String) -> EditorDefinition? { byId[id] }

    /// Editors detected as installed on this machine. An app-backed editor counts as installed
    /// when its `.app` bundle is present under a standard Applications root; a terminal-only
    /// editor (e.g. vim) counts when its CLI resolves on PATH. Any ids passed in `alwaysInclude`
    /// are kept in the result even when not detected — useful so a user's currently-selected
    /// default remains visible in menus.
    static func installedEditors(alwaysInclude ids: [String] = []) -> [EditorDefinition] {
        let pinned = Set(
            ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
        )
        return catalog.filter { isInstalled($0) || pinned.contains($0.id) }
    }

    static func isInstalled(_ def: EditorDefinition) -> Bool {
        if let cached = installationCache[def.id] { return cached }
        let result = computeIsInstalled(def)
        installationCache[def.id] = result
        return result
    }

    private static var installationCache: [String: Bool] = [:]

    private static func computeIsInstalled(_ def: EditorDefinition) -> Bool {
        if let appName = def.applicationName {
            return applicationIsInstalled(named: appName)
        }
        if let cli = def.cliCommand {
            return commandExists(cli)
        }
        return false
    }

    private static let applicationSearchRoots: [String] = {
        let home = NSHomeDirectory()
        return [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(home)/Applications",
            "\(home)/Applications/JetBrains Toolbox",
        ]
    }()

    private static func applicationIsInstalled(named name: String) -> Bool {
        let fm = FileManager.default
        for root in applicationSearchRoots {
            if fm.fileExists(atPath: "\(root)/\(name).app") { return true }
        }
        return false
    }

    private static func commandExists(_ cmd: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [cmd]
        process.environment = cliEnvironment()
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func displayName(for id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "VS Code" }
        return byId[trimmed]?.displayName ?? trimmed
    }

    /// Resolves the editor id to use: project override first, then the global default, then "code".
    static func resolvedEditor(for project: ProjectItem?) -> String {
        if let override = project?.editor.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        let global = SettingsManager.shared.settings.defaultEditor
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return global.isEmpty ? "code" : global
    }

    @discardableResult
    static func open(path: String, editor: String, line: Int? = nil) -> Bool {
        let normalized = editor.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedId = normalized.isEmpty ? "code" : normalized
        let def = byId[resolvedId]
        var errors: [String] = []

        if let def, def.lineStyle == .terminal, let cli = def.cliCommand {
            if let error = runTerminalEditor(command: cli, path: path, line: line) {
                errors.append(error)
            } else {
                return true
            }
        } else {
            if let def, let cli = def.cliCommand {
                let args = cliArguments(command: cli, style: def.lineStyle, path: path, line: line)
                if let error = runProcess(
                    executablePath: "/usr/bin/env",
                    arguments: args,
                    environment: cliEnvironment()
                ) {
                    errors.append(error)
                } else {
                    return true
                }
            }

            if let def, let appName = def.applicationName {
                if let error = runProcess(
                    executablePath: "/usr/bin/open",
                    arguments: ["-a", appName, path]
                ) {
                    errors.append(error)
                } else {
                    return true
                }
            }

            // Last-ditch: treat the id itself as either an app name or CLI command.
            if let error = runProcess(
                executablePath: "/usr/bin/open",
                arguments: ["-a", resolvedId, path]
            ) {
                errors.append(error)
            } else {
                return true
            }
        }

        NSSound.beep()
        let details = errors.filter { !$0.isEmpty }.joined(separator: " | ")
        if details.isEmpty {
            NSLog("CTerm: failed to open \(path) in editor \(resolvedId)")
        } else {
            NSLog("CTerm: failed to open \(path) in editor \(resolvedId): \(details)")
        }
        return false
    }

    private static func cliArguments(command: String, style: EditorDefinition.LineStyle, path: String, line: Int?) -> [String] {
        switch style {
        case .vscode:
            if let line { return [command, "-g", "\(path):\(line)"] }
            return [command, path]
        case .zed, .sublime:
            if let line { return [command, "\(path):\(line)"] }
            return [command, path]
        case .intellij, .xed:
            if let line { return [command, "--line", "\(line)", path] }
            return [command, path]
        case .none, .terminal:
            return [command, path]
        }
    }

    private static func cliEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPathEntries = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let defaultPathEntries = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen: Set<String> = []
        let mergedPath = (existingPathEntries + defaultPathEntries).filter { seen.insert($0).inserted }
        environment["PATH"] = mergedPath.joined(separator: ":")
        return environment
    }

    private static func runTerminalEditor(command: String, path: String, line: Int?) -> String? {
        let escapedPath = shellQuoted(path)
        let invocation = line.map { "\(command) +\($0) \(escapedPath)" } ?? "\(command) \(escapedPath)"
        let scriptCommand = invocation
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return runProcess(
            executablePath: "/usr/bin/osascript",
            arguments: [
                "-e", "tell application \"Terminal\" to activate",
                "-e", "tell application \"Terminal\" to do script \"\(scriptCommand)\"",
            ]
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }

        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }

        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if errorMessage.isEmpty {
            return "exit status \(process.terminationStatus)"
        }
        return errorMessage
    }
}

extension EditorDefinition {
    /// Brand-ish accent color used by the Open-in-editor button's icon tile.
    var accentColor: NSColor {
        switch id {
        case "code":           return NSColor(red: 0.00, green: 0.48, blue: 0.79, alpha: 1)
        case "code-insiders":  return NSColor(red: 0.16, green: 0.57, blue: 0.23, alpha: 1)
        case "cursor":         return NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        case "windsurf":       return NSColor(red: 0.00, green: 0.78, blue: 0.57, alpha: 1)
        case "zed":            return NSColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1)
        case "fleet":          return NSColor(red: 0.36, green: 0.27, blue: 0.87, alpha: 1)
        case "idea":           return NSColor(red: 0.91, green: 0.28, blue: 0.55, alpha: 1)
        case "webstorm":       return NSColor(red: 0.00, green: 0.56, blue: 0.83, alpha: 1)
        case "pycharm":        return NSColor(red: 0.96, green: 0.79, blue: 0.00, alpha: 1)
        case "goland":         return NSColor(red: 0.00, green: 0.67, blue: 0.91, alpha: 1)
        case "rider":          return NSColor(red: 0.46, green: 0.26, blue: 0.87, alpha: 1)
        case "phpstorm":       return NSColor(red: 0.55, green: 0.28, blue: 0.87, alpha: 1)
        case "clion":          return NSColor(red: 0.00, green: 0.67, blue: 0.44, alpha: 1)
        case "rubymine":       return NSColor(red: 0.87, green: 0.00, blue: 0.30, alpha: 1)
        case "subl":           return NSColor(red: 1.00, green: 0.59, blue: 0.00, alpha: 1)
        case "xcode":          return NSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        case "nova":           return NSColor(red: 0.35, green: 0.20, blue: 0.55, alpha: 1)
        case "bbedit":         return NSColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1)
        case "vim", "nvim":    return NSColor(red: 0.08, green: 0.57, blue: 0.24, alpha: 1)
        default:               return EditorLauncher.fallbackAccentColor
        }
    }

    /// 1–2 char glyph shown inside the button's icon tile.
    var badgeLetter: String {
        switch id {
        case "code":           return "VS"
        case "code-insiders":  return "VI"
        case "cursor":         return "C"
        case "windsurf":       return "W"
        case "zed":            return "Z"
        case "fleet":          return "F"
        case "idea":           return "IJ"
        case "webstorm":       return "WS"
        case "pycharm":        return "Py"
        case "goland":         return "Go"
        case "rider":          return "Rd"
        case "phpstorm":       return "Ph"
        case "clion":          return "CL"
        case "rubymine":       return "Rb"
        case "subl":           return "St"
        case "xcode":          return "X"
        case "nova":           return "N"
        case "bbedit":         return "BB"
        case "vim":            return "V"
        case "nvim":           return "NV"
        default:               return String(displayName.prefix(1)).uppercased()
        }
    }
}

enum AppTheme {
    static let bgPrimary = NSColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1.0)
    static let bgSecondary = NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
    static let bgTertiary = NSColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1.0)
    static let textPrimary = NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0)
    static let textSecondary = NSColor(red: 0.60, green: 0.60, blue: 0.65, alpha: 1.0)
    static let accent = NSColor(red: 0.45, green: 0.55, blue: 1.0, alpha: 1.0)
    static let border = NSColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1.0)
    static let statusBar = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)

    static let terminalFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let uiFont = NSFont.systemFont(ofSize: 12)
    static let uiFontSmall = NSFont.systemFont(ofSize: 11)
}
