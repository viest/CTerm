#!/usr/bin/env bash
set -euo pipefail

monitor_file="macos/CTerm/PerformanceMonitor.swift"
status_file="macos/CTerm/StatusBarView.swift"
main_file="macos/CTerm/MainWindowController.swift"

rg -n 'final class PerformanceMonitor' "$monitor_file" >/dev/null
rg -n 'task_threads' "$monitor_file" >/dev/null
rg -n 'thread_basic_info' "$monitor_file" >/dev/null
rg -n 'TASK_VM_INFO' "$monitor_file" >/dev/null
rg -n 'phys_footprint' "$monitor_file" >/dev/null
rg -n 'struct AppPerformanceSnapshot' "$monitor_file" >/dev/null

rg -n 'func updatePerformance' "$status_file" >/dev/null
rg -n 'CPU loading  MEM loading' "$status_file" >/dev/null
if rg -n 'func updateTerminalSize' "$status_file" >/dev/null; then
  echo "terminal size label should be removed from status bar" >&2
  exit 1
fi

rg -n 'performanceMonitor = PerformanceMonitor\(\)' "$main_file" >/dev/null
rg -n 'startPerformanceMonitoring\(\)' "$main_file" >/dev/null
rg -n 'withTimeInterval: 2' "$main_file" >/dev/null
