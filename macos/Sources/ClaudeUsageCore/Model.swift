import Foundation

// Pure model + normalization — Foundation only (no networking, no SwiftUI),
// so it builds and unit-tests on any platform incl. Linux CI.
// Mirrors the GNOME extension's lib/pure.js.

public enum Severity: String, Sendable {
    case normal, warning, critical
}

public struct LimitCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let percent: Int  // 0...100
    public let severity: Severity
    public let resetsAt: Date?
    public let active: Bool

    public init(
        id: String, label: String, percent: Int, severity: Severity,
        resetsAt: Date?, active: Bool
    ) {
        self.id = id
        self.label = label
        self.percent = percent
        self.severity = severity
        self.resetsAt = resetsAt
        self.active = active
    }
}

public enum UsageNormalizer {
    static let kindLabels: [String: String] = [
        "session": "Current session",
        "weekly_all": "Weekly · all models",
        "weekly_scoped": "Weekly",
        "weekly_oauth_apps": "Weekly · apps",
    ]
    static let kindOrder = ["session", "weekly_all", "weekly_scoped", "weekly_oauth_apps"]

    static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static func clampPercent(_ v: Double) -> Int {
        max(0, min(100, Int(v.rounded())))
    }

    /// Extract normalized cards from the raw payload. Prefers the modern
    /// `limits[]` array; falls back to legacy five_hour / seven_day fields.
    public static func normalize(_ payload: [String: Any]) -> [LimitCard] {
        if let limits = payload["limits"] as? [[String: Any]], !limits.isEmpty {
            let cards: [LimitCard] = limits.map { entry in
                let kind = entry["kind"] as? String ?? "unknown"
                var label = kindLabels[kind] ?? kind
                let scope = entry["scope"] as? [String: Any]
                let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
                if let model { label += " · \(model)" }
                let pct = clampPercent((entry["percent"] as? NSNumber)?.doubleValue ?? 0)
                let sev = Severity(rawValue: entry["severity"] as? String ?? "normal") ?? .normal
                return LimitCard(
                    id: kind + (model.map { ":\($0)" } ?? ""),
                    label: label, percent: pct, severity: sev,
                    resetsAt: parseDate(entry["resets_at"] as? String),
                    active: (entry["is_active"] as? Bool) ?? false)
            }
            return cards.sorted {
                let ai = kindOrder.firstIndex(of: $0.id.components(separatedBy: ":")[0]) ?? 99
                let bi = kindOrder.firstIndex(of: $1.id.components(separatedBy: ":")[0]) ?? 99
                return ai < bi
            }
        }

        var cards: [LimitCard] = []
        func legacy(_ payloadKey: String, id: String, _ label: String, active: Bool) {
            guard let obj = payload[payloadKey] as? [String: Any],
                let util = (obj["utilization"] as? NSNumber)?.doubleValue
            else { return }
            cards.append(
                LimitCard(
                    id: id, label: label, percent: clampPercent(util), severity: .normal,
                    resetsAt: parseDate(obj["resets_at"] as? String), active: active))
        }
        legacy("five_hour", id: "session", "Current session", active: true)
        legacy("seven_day", id: "weekly_all", "Weekly · all models", active: false)
        return cards
    }
}
