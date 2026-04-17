import Foundation

enum AgentHookEvent: String {
    case start = "Start"
    case stop = "Stop"
    case permissionRequest = "PermissionRequest"
}

enum AgentHookEventMapper {
    static func map(_ raw: String?) -> AgentHookEvent? {
        guard let raw, !raw.isEmpty else { return nil }

        switch raw {
        case "Start",
             "SessionStart", "sessionStart", "session_start",
             "UserPromptSubmit", "userPromptSubmit", "user_prompt_submit",
             "PostToolUse", "postToolUse", "post_tool_use",
             "PostToolUseFailure", "postToolUseFailure", "post_tool_use_failure",
             "BeforeAgent", "AfterTool",
             "task_started":
            return .start

        case "Stop", "stop",
             "SessionEnd", "sessionEnd", "session_end",
             "AfterAgent",
             "agent-turn-complete", "task_complete":
            return .stop

        case "PermissionRequest",
             "Notification",
             "PreToolUse", "preToolUse", "pre_tool_use",
             "exec_approval_request",
             "apply_patch_approval_request",
             "request_user_input":
            return .permissionRequest

        default:
            return nil
        }
    }
}
