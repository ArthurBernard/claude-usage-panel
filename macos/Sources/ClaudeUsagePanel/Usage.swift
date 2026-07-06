import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLSession lives here on Linux
#endif

// Data layer: read the local Claude Code OAuth token and query the official
// usage endpoint. Read-only — we never write back to the credentials file.
// Mirrors the GNOME extension's lib/claudeUsage.js.

enum Severity: String {
    case normal, warning, critical
}

struct LimitCard: Identifiable {
    let id: String
    let label: String
    let percent: Int       // 0...100
    let severity: Severity
    let resetsAt: Date?
    let active: Bool
}

struct UsageResult {
    let cards: [LimitCard]
    let planLabel: String?
}

enum UsageError: LocalizedError {
    case noToken
    case authExpired
    case http(Int)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .noToken:     return "No Claude credentials found. Sign in with Claude Code."
        case .authExpired: return "Claude session expired. Run any Claude Code command to refresh."
        case .http(let s): return "HTTP \(s)"
        case .parse(let m): return m
        }
    }
}

enum ClaudeUsage {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"

    private static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    /// Read the OAuth access token from ~/.claude/.credentials.json.
    static func readAccessToken() -> String? {
        guard let data = try? Data(contentsOf: credentialsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Token may sit under `claudeAiOauth` or at the top level.
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        return (oauth["accessToken"] as? String)
            ?? (oauth["access_token"] as? String)
            ?? (oauth["token"] as? String)
    }

    private static let kindLabels: [String: String] = [
        "session": "Current session",
        "weekly_all": "Weekly · all models",
        "weekly_scoped": "Weekly",
        "weekly_oauth_apps": "Weekly · apps",
    ]
    private static let kindOrder = ["session", "weekly_all", "weekly_scoped", "weekly_oauth_apps"]

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFormatter.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }

    /// Extract normalized cards from the raw payload. Prefers the modern
    /// `limits[]` array; falls back to legacy five_hour / seven_day fields.
    static func normalize(_ payload: [String: Any]) -> [LimitCard] {
        if let limits = payload["limits"] as? [[String: Any]], !limits.isEmpty {
            let cards: [LimitCard] = limits.map { entry in
                let kind = entry["kind"] as? String ?? "unknown"
                var label = kindLabels[kind] ?? kind
                let scope = entry["scope"] as? [String: Any]
                let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                if let model { label += " · \(model)" }
                let pct = max(0, min(100, Int((entry["percent"] as? NSNumber)?.doubleValue.rounded() ?? 0)))
                let sev = Severity(rawValue: entry["severity"] as? String ?? "normal") ?? .normal
                return LimitCard(
                    id: kind + (model.map { ":\($0)" } ?? ""),
                    label: label,
                    percent: pct,
                    severity: sev,
                    resetsAt: parseDate(entry["resets_at"] as? String),
                    active: (entry["is_active"] as? Bool) ?? false
                )
            }
            return cards.sorted {
                let ai = kindOrder.firstIndex(of: $0.id.components(separatedBy: ":")[0]) ?? 99
                let bi = kindOrder.firstIndex(of: $1.id.components(separatedBy: ":")[0]) ?? 99
                return ai < bi
            }
        }

        // Legacy fallback.
        var cards: [LimitCard] = []
        func legacy(_ key: String, _ label: String, active: Bool) {
            guard let obj = payload[key] as? [String: Any],
                  let util = (obj["utilization"] as? NSNumber)?.doubleValue else { return }
            cards.append(LimitCard(
                id: key, label: label, percent: max(0, min(100, Int(util.rounded()))),
                severity: .normal, resetsAt: parseDate(obj["resets_at"] as? String), active: active))
        }
        legacy("five_hour", "Current session", active: true)
        legacy("seven_day", "Weekly · all models", active: false)
        return cards
    }

    /// Fetch usage from the endpoint.
    static func fetch() async throws -> UsageResult {
        guard let token = readAccessToken() else { throw UsageError.noToken }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw UsageError.authExpired }
        guard (200..<300).contains(status) else { throw UsageError.http(status) }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.parse("Usage endpoint returned invalid JSON")
        }
        return UsageResult(cards: normalize(payload), planLabel: payload["plan_label"] as? String)
    }
}
