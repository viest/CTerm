import AppKit

class StatusBarView: NSView {
    private var branchIcon: NSTextField!
    private var branchLabel: NSTextField!
    private var branchMonitorSeparator: NSView!
    private var agentContainer: NSView!
    private var agentViews: [NSView] = []
    private var agentLoadingLabel: NSTextField?
    private var performanceLabel: StatusHoverLabel!

    private var perAgentUsage: [String: TokenUsage] = [:]
    private var providerMonitoring: [String: ProviderMonitorSnapshot] = [:]
    private var providerMonitoringLoaded = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = AppTheme.statusBar.cgColor

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = AppTheme.border.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        branchIcon = makeLabel("\u{2387}", size: 10, color: AppTheme.textSecondary)
        addSubview(branchIcon)

        branchLabel = makeLabel("main", size: 11, color: AppTheme.accent, mono: true)
        addSubview(branchLabel)

        branchMonitorSeparator = NSView()
        branchMonitorSeparator.wantsLayer = true
        branchMonitorSeparator.layer?.backgroundColor = AppTheme.border.cgColor
        branchMonitorSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(branchMonitorSeparator)

        agentContainer = NSView()
        agentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(agentContainer)

        performanceLabel = makeHoverLabel("CPU loading  MEM loading", size: 10, color: AppTheme.textSecondary, mono: true)
        performanceLabel.alignment = .right
        performanceLabel.hoverText = "CTerm performance data loading"
        addSubview(performanceLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),

            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),

            branchIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            branchIcon.centerYAnchor.constraint(equalTo: centerYAnchor),

            branchLabel.leadingAnchor.constraint(equalTo: branchIcon.trailingAnchor, constant: 3),
            branchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Match the chip-to-chip separator rhythm: `ChipLayout.sideGap`
            // of whitespace on each side of every 1pt divider, so the eye
            // walks a uniform beat across branch → | → Claude | Codex | Σ.
            // The right-hand pad comes from the first chip's leading side
            // gap, so we set the agentContainer constraint to 0.
            branchMonitorSeparator.leadingAnchor.constraint(equalTo: branchLabel.trailingAnchor, constant: ChipLayout.sideGap),
            branchMonitorSeparator.centerYAnchor.constraint(equalTo: centerYAnchor),
            branchMonitorSeparator.widthAnchor.constraint(equalToConstant: ChipLayout.separatorWidth),
            branchMonitorSeparator.heightAnchor.constraint(equalToConstant: 12),

            agentContainer.leadingAnchor.constraint(equalTo: branchMonitorSeparator.trailingAnchor, constant: 0),
            agentContainer.trailingAnchor.constraint(equalTo: performanceLabel.leadingAnchor, constant: -14),
            agentContainer.topAnchor.constraint(equalTo: topAnchor),
            agentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            performanceLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            performanceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            performanceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeLabel(_ text: String, size: CGFloat, color: NSColor, mono: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func makeHoverLabel(_ text: String, size: CGFloat, color: NSColor, mono: Bool = false) -> StatusHoverLabel {
        let l = StatusHoverLabel(labelWithString: text)
        l.font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.systemFont(ofSize: size)
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    // MARK: - Public API

    /// Set usage data; called whenever token tracker updates
    var usage: TokenUsage = TokenUsage() {
        didSet {} // kept for compat
    }

    func updateAllAgentUsage(_ usageMap: [String: TokenUsage]) {
        perAgentUsage = usageMap
        rebuildAgentChips()
    }

    func updateProviderMonitoring(_ monitoring: [String: ProviderMonitorSnapshot]) {
        providerMonitoringLoaded = true
        providerMonitoring = monitoring
        rebuildAgentChips()
    }

    func updateBranch(_ branch: String) {
        branchLabel.stringValue = branch
    }

    func updatePerformance(_ snapshot: AppPerformanceSnapshot) {
        performanceLabel.stringValue = snapshot.statusText
        performanceLabel.hoverText = snapshot.tooltip
    }

    func updateProvider(_ provider: String) {
        // Ensure this provider appears even with 0 usage
        if perAgentUsage[provider] == nil {
            perAgentUsage[provider] = TokenUsage()
            rebuildAgentChips()
        }
    }

    // MARK: - Agent chips

    private func rebuildAgentChips() {
        for v in agentViews { v.removeFromSuperview() }
        agentViews = []
        agentLoadingLabel?.removeFromSuperview()
        agentLoadingLabel = nil

        if !providerMonitoringLoaded {
            let loadingText = "Usage data loading"
            let loadingLabel = makeLabel(loadingText, size: 10, color: AppTheme.textSecondary, mono: true)
            let width = ceil((loadingText as NSString).size(withAttributes: [.font: loadingLabel.font as Any]).width)
            loadingLabel.frame = NSRect(x: 0, y: 4, width: width, height: 16)
            agentContainer.addSubview(loadingLabel)
            agentLoadingLabel = loadingLabel
            return
        }

        let sortedProviders = Set(perAgentUsage.keys).union(providerMonitoring.keys).sorted()
        var x: CGFloat = 0
        let chipH: CGFloat = 18
        let y: CGFloat = 3

        // Chips sit flush against each other. The separator drawn at x=0 of
        // each chip-with-separator is visually centered because both chips
        // use the same side-padding (see ChipLayout.sideGap), so there's an
        // equal `sideGap` of whitespace on either side of the 1pt line.
        for (index, provider) in sortedProviders.enumerated() {
            let chip = AgentUsageChip(
                provider: provider,
                usage: perAgentUsage[provider],
                monitor: providerMonitoring[provider],
                showsLeadingSeparator: index > 0
            )
            let w = chip.intrinsicContentSize.width
            chip.frame = NSRect(x: x, y: y, width: w, height: chipH)
            agentContainer.addSubview(chip)
            agentViews.append(chip)
            x += w
        }

        if let totals = aggregateTokenTotals() {
            let chip = AgentTotalsChip(totals: totals, showsLeadingSeparator: !agentViews.isEmpty)
            let w = chip.intrinsicContentSize.width
            chip.frame = NSRect(x: x, y: y, width: w, height: chipH)
            agentContainer.addSubview(chip)
            agentViews.append(chip)
        }
    }

    /// Sums per-day token counts across all providers' snapshots. Returns
    /// nil when there's no snapshot data at all (avoids showing zeros while
    /// usage is still loading), or when every bucket is empty.
    private func aggregateTokenTotals() -> AgentTotalsChip.Totals? {
        guard !providerMonitoring.isEmpty else { return nil }

        var today: Int64 = 0
        var sevenDays: Int64 = 0
        var thirtyDays: Int64 = 0

        for snapshot in providerMonitoring.values {
            let daily = snapshot.dailyUsage
            if let first = daily.first {
                today += first.tokenCount
            }
            for entry in daily.prefix(7) { sevenDays += entry.tokenCount }
            for entry in daily.prefix(30) { thirtyDays += entry.tokenCount }
        }

        if today == 0 && sevenDays == 0 && thirtyDays == 0 {
            return nil
        }
        return AgentTotalsChip.Totals(today: today, sevenDays: sevenDays, thirtyDays: thirtyDays)
    }
}

// MARK: - All-agents aggregate chip

/// Shows today / 7d / 30d total tokens summed across every agent. Rendered
/// to the right of the per-agent chips with a leading separator, matching
/// `AgentUsageChip`'s visual language so the status bar reads as one row.
final class AgentTotalsChip: NSView {
    struct Totals {
        let today: Int64
        let sevenDays: Int64
        let thirtyDays: Int64
    }

    private let totals: Totals
    private let showsLeadingSeparator: Bool
    private var trackingAreaRef: NSTrackingArea?

    init(totals: Totals, showsLeadingSeparator: Bool) {
        self.totals = totals
        self.showsLeadingSeparator = showsLeadingSeparator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        StatusHoverPopoverManager.shared.scheduleShow(text: tooltipText, relativeTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        StatusHoverPopoverManager.shared.close(relativeTo: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            StatusHoverPopoverManager.shared.close(relativeTo: self)
        }
    }

    override var intrinsicContentSize: NSSize {
        let segments = contentSegments()
        let textWidth = segments.reduce(CGFloat(0)) { $0 + ($1.text as NSString).size(withAttributes: [.font: $1.font]).width }
        let gapCount = max(0, segments.count - 1)
        let contentWidth = textWidth + CGFloat(gapCount) * ChipLayout.interSegmentGap
        return NSSize(
            width: ChipLayout.intrinsicWidth(contentWidth: contentWidth, showsSeparator: showsLeadingSeparator),
            height: ChipLayout.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChipLayout.drawSeparatorIfNeeded(showsLeadingSeparator, in: bounds)

        let textY = (bounds.height - 13) / 2
        var x: CGFloat = ChipLayout.contentLeadingX(showsSeparator: showsLeadingSeparator)
        for segment in contentSegments() {
            let attrs: [NSAttributedString.Key: Any] = [.font: segment.font, .foregroundColor: segment.color]
            let string = segment.text as NSString
            string.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
            x += string.size(withAttributes: attrs).width + ChipLayout.interSegmentGap
        }
    }

    private func contentSegments() -> [(text: String, color: NSColor, font: NSFont)] {
        let labelFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let numFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        return [
            ("Σ",              AppTheme.textPrimary,   labelFont),
            ("Today",          AppTheme.textSecondary, labelFont),
            (formatTokens(totals.today),      AppTheme.textPrimary, numFont),
            ("7d",             AppTheme.textSecondary, labelFont),
            (formatTokens(totals.sevenDays),  AppTheme.textPrimary, numFont),
            ("30d",            AppTheme.textSecondary, labelFont),
            (formatTokens(totals.thirtyDays), AppTheme.textPrimary, numFont),
        ]
    }

    private func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private var tooltipText: String {
        [
            "All agents — token totals",
            "Today: \(formatFullTokens(totals.today))",
            "Past 7 days: \(formatFullTokens(totals.sevenDays))",
            "Past 30 days: \(formatFullTokens(totals.thirtyDays))",
        ].joined(separator: "\n")
    }

    private func formatFullTokens(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

// MARK: - Shared chip layout metrics
//
// Centralizes every position and padding used by the status-bar chips so
// that all chips — agent, totals, anything added later — line up on the
// same grid. The invariant the eye cares about is: the whitespace to the
// left of a separator (trailing pad of the previous chip) equals the
// whitespace to its right (leading pad of this chip before content). Both
// are `sideGap`.

private enum ChipLayout {
    static let height: CGFloat = 18
    static let sideGap: CGFloat = 7
    static let separatorWidth: CGFloat = 1
    static let interSegmentGap: CGFloat = 5
    static let fontSize: CGFloat = 9.5

    static func contentLeadingX(showsSeparator: Bool) -> CGFloat {
        showsSeparator ? (separatorWidth + sideGap) : sideGap
    }

    static func drawSeparatorIfNeeded(_ showsSeparator: Bool, in bounds: NSRect) {
        guard showsSeparator else { return }
        AppTheme.border.setFill()
        NSRect(x: 0, y: 3, width: separatorWidth, height: bounds.height - 6).fill()
    }

    static func intrinsicWidth(contentWidth: CGFloat, showsSeparator: Bool) -> CGFloat {
        ceil(contentLeadingX(showsSeparator: showsSeparator) + contentWidth + sideGap)
    }
}

// MARK: - Per-agent usage chip

class AgentUsageChip: NSView {
    let provider: String
    let usage: TokenUsage?
    let monitor: ProviderMonitorSnapshot?
    private let providerColor: NSColor
    private let displayName: String
    private let showsLeadingSeparator: Bool
    private var trackingAreaRef: NSTrackingArea?

    init(provider: String, usage: TokenUsage?, monitor: ProviderMonitorSnapshot?, showsLeadingSeparator: Bool) {
        self.provider = provider
        self.usage = usage
        self.monitor = monitor
        self.providerColor = Self.color(for: provider)
        self.displayName = Self.shortName(for: provider)
        self.showsLeadingSeparator = showsLeadingSeparator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        StatusHoverPopoverManager.shared.scheduleShow(text: monitor?.tooltip, relativeTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        StatusHoverPopoverManager.shared.close(relativeTo: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            StatusHoverPopoverManager.shared.close(relativeTo: self)
        }
    }

    override var intrinsicContentSize: NSSize {
        let segments = contentSegments()
        let textWidth = segments.reduce(CGFloat(0)) { $0 + ($1.text as NSString).size(withAttributes: [.font: $1.font]).width }
        let gapCount = max(0, segments.count - 1)
        let contentWidth = textWidth + CGFloat(gapCount) * ChipLayout.interSegmentGap
        return NSSize(
            width: ChipLayout.intrinsicWidth(contentWidth: contentWidth, showsSeparator: showsLeadingSeparator),
            height: ChipLayout.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChipLayout.drawSeparatorIfNeeded(showsLeadingSeparator, in: bounds)

        let textY = (bounds.height - 13) / 2
        var x: CGFloat = ChipLayout.contentLeadingX(showsSeparator: showsLeadingSeparator)
        for segment in contentSegments() {
            let attrs: [NSAttributedString.Key: Any] = [.font: segment.font, .foregroundColor: segment.color]
            let string = segment.text as NSString
            string.draw(at: NSPoint(x: x, y: textY), withAttributes: attrs)
            x += string.size(withAttributes: attrs).width + ChipLayout.interSegmentGap
        }
    }

    private func contentSegments() -> [(text: String, color: NSColor, font: NSFont)] {
        let nameFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let numFont = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
        var segments: [(String, NSColor, NSFont)] = [(displayName, providerColor, nameFont)]

        if let monitor {
            // Window labels like "5h" / "7d" are static context — render
            // them in secondary gray so the eye lands on the percentage,
            // which is the value that actually changes and carries the
            // threshold color.
            for window in monitor.visibleWindows {
                segments.append((window.compactName, AppTheme.textSecondary, numFont))
                segments.append(("\(Int(window.usedPercent.rounded()))%", color(forWindow: window.usedPercent), numFont))
            }

            if monitor.costUSD > 0.000_001 || usage == nil {
                segments.append((monitor.formattedCost, color(forCost: monitor.costUSD), numFont))
            } else if let usage {
                segments.append((usage.formattedCost, color(forCost: usage.costUSD), numFont))
            }

            if monitor.visibleWindows.isEmpty, let usage {
                segments.append((formatTokens(usage.totalTokens), AppTheme.textPrimary, numFont))
            }
            return segments
        }

        if let usage {
            segments.append((formatTokens(usage.totalTokens), AppTheme.textPrimary, numFont))
            segments.append((usage.formattedCost, color(forCost: usage.costUSD), numFont))
        }

        return segments
    }

    private func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func color(forWindow percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 70 { return .systemOrange }
        return AppTheme.textPrimary
    }

    private func color(forCost cost: Double) -> NSColor {
        if cost >= 20 { return .systemRed }
        if cost >= 5 { return .systemOrange }
        return .systemGreen
    }

    private static func color(for provider: String) -> NSColor {
        switch provider {
        case "anthropic":  return NSColor(red: 0.91, green: 0.52, blue: 0.24, alpha: 1)
        case "openai":     return NSColor(red: 0.20, green: 0.80, blue: 0.50, alpha: 1)
        case "google":     return NSColor(red: 0.30, green: 0.52, blue: 1.00, alpha: 1)
        case "github":     return NSColor(red: 0.58, green: 0.58, blue: 0.68, alpha: 1)
        case "multiple":   return NSColor(red: 0.65, green: 0.42, blue: 0.90, alpha: 1)
        default:           return AppTheme.textSecondary
        }
    }

    private static func shortName(for provider: String) -> String {
        switch provider {
        case "anthropic": return "Claude"
        case "openai":    return "Codex"
        case "google":    return "Gemini"
        case "github":    return "Copilot"
        case "multiple":  return "Aider"
        default:          return provider
        }
    }
}
