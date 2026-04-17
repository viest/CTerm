#!/usr/bin/env bash
set -euo pipefail

app_delegate="macos/CTerm/AppDelegate.swift"
about_file="macos/CTerm/AboutWindow.swift"

rg -n 'private var aboutWindow: AboutWindow\?' "$app_delegate" >/dev/null
rg -n 'let aboutItem = NSMenuItem\(title: "About CTerm", action: #selector\(showAbout\(_:\)\), keyEquivalent: ""\)' "$app_delegate" >/dev/null
rg -n '@objc func showAbout\(_ sender: Any\?\)' "$app_delegate" >/dev/null
! rg -n 'orderFrontStandardAboutPanel' "$app_delegate" >/dev/null

rg -n 'final class AboutWindow: NSObject, NSWindowDelegate' "$about_file" >/dev/null
rg -n 'window\.backgroundColor = AppTheme\.bgPrimary' "$about_file" >/dev/null
rg -n 'window\.appearance = NSAppearance\(named: \.darkAqua\)' "$about_file" >/dev/null
rg -n 'let topTitle = NSTextField\(labelWithString: "About"\)' "$about_file" >/dev/null
rg -n 'iconView\.image = NSApp\.applicationIconImage' "$about_file" >/dev/null
rg -n 'let nameLabel = NSTextField\(labelWithString: appName\(\)\)' "$about_file" >/dev/null
rg -n '\("Author", "viest"\)' "$about_file" >/dev/null
rg -n '\("Email", "wjx@php\.net"\)' "$about_file" >/dev/null
rg -n '\("Version", versionText\(\)\)' "$about_file" >/dev/null
rg -n '\("Built", buildTimeText\(\)\)' "$about_file" >/dev/null
rg -n 'private func makeInfoRow\(title: String, value: String\) -> NSView' "$about_file" >/dev/null
rg -n 'private func buildTimeText\(\) -> String' "$about_file" >/dev/null
rg -n 'Bundle\.main\.executableURL' "$about_file" >/dev/null
rg -n 'formatter\.dateFormat = "yyyy-MM-dd HH:mm:ss z"' "$about_file" >/dev/null
