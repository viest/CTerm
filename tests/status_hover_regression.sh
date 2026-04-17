#!/usr/bin/env bash
set -euo pipefail

hover_file="macos/CTerm/StatusHoverPopover.swift"
status_file="macos/CTerm/StatusBarView.swift"

rg -n 'final class StatusHoverPopoverManager' "$hover_file" >/dev/null
rg -n 'private let popover = NSPopover\(\)' "$hover_file" >/dev/null
rg -n 'popover\.contentSize = .*configure\(text: trimmed\)' "$hover_file" >/dev/null
rg -n 'final class StatusHoverLabel: NSTextField' "$hover_file" >/dev/null
rg -n 'NSVisualEffectView' "$hover_file" >/dev/null
rg -n 'private let minTextWidth: CGFloat = 120' "$hover_file" >/dev/null
rg -n 'private let maxTextWidth: CGFloat = 260' "$hover_file" >/dev/null
rg -n 'private var stackViewWidthConstraint: NSLayoutConstraint!' "$hover_file" >/dev/null
rg -n 'labelWidthConstraints' "$hover_file" >/dev/null
rg -n 'loadViewIfNeeded\(\)' "$hover_file" >/dev/null
rg -n 'stackViewWidthConstraint = stackView\.widthAnchor\.constraint\(equalToConstant: maxTextWidth\)' "$hover_file" >/dev/null
rg -n 'label\.widthAnchor\.constraint\(equalToConstant: textWidth\)' "$hover_file" >/dev/null
rg -n 'private func measuredTextWidth\(for lines: \[String\]\) -> CGFloat' "$hover_file" >/dev/null

rg -n 'private var performanceLabel: StatusHoverLabel!' "$status_file" >/dev/null
rg -n 'makeHoverLabel\(' "$status_file" >/dev/null
rg -n 'performanceLabel\.hoverText =' "$status_file" >/dev/null
rg -n 'StatusHoverPopoverManager\.shared\.scheduleShow' "$status_file" >/dev/null

if rg -n 'toolTip = monitor\?\.tooltip' "$status_file" >/dev/null; then
  echo "status bar monitor chips should not use legacy toolTip" >&2
  exit 1
fi

if rg -n 'performanceLabel\.toolTip =' "$status_file" >/dev/null; then
  echo "performance label should not use legacy toolTip" >&2
  exit 1
fi
