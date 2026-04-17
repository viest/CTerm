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

    init(name: String, path: String, editor: String = "code", description: String = "", pinned: Bool = false) {
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

enum EditorLauncher {
    private static let applicationNames: [String: String] = [
        "code": "Visual Studio Code",
        "cursor": "Cursor",
        "idea": "IntelliJ IDEA",
        "subl": "Sublime Text",
        "xcode": "Xcode",
    ]

    @discardableResult
    static func open(path: String, editor: String, line: Int? = nil) -> Bool {
        let normalizedEditor = editor.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEditor = normalizedEditor.isEmpty ? "code" : normalizedEditor
        var errors: [String] = []

        if resolvedEditor == "vim" {
            if let error = runVimInTerminal(path: path, line: line) {
                errors.append(error)
            } else {
                return true
            }
        } else if let command = commandArguments(for: resolvedEditor, path: path, line: line) {
            if let error = runProcess(
                executablePath: "/usr/bin/env",
                arguments: command,
                environment: cliEnvironment()
            ) {
                errors.append(error)
            } else {
                return true
            }
        }

        if let applicationName = applicationNames[resolvedEditor] {
            if let error = runProcess(
                executablePath: "/usr/bin/open",
                arguments: ["-a", applicationName, path]
            ) {
                errors.append(error)
            } else {
                return true
            }
        }

        if let error = runProcess(
            executablePath: "/usr/bin/open",
            arguments: ["-a", resolvedEditor, path]
        ) {
            errors.append(error)
        } else {
            return true
        }

        NSSound.beep()
        let details = errors.filter { !$0.isEmpty }.joined(separator: " | ")
        if details.isEmpty {
            NSLog("CTerm: failed to open \(path) in editor \(resolvedEditor)")
        } else {
            NSLog("CTerm: failed to open \(path) in editor \(resolvedEditor): \(details)")
        }
        return false
    }

    private static func commandArguments(for editor: String, path: String, line: Int?) -> [String]? {
        switch editor {
        case "code", "cursor":
            if let line {
                return [editor, "-g", "\(path):\(line)"]
            }
            return [editor, path]
        case "idea":
            if let line {
                return [editor, "--line", "\(line)", path]
            }
            return [editor, path]
        case "subl":
            if let line {
                return [editor, "\(path):\(line)"]
            }
            return [editor, path]
        case "xcode":
            if let line {
                return ["xed", "--line", "\(line)", path]
            }
            return ["xed", path]
        default:
            return nil
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

    private static func runVimInTerminal(path: String, line: Int?) -> String? {
        let escapedPath = shellQuoted(path)
        let command = line.map { "vim +\($0) \(escapedPath)" } ?? "vim \(escapedPath)"
        let scriptCommand = command
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
