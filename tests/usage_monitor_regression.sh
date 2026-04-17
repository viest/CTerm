#!/usr/bin/env bash
set -euo pipefail

monitor_file="macos/CTerm/UsageMonitor.swift"
status_file="macos/CTerm/StatusBarView.swift"
main_file="macos/CTerm/MainWindowController.swift"

rg -n 'final class UsageMonitor' "$monitor_file" >/dev/null
rg -n 'func loadCachedSnapshots\(\) -> \[String: ProviderMonitorSnapshot\]' "$monitor_file" >/dev/null
rg -n 'private let snapshotCacheURL: URL = \{' "$monitor_file" >/dev/null
rg -n 'private var codexLiveFileCache: \[String: CachedCodexLiveFileSnapshot\] = \[:\]' "$monitor_file" >/dev/null
rg -n 'private func liveCodexSnapshot\(for file: URL, recentSince: Date\) -> CodexLiveFileSnapshot\?' "$monitor_file" >/dev/null
rg -n 'private func saveCachedSnapshots\(_ snapshots: \[String: ProviderMonitorSnapshot\]\)' "$monitor_file" >/dev/null
rg -n '\.codex/sessions' "$monitor_file" >/dev/null
rg -n '\.claude/projects' "$monitor_file" >/dev/null
rg -n 'CodexBar history' "$monitor_file" >/dev/null
rg -n 'ProviderMonitorSnapshot\.formattedTokenCount\(tokenCount\)' "$monitor_file" >/dev/null
rg -n 'private static func formattedTokenCount\(_ count: Int64\) -> String' "$monitor_file" >/dev/null
rg -n 'private static func compactTokenCount\(_ count: Int64, divisor: Double, suffix: String\) -> String' "$monitor_file" >/dev/null
rg -n '1_000_000_000' "$monitor_file" >/dev/null
rg -n 'suffix: "B"' "$monitor_file" >/dev/null
rg -n '1_000_000' "$monitor_file" >/dev/null
rg -n 'suffix: "M"' "$monitor_file" >/dev/null
rg -n 'func updateProviderMonitoring' "$status_file" >/dev/null
rg -n 'private var providerMonitoringLoaded = false' "$status_file" >/dev/null
rg -n 'visibleWindows' "$status_file" >/dev/null
rg -n 'branchMonitorSeparator' "$status_file" >/dev/null
rg -n 'showsLeadingSeparator' "$status_file" >/dev/null
rg -n 'if !providerMonitoringLoaded' "$status_file" >/dev/null
rg -n 'let loadingText = "Usage data loading"' "$status_file" >/dev/null
rg -n 'AppTheme\.border\.setFill\(\)' "$status_file" >/dev/null
if rg -n 'providerColor\.withAlphaComponent\(0\.12\)\.cgColor' "$status_file" >/dev/null; then
  echo "status bar monitor items should not use filled backgrounds" >&2
  exit 1
fi
rg -n 'usageMonitor = UsageMonitor\(\)' "$main_file" >/dev/null
rg -n 'startUsageMonitoring\(\)' "$main_file" >/dev/null
rg -n 'withTimeInterval: 60' "$main_file" >/dev/null
rg -n 'private static let usageMonitorInitialRefreshDelay: TimeInterval = 15' "$main_file" >/dev/null
rg -n 'let cachedSnapshots = usageMonitor\.loadCachedSnapshots\(\)' "$main_file" >/dev/null
rg -n 'statusBar\.updateProviderMonitoring\(cachedSnapshots\)' "$main_file" >/dev/null
rg -n 'usageMonitorTimer\?\.fireDate = Date\(\)\.addingTimeInterval\(Self\.usageMonitorInitialRefreshDelay\)' "$main_file" >/dev/null

if sed -n '/private func startUsageMonitoring/,/private func startPerformanceMonitoring/p' "$main_file" | rg -n '^\s*usageMonitor\.refresh\(\)$' >/dev/null; then
  echo "usage monitoring should not trigger a full live refresh during startup" >&2
  exit 1
fi
