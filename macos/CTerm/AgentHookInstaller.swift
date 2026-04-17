import Foundation

/// On-disk layout for agent hook files under the user's home directory.
enum AgentHookLayout {
    static let version = "1"

    static let homeDir: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".cterm")

    static var hooksDir: URL { homeDir.appendingPathComponent("hooks") }
    static var notifyScript: URL { hooksDir.appendingPathComponent("notify-hook.sh") }
    static var portFile: URL { hooksDir.appendingPathComponent("port") }

    static var claudeSettingsFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }

    static var codexHooksFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("hooks.json")
    }

    static var codexConfigFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }
}

enum AgentHookInstaller {
    /// Called once at app launch. Safe to re-run; all writes are idempotent.
    static func install() {
        do {
            try FileManager.default.createDirectory(
                at: AgentHookLayout.hooksDir,
                withIntermediateDirectories: true
            )
            writeNotifyScriptIfChanged()
            mergeClaudeSettings()
            mergeCodexHooks()
            ensureCodexHooksFeatureEnabled()
        } catch {
            NSLog("[agent-hook] install failed: \(error)")
        }
    }

    // MARK: - notify-hook.sh

    /// Bash script the agent's native hook invokes. It parses the hook JSON,
    /// extracts the event name, and POSTs it to the local hook server.
    private static let notifyScript = #"""
#!/bin/bash
# CTerm notify-hook v1
# Invoked by native agent hooks (Claude Code, Codex, OpenCode, etc.)
# Reads hook JSON from stdin or $1, extracts the event name, and forwards
# it to the local CTerm hook server on 127.0.0.1.

if [ -n "$1" ]; then
  INPUT="$1"
else
  INPUT=$(cat 2>/dev/null || true)
fi

# Skip entirely when the hook runs outside a CTerm-spawned terminal.
if [ -z "$CTERM_PANE_ID" ]; then
  exit 0
fi

# Claude Code puts the event in "hook_event_name"; Codex uses "type".
EVENT=$(printf '%s' "$INPUT" \
  | grep -oE '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed -E 's/.*"([^"]*)"$/\1/')

if [ -z "$EVENT" ]; then
  CODEX_TYPE=$(printf '%s' "$INPUT" \
    | grep -oE '"type"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"([^"]*)"$/\1/')
  case "$CODEX_TYPE" in
    agent-turn-complete|task_complete)
      EVENT="Stop"
      ;;
    task_started)
      EVENT="Start"
      ;;
    exec_approval_request|apply_patch_approval_request|request_user_input)
      EVENT="PermissionRequest"
      ;;
  esac
fi

if [ -z "$EVENT" ]; then
  exit 0
fi

# Prefer the port file (refreshed on each app launch) over the env var
# (frozen at shell spawn) so hooks keep working after CTerm restarts.
PORT=""
if [ -n "$CTERM_HOME_DIR" ] && [ -r "$CTERM_HOME_DIR/hooks/port" ]; then
  PORT=$(cat "$CTERM_HOME_DIR/hooks/port" 2>/dev/null)
fi
if [ -z "$PORT" ]; then
  PORT="${CTERM_PORT:-}"
fi
if [ -z "$PORT" ]; then
  exit 0
fi

# 1s connect / 2s total so a stalled server never blocks the agent.
curl -sG "http://127.0.0.1:${PORT}/hook/complete" \
  --connect-timeout 1 --max-time 2 \
  --data-urlencode "paneId=$CTERM_PANE_ID" \
  --data-urlencode "tabId=${CTERM_TAB_ID:-}" \
  --data-urlencode "workspaceId=${CTERM_WORKSPACE_ID:-}" \
  --data-urlencode "projectId=${CTERM_PROJECT_ID:-}" \
  --data-urlencode "provider=${CTERM_PROVIDER:-}" \
  --data-urlencode "eventType=$EVENT" \
  > /dev/null 2>&1

exit 0
"""#

    private static func writeNotifyScriptIfChanged() {
        let url = AgentHookLayout.notifyScript
        let desired = notifyScript
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == desired {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return
        }
        try? desired.data(using: .utf8)?.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: - ~/.claude/settings.json merge

    /// Hook command written into ~/.claude/settings.json. Resolved at runtime
    /// so one shared settings file works regardless of where CTerm is installed.
    private static func managedHookCommand() -> String {
        "[ -x \"$HOME/.cterm/hooks/notify-hook.sh\" ] && \"$HOME/.cterm/hooks/notify-hook.sh\" || true"
    }

    private static let claudeManagedEvents: [(event: String, matcher: String?)] = [
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("PostToolUse", "*"),
        ("Notification", "*")
    ]

    private static let codexManagedEvents: [(event: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("UserPromptSubmit", nil),
        ("Stop", nil)
    ]

    private static func mergeClaudeSettings() {
        mergeNestedHooksFile(
            path: AgentHookLayout.claudeSettingsFile,
            events: claudeManagedEvents
        )
    }

    private static func mergeCodexHooks() {
        mergeNestedHooksFile(
            path: AgentHookLayout.codexHooksFile,
            events: codexManagedEvents
        )
    }

    /// Both Claude Code and Codex use the same nested-hook JSON shape:
    ///   { "hooks": { "<EventName>": [ { "matcher"?, "hooks": [{"type":"command","command":"..."}] } ] } }
    /// We:
    ///   1. Parse existing file (preserving unrelated settings),
    ///   2. Strip any managed CTerm hook entries (identified by notify-hook.sh path),
    ///   3. Re-add current managed entries.
    private static func mergeNestedHooksFile(
        path: URL,
        events: [(event: String, matcher: String?)]
    ) {
        var root: [String: Any] = [:]

        if let data = try? Data(contentsOf: path),
           let parsed = try? JSONSerialization.jsonObject(with: data),
           let dict = parsed as? [String: Any] {
            root = dict
        }

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let command = managedHookCommand()
        let notifyMarker = "notify-hook.sh"

        for (eventName, matcher) in events {
            var existing = (hooks[eventName] as? [[String: Any]]) ?? []

            // Strip previously managed entries.
            existing = existing.compactMap { def -> [String: Any]? in
                guard var entry = def as [String: Any]? else { return def }
                if let children = entry["hooks"] as? [[String: Any]] {
                    let filtered = children.filter { child in
                        let cmd = (child["command"] as? String) ?? ""
                        return !cmd.contains(notifyMarker)
                    }
                    if filtered.isEmpty {
                        return nil
                    }
                    entry["hooks"] = filtered
                }
                return entry
            }

            var managedDef: [String: Any] = [
                "hooks": [["type": "command", "command": command]]
            ]
            if let matcher { managedDef["matcher"] = matcher }
            existing.append(managedDef)
            hooks[eventName] = existing
        }

        // Remove now-empty managed event keys (none in this pass, but
        // preserve user-defined keys untouched).
        root["hooks"] = hooks

        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }

        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let existing = try? Data(contentsOf: path), existing == data {
            return
        }
        try? data.write(to: path, options: .atomic)
    }

    // MARK: - Codex feature flag (codex_hooks)

    /// Codex only honors `~/.codex/hooks.json` when its `codex_hooks` feature
    /// flag is enabled (off by default, since it's marked "under development"
    /// upstream). Without this, the hooks we install above are silently
    /// ignored — so Start/Stop/PermissionRequest events never reach CTerm and
    /// Codex panes never show running state. We persist the flag in
    /// `~/.codex/config.toml` under `[features]` so the hook pipeline Just
    /// Works regardless of how the user launches codex.
    ///
    /// Approach: minimal, in-place TOML edit. We only touch the single line
    /// we care about; everything else in the file is preserved byte-for-byte.
    /// If the file already has the flag set (even commented out in a sensible
    /// way we can't easily parse, or set by another tool), we do nothing.
    private static func ensureCodexHooksFeatureEnabled() {
        let path = AgentHookLayout.codexConfigFile
        let existing = (try? String(contentsOf: path, encoding: .utf8)) ?? ""

        if codexHooksFlagIsTrue(in: existing) { return }

        let updated = applyCodexHooksFlag(to: existing)
        guard updated != existing else { return }

        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? updated.data(using: .utf8)?.write(to: path, options: .atomic)
    }

    /// Returns true if `[features] codex_hooks = true` is already present
    /// (any whitespace, any case on the boolean is unusual in TOML so we keep
    /// it strict — `true` only).
    static func codexHooksFlagIsTrue(in contents: String) -> Bool {
        guard let featuresTable = codexFeaturesTableContents(in: contents) else {
            return false
        }
        for rawLine in featuresTable.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("codex_hooks") {
                let afterKey = line.dropFirst("codex_hooks".count).trimmingCharacters(in: .whitespaces)
                if afterKey.hasPrefix("=") {
                    let value = afterKey.dropFirst().trimmingCharacters(in: .whitespaces)
                    return value == "true"
                }
            }
        }
        return false
    }

    /// Extracts the substring of `contents` belonging to the `[features]`
    /// table — from just after the header to the start of the next table
    /// header (or EOF). Returns nil if there is no `[features]` table.
    private static func codexFeaturesTableContents(in contents: String) -> Substring? {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        var capture = false
        var captured: [Substring] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if trimmed == "[features]" {
                    capture = true
                    continue
                }
                if capture { break }
                continue
            }
            if capture { captured.append(line) }
        }
        guard capture else { return nil }
        return Substring(captured.joined(separator: "\n"))
    }

    /// Ensures `codex_hooks = true` is present. Three cases:
    ///   1. `[features]` table exists and already contains a `codex_hooks`
    ///      line (any value) → replace that line in place. Avoids creating
    ///      duplicate keys, which TOML rejects.
    ///   2. `[features]` table exists, no `codex_hooks` key → insert right
    ///      after the header.
    ///   3. No `[features]` table → append one at EOF.
    static func applyCodexHooksFlag(to contents: String) -> String {
        var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var featuresHeaderIndex: Int? = nil
        var featuresEndIndex: Int = lines.count  // exclusive; defaults to EOF
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if featuresHeaderIndex == nil {
                if trimmed == "[features]" {
                    featuresHeaderIndex = i
                }
            } else if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                featuresEndIndex = i
                break
            }
        }

        if let headerIndex = featuresHeaderIndex {
            for i in (headerIndex + 1)..<featuresEndIndex {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { continue }
                if trimmed.hasPrefix("codex_hooks") {
                    lines[i] = "codex_hooks = true"
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert("codex_hooks = true", at: headerIndex + 1)
            return lines.joined(separator: "\n")
        }

        var trailing = contents
        if !trailing.isEmpty && !trailing.hasSuffix("\n") {
            trailing += "\n"
        }
        if !trailing.isEmpty {
            trailing += "\n"
        }
        trailing += "[features]\ncodex_hooks = true\n"
        return trailing
    }
}
