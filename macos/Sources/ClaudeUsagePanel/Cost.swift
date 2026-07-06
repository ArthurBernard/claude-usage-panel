import Foundation

// Optional cost layer: the official usage API does not expose dollar cost on
// subscription plans, so we shell out to `ccusage` (computed from the local
// ~/.claude/projects/*.jsonl logs). Mirrors the GNOME extension's lib/cost.js.

struct ActiveCost {
    let costUSD: Double
    let tokens: Int
}

enum Cost {
    /// Run `ccusage blocks --active --json`. Tries a global `ccusage` first,
    /// then falls back to `npx`. Returns nil if unavailable.
    static func fetchActiveCost() async -> ActiveCost? {
        let candidates: [[String]] = [
            ["ccusage", "blocks", "--active", "--json"],
            ["npx", "-y", "ccusage@latest", "blocks", "--active", "--json"],
        ]
        for argv in candidates {
            if let cost = run(argv) { return cost }
        }
        return nil
    }

    private static func run(_ argv: [String]) -> ActiveCost? {
        let proc = Process()
        // Use a login-ish PATH so Homebrew / Volta / npm global bins resolve.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = argv
        var env = ProcessInfo.processInfo.environment
        let extra = [
            "/opt/homebrew/bin", "/usr/local/bin",
            NSHomeDirectory() + "/.volta/bin",
            NSHomeDirectory() + "/.npm-global/bin",
        ]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        proc.environment = env

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let blocks = json["blocks"] as? [[String: Any]],
            let first = blocks.first
        else { return nil }

        let cost = (first["costUSD"] as? NSNumber)?.doubleValue ?? 0
        let tokens = (first["totalTokens"] as? NSNumber)?.intValue ?? 0
        return ActiveCost(costUSD: cost, tokens: tokens)
    }
}
