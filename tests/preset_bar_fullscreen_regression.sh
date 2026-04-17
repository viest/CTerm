#!/usr/bin/env bash
set -euo pipefail

preset_file="macos/CTerm/PresetBarView.swift"
main_file="macos/CTerm/MainWindowController.swift"

rg -n 'private static let leadingInsetWithTrafficLights: CGFloat = 80' "$preset_file" >/dev/null
rg -n 'private static let leadingInsetWithoutTrafficLights: CGFloat = 14' "$preset_file" >/dev/null
rg -n 'private var sidebarLeadingConstraint: NSLayoutConstraint!' "$preset_file" >/dev/null
rg -n 'sidebarLeadingConstraint = sidebarToggle\.leadingAnchor\.constraint\(' "$preset_file" >/dev/null
rg -n 'func setShowsTrafficLightSpacing\(_ showsTrafficLights: Bool\)' "$preset_file" >/dev/null
rg -n 'Self\.leadingInsetWithTrafficLights' "$preset_file" >/dev/null
rg -n 'Self\.leadingInsetWithoutTrafficLights' "$preset_file" >/dev/null
if rg -n 'sidebarToggle\.leadingAnchor\.constraint\(equalTo: leadingAnchor, constant: 80\)' "$preset_file" >/dev/null; then
  echo "preset bar should not hardcode traffic light spacing in fullscreen path" >&2
  exit 1
fi

rg -n 'updatePresetBarTrafficLightSpacing\(\)' "$main_file" >/dev/null
rg -n 'private func updatePresetBarTrafficLightSpacing\(showsTrafficLights: Bool\? = nil\)' "$main_file" >/dev/null
rg -n 'windowWillEnterFullScreen' "$main_file" >/dev/null
rg -n 'updatePresetBarTrafficLightSpacing\(showsTrafficLights: false\)' "$main_file" >/dev/null
rg -n 'windowWillExitFullScreen' "$main_file" >/dev/null
rg -n 'updatePresetBarTrafficLightSpacing\(showsTrafficLights: true\)' "$main_file" >/dev/null
