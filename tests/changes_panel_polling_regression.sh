#!/usr/bin/env bash
set -euo pipefail

file="macos/CTerm/ChangesPanel.swift"

rg -n 'private var refreshInFlight = false' "$file" >/dev/null
rg -n 'private var needsRefresh = false' "$file" >/dev/null
rg -n 'var onGitRepositoryMutated: \(\(\) -> Void\)\?' "$file" >/dev/null
rg -n 'override func viewDidMoveToWindow\(\)' "$file" >/dev/null
sed -n '/override func viewDidMoveToWindow/,/private func setupUI/p' "$file" | rg -n 'refreshIfNeeded\(\)' >/dev/null
rg -n 'private var shouldPollForChanges: Bool \{' "$file" >/dev/null
rg -n '!isHiddenOrHasHiddenAncestor' "$file" >/dev/null
rg -n 'func refreshIfNeeded\(force: Bool = false\)' "$file" >/dev/null
rg -n 'private func startRefreshIfNeeded\(\)' "$file" >/dev/null
rg -n 'guard shouldPollForChanges, !refreshInFlight, needsRefresh, let path = currentProjectPath else \{ return \}' "$file" >/dev/null
rg -n 'if self\.currentProjectPath == path \{' "$file" >/dev/null
rg -n 'let shouldStartAnotherRefresh = self\.currentProjectPath != nil && \(self\.needsRefresh \|\| self\.currentProjectPath != path\)' "$file" >/dev/null
rg -n 'onGitRepositoryMutated' "$file" >/dev/null
! rg -n 'refreshPollingInterval' "$file" >/dev/null
! rg -n 'refreshTimer' "$file" >/dev/null
! rg -n 'updateRefreshTimer\(\)' "$file" >/dev/null
! rg -n 'pollForChanges\(\)' "$file" >/dev/null
