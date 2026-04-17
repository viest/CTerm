import Foundation

/// Manages workspace lifecycle scripts from .cterm/config.json.
class WorkspaceLifecycle {
    static let shared = WorkspaceLifecycle()
    private init() {}

    // MARK: - Config

    func loadConfig(projectPath: String) -> WorkspaceConfig? {
        let configPath = (projectPath as NSString).appendingPathComponent(".cterm/config.json")
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return nil }
        return try? JSONDecoder().decode(WorkspaceConfig.self, from: data)
    }

    // MARK: - Run Scripts

    func runSetup(projectPath: String, workspaceName: String, workingDir: String, completion: @escaping (Bool) -> Void) {
        guard let config = loadConfig(projectPath: projectPath), let commands = config.setup, !commands.isEmpty else {
            completion(true)
            return
        }
        runCommands(commands, projectPath: projectPath, workspaceName: workspaceName, workingDir: workingDir, completion: completion)
    }

    func runTeardown(projectPath: String, workspaceName: String, workingDir: String, completion: @escaping (Bool) -> Void) {
        guard let config = loadConfig(projectPath: projectPath), let commands = config.teardown, !commands.isEmpty else {
            completion(true)
            return
        }
        runCommands(commands, projectPath: projectPath, workspaceName: workspaceName, workingDir: workingDir, completion: completion)
    }

    func runScripts(projectPath: String, workspaceName: String, workingDir: String, completion: @escaping (Bool) -> Void) {
        guard let config = loadConfig(projectPath: projectPath), let commands = config.run, !commands.isEmpty else {
            completion(true)
            return
        }
        runCommands(commands, projectPath: projectPath, workspaceName: workspaceName, workingDir: workingDir, completion: completion)
    }

    // MARK: - Internal

    private func runCommands(_ commands: [String], projectPath: String, workspaceName: String,
                             workingDir: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            var allSuccess = true

            for cmd in commands {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", cmd]
                process.currentDirectoryURL = URL(fileURLWithPath: workingDir)

                // Inject environment variables
                var env = ProcessInfo.processInfo.environment
                env["CTERM_ROOT_PATH"] = projectPath
                env["CTERM_WORKSPACE_NAME"] = workspaceName
                env["CTERM_WORKSPACE_PATH"] = workingDir
                process.environment = env

                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        allSuccess = false
                    }
                } catch {
                    allSuccess = false
                }
            }

            DispatchQueue.main.async {
                completion(allSuccess)
            }
        }
    }

    /// Run commands in a terminal by sending them as text input.
    /// This allows the user to see the output in the terminal.
    func sendCommandsToTerminal(commands: [String], surface: ghostty_surface_t) {
        var delay: Double = 0.5
        for cmd in commands {
            let input = cmd + "\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ghostty_surface_text(surface, input, UInt(input.utf8.count))
            }
            delay += 0.3
        }
    }
}
