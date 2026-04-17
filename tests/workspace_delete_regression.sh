#!/usr/bin/env bash
set -euo pipefail

controller="macos/CTerm/MainWindowController.swift"

rg -n 'func deleteWorkspace\(_ workspace: WorkspaceItem, deleteBranch: Bool\)' "$controller" >/dev/null
rg -n 'private func performWorkspaceDeletion\(_ workspace: WorkspaceItem, deleteBranch: Bool, projectPath: String\?\)' "$controller" >/dev/null
rg -n 'func runGit\(arguments: \[String\]\)' "$controller" >/dev/null
rg -n 'runGit\(arguments: \["worktree", "remove", workspace\.worktreePath, "--force"\]\)' "$controller" >/dev/null
rg -n 'runGit\(arguments: \["worktree", "prune"\]\)' "$controller" >/dev/null
rg -n 'runGit\(arguments: \["branch", "-D", workspace\.branchName\]\)' "$controller" >/dev/null

if rg -n 'branch", "-d", workspace\.branchName' "$controller" >/dev/null; then
  echo "workspace deletion should force-delete the branch with -D" >&2
  exit 1
fi
