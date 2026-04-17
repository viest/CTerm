import Foundation

class TokenTrackerBridge {
    /// Per-provider usage
    private(set) var providerUsage: [String: TokenUsage] = [:]
    var onUsageUpdated: (([String: TokenUsage]) -> Void)?
    private let storagePath: String

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ctermDir = appSupport.appendingPathComponent("CTerm")
        try? FileManager.default.createDirectory(at: ctermDir, withIntermediateDirectories: true)
        self.storagePath = ctermDir.appendingPathComponent("tokens.json").path
        loadFromDisk()
    }

    func addTokens(inputTokens: Int64, outputTokens: Int64, cost: Double, provider: String, model: String, sessionId: String) {
        let key = provider.isEmpty ? "unknown" : provider
        var usage = providerUsage[key] ?? TokenUsage()
        usage.inputTokens += inputTokens
        usage.outputTokens += outputTokens
        usage.costUSD += cost
        usage.entryCount += 1
        providerUsage[key] = usage

        DispatchQueue.main.async {
            self.onUsageUpdated?(self.providerUsage)
        }
    }

    func getTotalUsage() -> TokenUsage {
        var total = TokenUsage()
        for (_, u) in providerUsage {
            total.inputTokens += u.inputTokens
            total.outputTokens += u.outputTokens
            total.costUSD += u.costUSD
            total.entryCount += u.entryCount
        }
        return total
    }

    func saveToDisk() {
        var dict: [String: [String: Any]] = [:]
        for (provider, usage) in providerUsage {
            dict[provider] = [
                "inputTokens": usage.inputTokens,
                "outputTokens": usage.outputTokens,
                "costUSD": usage.costUSD,
                "entryCount": usage.entryCount,
            ]
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: storagePath))
        }
    }

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        for (provider, vals) in json {
            var usage = TokenUsage()
            usage.inputTokens = vals["inputTokens"] as? Int64 ?? 0
            usage.outputTokens = vals["outputTokens"] as? Int64 ?? 0
            usage.costUSD = vals["costUSD"] as? Double ?? 0
            usage.entryCount = vals["entryCount"] as? Int32 ?? 0
            providerUsage[provider] = usage
        }
    }
}
