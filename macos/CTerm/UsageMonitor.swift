import Foundation

struct ProviderMonitorWindow: Codable {
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int
    let capturedAt: Date?

    var shortLabel: String {
        "\(compactName) \(Int(usedPercent.rounded()))%"
    }

    var detailLabel: String {
        if let resetsAt {
            return "\(displayName): \(Int(usedPercent.rounded()))% (resets \(ProviderMonitorWindow.detailTimeFormatter.string(from: resetsAt)))"
        }
        return "\(displayName): \(Int(usedPercent.rounded()))%"
    }

    var compactName: String {
        let lower = name.lowercased()
        switch lower {
        case "session": return "5h"
        case "weekly":  return "7d"
        case "opus":    return "Op"
        default: break
        }
        // Only fall back to windowMinutes when no specific name is set —
        // otherwise e.g. the "opus" weekly bucket (10080 minutes) gets
        // mislabelled as the generic "7d" weekly.
        if lower.isEmpty {
            if windowMinutes == 300 { return "5h" }
            if windowMinutes == 10_080 { return "7d" }
        }
        if windowMinutes >= 1_440 { return "\(max(1, windowMinutes / 1_440))d" }
        if windowMinutes >= 60 { return "\(max(1, windowMinutes / 60))h" }
        return "\(windowMinutes)m"
    }

    var displayName: String {
        let lower = name.lowercased()
        switch lower {
        case "session": return "Session"
        case "weekly":  return "Weekly"
        case "opus":    return "Opus"
        case "":
            if windowMinutes == 300 { return "Session" }
            if windowMinutes == 10_080 { return "Weekly" }
            return compactName
        default:
            return name.capitalized
        }
    }

    private static let detailTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

struct DailyUsage: Codable {
    /// Midnight (local time) of the day this bucket represents.
    let date: Date
    let costUSD: Double
    let tokenCount: Int64
}

struct ProviderMonitorSnapshot: Codable {
    let provider: String
    let windows: [ProviderMonitorWindow]
    let visibleWindows: [ProviderMonitorWindow]
    let costUSD: Double
    let tokenCount: Int64
    let costWindowMinutes: Int?
    let updatedAt: Date?
    let source: String
    /// Per-day usage covering today and the previous
    /// `UsageMonitor.dailyBucketDayCount - 1` days, newest first. Always
    /// dense (empty days are zero-filled) so consumers can sum slices by
    /// position without guarding. The tooltip renders only the first 7;
    /// the status bar sums 1 / 7 / 30 entries for the today / 7d / 30d
    /// aggregate across all agents.
    let dailyUsage: [DailyUsage]

    init(
        provider: String,
        windows: [ProviderMonitorWindow],
        visibleWindows: [ProviderMonitorWindow],
        costUSD: Double,
        tokenCount: Int64,
        costWindowMinutes: Int?,
        updatedAt: Date?,
        source: String,
        dailyUsage: [DailyUsage] = []
    ) {
        self.provider = provider
        self.windows = windows
        self.visibleWindows = visibleWindows
        self.costUSD = costUSD
        self.tokenCount = tokenCount
        self.costWindowMinutes = costWindowMinutes
        self.updatedAt = updatedAt
        self.source = source
        self.dailyUsage = dailyUsage
    }

    /// Decodes snapshots written by older app versions (which did not yet
    /// serialize `dailyUsage`) by treating the missing field as empty. The
    /// next `UsageMonitor.refresh()` will repopulate it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        windows = try container.decode([ProviderMonitorWindow].self, forKey: .windows)
        visibleWindows = try container.decode([ProviderMonitorWindow].self, forKey: .visibleWindows)
        costUSD = try container.decode(Double.self, forKey: .costUSD)
        tokenCount = try container.decode(Int64.self, forKey: .tokenCount)
        costWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .costWindowMinutes)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        source = try container.decode(String.self, forKey: .source)
        dailyUsage = try container.decodeIfPresent([DailyUsage].self, forKey: .dailyUsage) ?? []
    }

    var formattedCost: String {
        if costUSD >= 100 {
            return String(format: "$%.0f", costUSD)
        }
        if costUSD >= 1 {
            return String(format: "$%.2f", costUSD)
        }
        return String(format: "$%.3f", costUSD)
    }

    var tooltip: String {
        var lines = [ProviderMonitorSnapshot.providerName(for: provider)]
        if !windows.isEmpty {
            lines.append(contentsOf: windows.map(\.detailLabel))
        }

        let tokenLabel = ProviderMonitorSnapshot.formattedTokenCount(tokenCount)
        if let costWindowMinutes {
            lines.append("Local cost (\(ProviderMonitorSnapshot.windowLabel(minutes: costWindowMinutes))): \(formattedCost)")
            lines.append("Local tokens (\(ProviderMonitorSnapshot.windowLabel(minutes: costWindowMinutes))): \(tokenLabel)")
        } else {
            lines.append("Local cost: \(formattedCost)")
            lines.append("Local tokens: \(tokenLabel)")
        }

        if !dailyUsage.isEmpty {
            lines.append("")
            lines.append("Past 7 days:")
            for entry in dailyUsage.prefix(7) {
                lines.append("  " + ProviderMonitorSnapshot.formatDailyUsageLine(entry))
            }
        }

        lines.append("Source: \(source)")
        return lines.joined(separator: "\n")
    }

    private static let dailyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    private static func formatDailyUsageLine(_ entry: DailyUsage) -> String {
        let dateLabel = dailyDateFormatter.string(from: entry.date)
        guard entry.tokenCount > 0 || entry.costUSD > 0 else {
            return "\(dateLabel)  —"
        }
        let tokens = formattedTokenCount(entry.tokenCount)
        let cost = formatCost(entry.costUSD)
        return "\(dateLabel)  \(tokens) · \(cost)"
    }

    private static func formatCost(_ costUSD: Double) -> String {
        if costUSD >= 100 { return String(format: "$%.0f", costUSD) }
        if costUSD >= 1 { return String(format: "$%.2f", costUSD) }
        if costUSD >= 0.01 { return String(format: "$%.2f", costUSD) }
        return String(format: "$%.3f", costUSD)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func formattedTokenCount(_ count: Int64) -> String {
        let absoluteCount = abs(Double(count))
        if absoluteCount >= 1_000_000_000 {
            return compactTokenCount(count, divisor: 1_000_000_000, suffix: "B")
        }
        if absoluteCount >= 1_000_000 {
            return compactTokenCount(count, divisor: 1_000_000, suffix: "M")
        }
        return integerFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func compactTokenCount(_ count: Int64, divisor: Double, suffix: String) -> String {
        let scaled = Double(count) / divisor
        if abs(scaled) >= 10 {
            return "\(Int(scaled.rounded()))\(suffix)"
        }
        return String(format: "%.1f%@", scaled, suffix)
            .replacingOccurrences(of: ".0\(suffix)", with: suffix)
    }

    private static func providerName(for provider: String) -> String {
        switch provider {
        case "anthropic": return "Claude"
        case "openai": return "Codex"
        case "google": return "Gemini"
        case "github": return "Copilot"
        case "multiple": return "Aider"
        default: return provider
        }
    }

    private static func windowLabel(minutes: Int) -> String {
        if minutes == 300 { return "5h" }
        if minutes == 10_080 { return "7d" }
        if minutes >= 1_440 { return "\(minutes / 1_440)d" }
        if minutes >= 60 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

final class UsageMonitor {
    private struct SnapshotCachePayload: Codable {
        let snapshots: [ProviderMonitorSnapshot]
    }

    private struct TimestampedUsage {
        let timestamp: Date
        let costUSD: Double
        let tokenCount: Int64
    }

    private struct CodexUsageEventSummary {
        let timestamp: Date
        let usage: CodexTokenUsage
        let model: String
    }

    private struct CodexLiveFileSnapshot {
        let latestRateLimits: CodexRateLimits?
        let latestRateLimitTimestamp: Date?
        let latestTimestamp: Date?
        let recentEvents: [CodexUsageEventSummary]
    }

    private struct CachedCodexLiveFileSnapshot {
        let contentModificationDate: Date
        let fileSize: UInt64
        let snapshot: CodexLiveFileSnapshot
    }

    /// How many days of per-day usage we compute. The tooltip only renders
    /// the most recent 7, but the status bar aggregates today / 7d / 30d
    /// from the same array, so we keep the full 30 around.
    static let dailyBucketDayCount: Int = 30

    /// How far back we parse agent transcripts. Matches
    /// `dailyBucketDayCount` so a 30d aggregate never under-reports for a
    /// user who hasn't touched a transcript in weeks.
    private static let codexEventCacheLookback: TimeInterval =
        TimeInterval(dailyBucketDayCount) * 24 * 60 * 60

    /// Midnight (local time) at the start of the daily-bucket window —
    /// i.e. the start of `today minus (dailyBucketDayCount - 1)`.
    private static func dailyBucketStart(now: Date) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: -(dailyBucketDayCount - 1), to: todayStart)
            ?? todayStart
    }

    /// Collapses a list of (timestamp, cost, tokens) into exactly
    /// `dailyBucketDayCount` daily buckets, newest first. Empty days are
    /// returned as zeroed entries so the tooltip and aggregate sums can
    /// index by position without guarding.
    private static func bucketDailyUsage(_ events: [TimestampedUsage], now: Date) -> [DailyUsage] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        var days: [Date] = []
        for offset in 0..<dailyBucketDayCount {
            if let day = cal.date(byAdding: .day, value: -offset, to: todayStart) {
                days.append(day)
            }
        }
        let windowStart = days.last ?? todayStart

        var costByDay: [Date: Double] = [:]
        var tokensByDay: [Date: Int64] = [:]
        for event in events where event.timestamp >= windowStart {
            let day = cal.startOfDay(for: event.timestamp)
            costByDay[day, default: 0] += event.costUSD
            tokensByDay[day, default: 0] += event.tokenCount
        }

        return days.map { day in
            DailyUsage(
                date: day,
                costUSD: costByDay[day] ?? 0,
                tokenCount: tokensByDay[day] ?? 0
            )
        }
    }

    var onSnapshotUpdated: (([String: ProviderMonitorSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "cterm.usage-monitor", qos: .utility)
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let snapshotCacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CTerm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("provider-monitor-cache.json")
    }()
    private var codexLiveFileCache: [String: CachedCodexLiveFileSnapshot] = [:]

    func loadCachedSnapshots() -> [String: ProviderMonitorSnapshot] {
        guard let data = try? Data(contentsOf: snapshotCacheURL),
              let payload = try? JSONDecoder().decode(SnapshotCachePayload.self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: payload.snapshots.map { ($0.provider, $0) })
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let snapshots = self.collectSnapshots()
            self.saveCachedSnapshots(snapshots)
            DispatchQueue.main.async {
                self.onSnapshotUpdated?(snapshots)
            }
        }
    }

    private func collectSnapshots(now: Date = Date()) -> [String: ProviderMonitorSnapshot] {
        var snapshots: [String: ProviderMonitorSnapshot] = [:]

        if let codex = loadCodexSnapshot(now: now) {
            snapshots[codex.provider] = codex
        }
        if let claude = loadClaudeSnapshot(now: now) {
            snapshots[claude.provider] = claude
        }

        return snapshots
    }

    private func loadCodexSnapshot(now: Date) -> ProviderMonitorSnapshot? {
        let fallbackWindows = loadHistoryWindows(from: codexBarHistoryURL())
        let live = loadLiveCodexSnapshot(now: now)
        let windows = live?.windows ?? fallbackWindows

        guard !windows.isEmpty || live != nil else { return nil }

        return ProviderMonitorSnapshot(
            provider: "openai",
            windows: windows,
            visibleWindows: selectVisibleWindows(from: windows),
            costUSD: live?.costUSD ?? 0,
            tokenCount: live?.tokenCount ?? 0,
            costWindowMinutes: live?.costWindowMinutes,
            updatedAt: live?.updatedAt ?? windows.compactMap(\.capturedAt).max(),
            source: live?.source ?? "CodexBar history",
            dailyUsage: Self.bucketDailyUsage(live?.dailyEvents ?? [], now: now)
        )
    }

    private func loadClaudeSnapshot(now: Date) -> ProviderMonitorSnapshot? {
        // Claude's history file also records an "opus" bucket that shares the
        // 10080-minute weekly window. We only surface Session (5h) and Weekly
        // (7d) in the UI, so drop opus before it flows into tooltip/chip.
        let windows = loadHistoryWindows(from: claudeHistoryURL())
            .filter { $0.name.lowercased() != "opus" }
        guard !windows.isEmpty else { return nil }

        let costWindow = preferredCostWindow(from: windows)
        let costWindowStart = startDate(for: costWindow, now: now)
        let dailyWindowStart = Self.dailyBucketStart(now: now)
        let summary = loadClaudeUsageSummary(
            costWindowStart: costWindowStart,
            dailyWindowStart: dailyWindowStart
        )

        return ProviderMonitorSnapshot(
            provider: "anthropic",
            windows: windows,
            visibleWindows: selectVisibleWindows(from: windows),
            costUSD: summary.costUSD,
            tokenCount: summary.tokenCount,
            costWindowMinutes: costWindow?.windowMinutes,
            updatedAt: summary.updatedAt ?? windows.compactMap(\.capturedAt).max(),
            source: "Claude transcripts",
            dailyUsage: Self.bucketDailyUsage(summary.dailyEvents, now: now)
        )
    }

    private func loadLiveCodexSnapshot(now: Date) -> (windows: [ProviderMonitorWindow], costUSD: Double, tokenCount: Int64, costWindowMinutes: Int?, updatedAt: Date?, source: String, dailyEvents: [TimestampedUsage])? {
        let sessionsRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions", isDirectory: true)
        let files = recentJSONLFiles(in: sessionsRoot, modifiedSince: now.addingTimeInterval(-10 * 24 * 60 * 60))
        guard !files.isEmpty else { return nil }

        let cacheWindowStart = now.addingTimeInterval(-Self.codexEventCacheLookback)
        let validPaths = Set(files.map(\.path))
        codexLiveFileCache = codexLiveFileCache.filter { validPaths.contains($0.key) }

        var latestRateLimits: CodexRateLimits?
        var latestRateLimitTimestamp: Date?
        var latestTimestamp: Date?
        var recentEvents: [CodexUsageEventSummary] = []

        for file in files {
            guard let snapshot = liveCodexSnapshot(for: file, recentSince: cacheWindowStart) else { continue }

            if let timestamp = snapshot.latestTimestamp,
               latestTimestamp == nil || timestamp > latestTimestamp! {
                latestTimestamp = timestamp
            }

            if let rateLimitTimestamp = snapshot.latestRateLimitTimestamp,
               let rateLimits = snapshot.latestRateLimits,
               latestRateLimitTimestamp == nil || rateLimitTimestamp > latestRateLimitTimestamp! {
                latestRateLimitTimestamp = rateLimitTimestamp
                latestRateLimits = rateLimits
            }

            recentEvents.append(contentsOf: snapshot.recentEvents)
        }

        guard let rateLimits = latestRateLimits else { return nil }
        let windows = windowsFromCodexRateLimits(rateLimits, capturedAt: latestTimestamp)
        let costWindow = preferredCostWindow(from: windows)
        let windowStart = startDate(for: costWindow, now: now)
        let dailyWindowStart = Self.dailyBucketStart(now: now)

        var costUSD = 0.0
        var tokenCount: Int64 = 0
        var dailyEvents: [TimestampedUsage] = []
        for event in recentEvents {
            let cost = codexCost(for: event.usage, model: event.model)
            let tokens = event.usage.totalTokenCount
            if event.timestamp >= windowStart {
                costUSD += cost
                tokenCount += tokens
            }
            if event.timestamp >= dailyWindowStart {
                dailyEvents.append(TimestampedUsage(timestamp: event.timestamp, costUSD: cost, tokenCount: tokens))
            }
        }

        return (
            windows: windows,
            costUSD: costUSD,
            tokenCount: tokenCount,
            costWindowMinutes: costWindow?.windowMinutes,
            updatedAt: latestTimestamp,
            source: "Codex sessions",
            dailyEvents: dailyEvents
        )
    }

    private func liveCodexSnapshot(for file: URL, recentSince: Date) -> CodexLiveFileSnapshot? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate else {
            return nil
        }

        let fileSize = UInt64(max(0, values.fileSize ?? 0))
        if let cached = codexLiveFileCache[file.path],
           cached.contentModificationDate == modifiedAt,
           cached.fileSize == fileSize {
            return cached.snapshot
        }

        let snapshot = parseLiveCodexSessionFile(file, recentSince: recentSince)
        codexLiveFileCache[file.path] = CachedCodexLiveFileSnapshot(
            contentModificationDate: modifiedAt,
            fileSize: fileSize,
            snapshot: snapshot
        )
        return snapshot
    }

    private func parseLiveCodexSessionFile(_ file: URL, recentSince: Date) -> CodexLiveFileSnapshot {
        let lines = readLines(from: file)
        guard !lines.isEmpty else {
            return CodexLiveFileSnapshot(
                latestRateLimits: nil,
                latestRateLimitTimestamp: nil,
                latestTimestamp: nil,
                recentEvents: []
            )
        }

        var sessionModel = "gpt-5.4"
        var latestRateLimits: CodexRateLimits?
        var latestRateLimitTimestamp: Date?
        var latestTimestamp: Date?
        var recentEvents: [CodexUsageEventSummary] = []

        for line in lines {
            if sessionModel == "gpt-5.4",
               line.contains("\"model\":\""),
               let carrier = decode(CodexModelCarrier.self, from: line),
               let model = carrier.payload?.model,
               !model.isEmpty {
                sessionModel = model
            }

            guard line.contains("\"type\":\"event_msg\""),
                  line.contains("\"token_count\""),
                  let event = decode(CodexTokenCountEvent.self, from: line),
                  let timestamp = parseISODate(event.timestamp) else {
                continue
            }

            if latestTimestamp == nil || timestamp > latestTimestamp! {
                latestTimestamp = timestamp
            }

            if let rateLimits = event.payload.rateLimits,
               latestRateLimitTimestamp == nil || timestamp > latestRateLimitTimestamp! {
                latestRateLimitTimestamp = timestamp
                latestRateLimits = rateLimits
            }

            if timestamp >= recentSince, let usage = event.payload.info?.lastTokenUsage {
                recentEvents.append(
                    CodexUsageEventSummary(
                        timestamp: timestamp,
                        usage: usage,
                        model: sessionModel
                    )
                )
            }
        }

        return CodexLiveFileSnapshot(
            latestRateLimits: latestRateLimits,
            latestRateLimitTimestamp: latestRateLimitTimestamp,
            latestTimestamp: latestTimestamp,
            recentEvents: recentEvents
        )
    }

    /// Parses Claude transcripts for both the cost-window summary (used by
    /// the chip) and a 7-day per-event list (used by `dailyUsage`). We scan
    /// files modified since `min(costWindowStart, dailyWindowStart)` and then
    /// filter each event by the relevant window so both summaries share one
    /// disk pass.
    private func loadClaudeUsageSummary(
        costWindowStart: Date,
        dailyWindowStart: Date
    ) -> (costUSD: Double, tokenCount: Int64, updatedAt: Date?, dailyEvents: [TimestampedUsage]) {
        let projectsRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
        let parseSince = min(costWindowStart, dailyWindowStart)
        let files = recentJSONLFiles(in: projectsRoot, modifiedSince: parseSince)

        var seenEventIds = Set<String>()
        var totalCost = 0.0
        var tokenCount: Int64 = 0
        var latestTimestamp: Date?
        var dailyEvents: [TimestampedUsage] = []

        for file in files {
            for line in readLines(from: file) {
                guard line.contains("\"usage\""), line.contains("\"model\""), let entry = decode(ClaudeUsageEntry.self, from: line), let message = entry.message, let usage = message.usage, let model = message.model, let timestamp = parseISODate(entry.timestamp), timestamp >= parseSince else {
                    continue
                }

                let eventId = entry.requestId ?? message.id ?? entry.uuid
                if let eventId, seenEventIds.contains(eventId) {
                    continue
                }
                if let eventId {
                    seenEventIds.insert(eventId)
                }

                let cost = claudeCost(for: usage, model: model)
                let tokens = usage.totalTokenCount

                if timestamp >= costWindowStart {
                    totalCost += cost
                    tokenCount += tokens
                    if latestTimestamp == nil || timestamp > latestTimestamp! {
                        latestTimestamp = timestamp
                    }
                }
                if timestamp >= dailyWindowStart {
                    dailyEvents.append(TimestampedUsage(timestamp: timestamp, costUSD: cost, tokenCount: tokens))
                }
            }
        }

        return (costUSD: totalCost, tokenCount: tokenCount, updatedAt: latestTimestamp, dailyEvents: dailyEvents)
    }

    private func loadHistoryWindows(from path: URL) -> [ProviderMonitorWindow] {
        guard let data = try? Data(contentsOf: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = root["accounts"] as? [String: Any] else {
            return []
        }

        let preferredKey = root["preferredAccountKey"] as? String
        let rawWindows: [[String: Any]]? = {
            if let preferredKey, let windows = accounts[preferredKey] as? [[String: Any]] {
                return windows
            }
            for value in accounts.values {
                if let windows = value as? [[String: Any]] {
                    return windows
                }
            }
            return nil
        }()

        guard let rawWindows else { return [] }

        return rawWindows.compactMap { window in
            guard let name = window["name"] as? String,
                  let minutes = window["windowMinutes"] as? Int,
                  let entries = window["entries"] as? [[String: Any]],
                  let latestEntry = latestHistoryEntry(in: entries),
                  let usedPercent = percentValue(from: latestEntry["usedPercent"]) else {
                return nil
            }

            let resetsAt = (latestEntry["resetsAt"] as? String).flatMap(parseISODate)
            let capturedAt = (latestEntry["capturedAt"] as? String).flatMap(parseISODate)

            return ProviderMonitorWindow(
                name: name,
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                windowMinutes: minutes,
                capturedAt: capturedAt
            )
        }.sorted { lhs, rhs in
            if lhs.windowMinutes == rhs.windowMinutes {
                return lhs.name < rhs.name
            }
            return lhs.windowMinutes < rhs.windowMinutes
        }
    }

    private func percentValue(from rawValue: Any?) -> Double? {
        if let rawValue = rawValue as? Double {
            return rawValue
        }
        if let rawValue = rawValue as? Int {
            return Double(rawValue)
        }
        return nil
    }

    private func latestHistoryEntry(in entries: [[String: Any]]) -> [String: Any]? {
        entries.max { lhs, rhs in
            let leftDate = (lhs["capturedAt"] as? String).flatMap(parseISODate) ?? .distantPast
            let rightDate = (rhs["capturedAt"] as? String).flatMap(parseISODate) ?? .distantPast
            return leftDate < rightDate
        }
    }

    private func windowsFromCodexRateLimits(_ rateLimits: CodexRateLimits, capturedAt: Date?) -> [ProviderMonitorWindow] {
        var windows: [ProviderMonitorWindow] = []

        if let primary = rateLimits.primary, let minutes = primary.windowMinutes {
            windows.append(
                ProviderMonitorWindow(
                    name: "session",
                    usedPercent: primary.usedPercent ?? 0,
                    resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    windowMinutes: minutes,
                    capturedAt: capturedAt
                )
            )
        }

        if let secondary = rateLimits.secondary, let minutes = secondary.windowMinutes {
            windows.append(
                ProviderMonitorWindow(
                    name: "weekly",
                    usedPercent: secondary.usedPercent ?? 0,
                    resetsAt: secondary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    windowMinutes: minutes,
                    capturedAt: capturedAt
                )
            )
        }

        return windows
    }

    private func recentJSONLFiles(in root: URL, modifiedSince: Date) -> [URL] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [],
                errorHandler: nil
              ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }

            if let modifiedAt = values.contentModificationDate, modifiedAt < modifiedSince {
                continue
            }

            files.append(fileURL)
        }
        return files
    }

    private func readLines(from file: URL) -> [String] {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return []
        }
        return contents.components(separatedBy: "\n")
    }

    private func saveCachedSnapshots(_ snapshots: [String: ProviderMonitorSnapshot]) {
        let payload = SnapshotCachePayload(
            snapshots: snapshots.values.sorted { $0.provider < $1.provider }
        )

        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: snapshotCacheURL, options: .atomic)
    }

    private func parseISODate(_ value: String) -> Date? {
        if let date = UsageMonitor.iso8601Fractional.date(from: value) {
            return date
        }
        return UsageMonitor.iso8601.date(from: value)
    }

    private func startDate(for window: ProviderMonitorWindow?, now: Date) -> Date {
        guard let window else {
            return now.addingTimeInterval(-7 * 24 * 60 * 60)
        }
        if let resetsAt = window.resetsAt {
            return resetsAt.addingTimeInterval(TimeInterval(-window.windowMinutes * 60))
        }
        if let capturedAt = window.capturedAt {
            return capturedAt.addingTimeInterval(TimeInterval(-window.windowMinutes * 60))
        }
        return now.addingTimeInterval(TimeInterval(-window.windowMinutes * 60))
    }

    private func preferredCostWindow(from windows: [ProviderMonitorWindow]) -> ProviderMonitorWindow? {
        if let weekly = windows.first(where: { $0.name.lowercased() == "weekly" }) {
            return weekly
        }
        return windows.max { lhs, rhs in
            lhs.windowMinutes < rhs.windowMinutes
        }
    }

    private func selectVisibleWindows(from windows: [ProviderMonitorWindow]) -> [ProviderMonitorWindow] {
        // Prefer name-based matches so "opus" (which shares the 10080-minute
        // window with "weekly") doesn't shadow the real weekly bucket.
        let session = windows.first(where: { $0.name.lowercased() == "session" })
            ?? windows.first(where: { $0.windowMinutes == 300 })
        let weekly = windows.first(where: { $0.name.lowercased() == "weekly" })
            ?? windows.first(where: { $0.windowMinutes == 10_080 && $0.name.lowercased() != "opus" })
        if let session, let weekly,
           session.name != weekly.name || session.windowMinutes != weekly.windowMinutes {
            return [session, weekly]
        }

        if windows.count <= 2 {
            return windows
        }

        guard let shortest = windows.min(by: { $0.windowMinutes < $1.windowMinutes }),
              let longest = windows.max(by: { $0.windowMinutes < $1.windowMinutes }) else {
            return Array(windows.prefix(2))
        }

        if shortest.name == longest.name && shortest.windowMinutes == longest.windowMinutes {
            return [shortest]
        }

        return [shortest, longest]
    }

    private func codexCost(for usage: CodexTokenUsage, model: String) -> Double {
        let pricing = openAIPriceCard(for: model)
        let cachedInput = max(0, usage.cachedInputTokens ?? 0)
        let totalInput = max(0, usage.inputTokens ?? 0)
        let uncachedInput = max(0, totalInput - cachedInput)
        let output = max(0, usage.outputTokens ?? 0)

        return (Double(uncachedInput) * pricing.inputUSDPerMTok / 1_000_000)
            + (Double(cachedInput) * pricing.cachedInputUSDPerMTok / 1_000_000)
            + (Double(output) * pricing.outputUSDPerMTok / 1_000_000)
    }

    private func claudeCost(for usage: ClaudeUsage, model: String) -> Double {
        let pricing = claudePriceCard(for: model)
        let inputTokens = max(0, usage.inputTokens ?? 0)
        let cacheReadTokens = max(0, usage.cacheReadInputTokens ?? 0)
        let outputTokens = max(0, usage.outputTokens ?? 0)

        let cache5mTokens = max(0, usage.cacheCreation?.ephemeral5mInputTokens ?? 0)
        let cache1hTokens = max(0, usage.cacheCreation?.ephemeral1hInputTokens ?? 0)
        let cacheWriteFallback = max(0, (usage.cacheCreationInputTokens ?? 0) - cache5mTokens - cache1hTokens)

        return (Double(inputTokens) * pricing.inputUSDPerMTok / 1_000_000)
            + (Double(cacheReadTokens) * pricing.cacheReadUSDPerMTok / 1_000_000)
            + (Double(cache5mTokens + cacheWriteFallback) * pricing.cacheWrite5mUSDPerMTok / 1_000_000)
            + (Double(cache1hTokens) * pricing.cacheWrite1hUSDPerMTok / 1_000_000)
            + (Double(outputTokens) * pricing.outputUSDPerMTok / 1_000_000)
    }

    private func openAIPriceCard(for model: String) -> OpenAIPriceCard {
        let normalized = model.lowercased()
        if normalized.contains("gpt-5.4-mini") || normalized.contains("gpt-5.4 mini") {
            return .init(inputUSDPerMTok: 0.75, cachedInputUSDPerMTok: 0.075, outputUSDPerMTok: 4.50)
        }
        if normalized.contains("gpt-5.4-nano") || normalized.contains("gpt-5.4 nano") {
            return .init(inputUSDPerMTok: 0.20, cachedInputUSDPerMTok: 0.02, outputUSDPerMTok: 1.25)
        }
        return .init(inputUSDPerMTok: 2.50, cachedInputUSDPerMTok: 0.25, outputUSDPerMTok: 15.00)
    }

    private func claudePriceCard(for model: String) -> ClaudePriceCard {
        let normalized = model.lowercased()
        if normalized.contains("opus") {
            return .init(inputUSDPerMTok: 5.0, outputUSDPerMTok: 25.0)
        }
        if normalized.contains("haiku") {
            return .init(inputUSDPerMTok: 1.0, outputUSDPerMTok: 5.0)
        }
        return .init(inputUSDPerMTok: 3.0, outputUSDPerMTok: 15.0)
    }

    private func decode<T: Decodable>(_ type: T.Type, from line: String) -> T? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func codexBarHistoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/com.steipete.codexbar/history/codex.json")
    }

    private func claudeHistoryURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/com.steipete.codexbar/history/claude.json")
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct OpenAIPriceCard {
    let inputUSDPerMTok: Double
    let cachedInputUSDPerMTok: Double
    let outputUSDPerMTok: Double
}

private struct ClaudePriceCard {
    let inputUSDPerMTok: Double
    let outputUSDPerMTok: Double

    var cacheReadUSDPerMTok: Double { inputUSDPerMTok * 0.10 }
    var cacheWrite5mUSDPerMTok: Double { inputUSDPerMTok * 1.25 }
    var cacheWrite1hUSDPerMTok: Double { inputUSDPerMTok * 2.0 }
}

private struct CodexModelCarrier: Decodable {
    let payload: Payload?

    struct Payload: Decodable {
        let model: String?
    }
}

private struct CodexTokenCountEvent: Decodable {
    let timestamp: String
    let payload: Payload

    struct Payload: Decodable {
        let info: Info?
        let rateLimits: CodexRateLimits?

        enum CodingKeys: String, CodingKey {
            case info
            case rateLimits = "rate_limits"
        }
    }

    struct Info: Decodable {
        let lastTokenUsage: CodexTokenUsage?

        enum CodingKeys: String, CodingKey {
            case lastTokenUsage = "last_token_usage"
        }
    }
}

private struct CodexRateLimits: Codable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

private struct CodexRateLimitWindow: Codable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Int64?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private struct CodexTokenUsage: Codable {
    let inputTokens: Int64?
    let cachedInputTokens: Int64?
    let outputTokens: Int64?
    let totalTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    var totalTokenCount: Int64 {
        totalTokens ?? max(0, (inputTokens ?? 0) + (outputTokens ?? 0))
    }
}

private struct ClaudeUsageEntry: Decodable {
    let message: ClaudeMessage?
    let requestId: String?
    let timestamp: String
    let uuid: String?
}

private struct ClaudeMessage: Decodable {
    let id: String?
    let model: String?
    let usage: ClaudeUsage?
}

private struct ClaudeUsage: Decodable {
    let inputTokens: Int64?
    let cacheCreationInputTokens: Int64?
    let cacheReadInputTokens: Int64?
    let outputTokens: Int64?
    let cacheCreation: ClaudeCacheCreation?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreation = "cache_creation"
    }

    var totalTokenCount: Int64 {
        max(0, (inputTokens ?? 0) + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0) + (outputTokens ?? 0))
    }
}

private struct ClaudeCacheCreation: Decodable {
    let ephemeral1hInputTokens: Int64?
    let ephemeral5mInputTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }
}
