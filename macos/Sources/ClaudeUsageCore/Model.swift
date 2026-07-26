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
    /// Pool this limit draws from: "session" or "weekly".
    public let group: String
    /// A per-model sub-cap of `group`'s pool (e.g. Fable), not a pool of its own.
    public let scoped: Bool
    public let percent: Int  // 0...100
    public let severity: Severity
    public var resetsAt: Date?
    public let active: Bool

    public init(
        id: String, label: String, percent: Int, severity: Severity,
        resetsAt: Date?, active: Bool, group: String = "", scoped: Bool = false
    ) {
        self.id = id
        self.label = label
        self.group = group
        self.scoped = scoped
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

    /// Which pool a limit draws from. The API sends `group` ("session" /
    /// "weekly"); payloads that predate it are grouped by the kind prefix.
    static func groupOf(_ kind: String, _ group: String?) -> String {
        if let group, !group.isEmpty { return group }
        return kind.hasPrefix("weekly") ? "weekly" : kind
    }

    /// A scoped (per-model) limit is a sub-cap ON its group's pooled limit, not a
    /// pool of its own: Fable usage counts toward `weekly_all` and shares its
    /// reset. The API leaves the scoped `resets_at` null until that model is used
    /// in the window, so borrow the pooled reset.
    static func inheritPooledResets(_ cards: [LimitCard]) -> [LimitCard] {
        var out = cards
        for i in out.indices where out[i].scoped && out[i].resetsAt == nil {
            if let pooled = out.first(where: {
                !$0.scoped && $0.group == out[i].group && $0.resetsAt != nil
            }) {
                out[i].resetsAt = pooled.resetsAt
            }
        }
        return out
    }

    /// Sub-line for a scoped (per-model) card: its percent is a *share* of the
    /// weekly pool (on Max, up to 50 % of the weekly allowance may go to Fable),
    /// never extra headroom — every Fable token also moves `weekly_all`.
    public static func poolNote(_ card: LimitCard) -> String {
        card.scoped && card.group == "weekly" ? "Share of the weekly all-models limit" : ""
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
                    active: (entry["is_active"] as? Bool) ?? false,
                    group: groupOf(kind, entry["group"] as? String), scoped: model != nil)
            }
            return inheritPooledResets(cards).sorted {
                let ai = kindOrder.firstIndex(of: $0.id.components(separatedBy: ":")[0]) ?? 99
                let bi = kindOrder.firstIndex(of: $1.id.components(separatedBy: ":")[0]) ?? 99
                return ai < bi
            }
        }

        var cards: [LimitCard] = []
        func legacy(
            _ payloadKey: String, id: String, _ label: String, group: String, active: Bool
        ) {
            guard let obj = payload[payloadKey] as? [String: Any],
                let util = (obj["utilization"] as? NSNumber)?.doubleValue
            else { return }
            cards.append(
                LimitCard(
                    id: id, label: label, percent: clampPercent(util), severity: .normal,
                    resetsAt: parseDate(obj["resets_at"] as? String), active: active,
                    group: group, scoped: false))
        }
        legacy("five_hour", id: "session", "Current session", group: "session", active: true)
        legacy("seven_day", id: "weekly_all", "Weekly · all models", group: "weekly", active: false)
        return cards
    }
}
