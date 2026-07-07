import AppKit
import ClaudeUsageCore
import SwiftUI

// MARK: - Palette (matches the GNOME extension)

extension Color {
    // Claude orange
    fileprivate static let cuAccent = Color(red: 0xd9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    fileprivate static let cuWarning = Color(red: 0xe0 / 255, green: 0xa4 / 255, blue: 0x58 / 255)
    fileprivate static let cuCritical = Color(red: 0xe5 / 255, green: 0x48 / 255, blue: 0x4d / 255)

    fileprivate static func severity(_ s: Severity) -> Color {
        switch s {
        case .normal: return .cuAccent
        case .warning: return .cuWarning
        case .critical: return .cuCritical
        }
    }
}

// MARK: - View model

@MainActor
final class UsageModel: ObservableObject {
    @Published var cards: [LimitCard] = []
    @Published var planLabel: String?
    @Published var errorText: String?
    @Published var costText: String?
    @Published var updated: String = ""

    @Published var refreshMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes")
            restart()
        }
    }
    @Published var showCost: Bool {
        didSet {
            UserDefaults.standard.set(showCost, forKey: "showCost")
            Task { await refresh() }
        }
    }
    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") }
    }
    @Published var cursorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cursorEnabled, forKey: "cursorEnabled")
            Task { await refresh() }
        }
    }
    @Published var cursorApiKey: String {
        didSet {
            UserDefaults.standard.set(cursorApiKey, forKey: "cursorApiKey")
            Task { await refresh() }
        }
    }
    @Published var cursorSummary: CursorSummary?
    @Published var cursorError: String?
    @Published private(set) var history: [String: [Int]] = [:]
    private var alertFired: [String: Int] = [:]

    private var loopTask: Task<Void, Never>?

    init() {
        refreshMinutes = UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 10
        showCost = UserDefaults.standard.bool(forKey: "showCost")
        alertsEnabled = UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool ?? true
        cursorEnabled = UserDefaults.standard.bool(forKey: "cursorEnabled")
        cursorApiKey = UserDefaults.standard.string(forKey: "cursorApiKey") ?? ""
        history = (UserDefaults.standard.dictionary(forKey: "history") as? [String: [Int]]) ?? [:]
        restart()  // didSet does not fire from init, so start the loop explicitly
    }

    private func restart() {
        loopTask?.cancel()
        let minutes = max(1, refreshMinutes)
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            }
        }
    }

    func refresh() async {
        do {
            let result = try await ClaudeUsage.fetch()
            cards = result.cards
            planLabel = result.planLabel
            errorText = nil
            updated = Self.timeFormatter.string(from: Date())
            recordHistory(result.cards)
            checkAlerts(result.cards)
        } catch {
            errorText = error.localizedDescription
        }

        guard showCost else {
            costText = nil
            return
        }
        costText = "computing…"
        if let cost = await Cost.fetchActiveCost() {
            costText = String(format: "$%.2f · %@ tokens", cost.costUSD, Self.compact(cost.tokens))
        } else {
            costText = "unavailable (install ccusage)"
        }

        await refreshCursor()
    }

    private func refreshCursor() async {
        guard cursorEnabled, !cursorApiKey.isEmpty else {
            cursorSummary = nil
            cursorError = nil
            return
        }
        do {
            cursorSummary = try await CursorAPI.fetch(key: cursorApiKey)
            cursorError = nil
        } catch {
            cursorSummary = nil
            cursorError = error.localizedDescription
        }
    }

    private func recordHistory(_ cards: [LimitCard]) {
        for c in cards {
            var h = history[c.id] ?? []
            h.append(c.percent)
            if h.count > 12 { h.removeFirst(h.count - 12) }
            history[c.id] = h
        }
        UserDefaults.standard.set(history, forKey: "history")  // survive restarts
    }

    // Notify on first crossing of 90% / 100%, with hysteresis to re-arm.
    private func checkAlerts(_ cards: [LimitCard]) {
        guard alertsEnabled else { return }
        for c in cards {
            let prev = alertFired[c.id] ?? 0
            let threshold = c.percent >= 100 ? 100 : (c.percent >= 90 ? 90 : 0)
            if threshold > prev {
                alertFired[c.id] = threshold
                notify("Claude usage", "\(c.label) reached \(threshold)%")
            } else if threshold < prev && c.percent < 85 {
                alertFired[c.id] = threshold
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "\\\"") }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [
            "-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\"",
        ]
        try? proc.run()
    }

    func spark(for id: String) -> String {
        let h = history[id] ?? []
        guard h.count >= 2 else { return "" }
        let blocks = Array(" ▁▂▃▄▅▆▇█")
        return String(h.map { blocks[max(0, min(8, Int((Double($0) / 100 * 8).rounded())))] })
    }

    /// Severity dot for the menu-bar title (renders in color as an emoji).
    private func dot(_ s: Severity) -> String {
        switch s {
        case .critical: return "🔴"
        case .warning: return "🟠"
        case .normal: return "🟢"
        }
    }

    /// Worst (highest %) limit, for the menu-bar title.
    var titleText: String {
        guard let worst = cards.max(by: { $0.percent < $1.percent }) else {
            return errorText == nil ? "⚪️ …" : "⚪️ ?"
        }
        let short =
            worst.label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces)
            ?? worst.label
        return "\(dot(worst.severity)) \(short) \(worst.percent)%"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(Int((Double(n) / 1_000).rounded()))k" }
        return "\(n)"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Reset-time helper

private func resetsText(_ date: Date?) -> String {
    guard let date else { return "" }
    let delta = Int(date.timeIntervalSinceNow)
    if delta <= 0 { return "Resetting…" }
    let d = delta / 86400
    let h = (delta % 86400) / 3600
    let m = (delta % 3600) / 60
    if d > 0 { return "Resets in \(d)d \(h)h" }
    if h > 0 { return String(format: "Resets in %dh %02dm", h, m) }
    return "Resets in \(m)m"
}

// MARK: - Views

private struct ProgressBar: View {
    let percent: Int
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(percent) / 100))
            }
        }
        .frame(height: 8)
    }
}

private struct CardView: View {
    let card: LimitCard
    let spark: String
    var body: some View {
        let color = Color.severity(card.severity)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.label).font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
                if card.active { Circle().fill(color).frame(width: 6, height: 6) }
                Spacer()
                Text("\(card.percent)%").font(.system(size: 15, weight: .heavy))
                    .foregroundColor(color).monospacedDigit()
            }
            ProgressBar(percent: card.percent, color: color)
            HStack {
                Text(resetsText(card.resetsAt)).font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !spark.isEmpty {
                    Text(spark).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    card.severity == .critical ? color.opacity(0.35) : Color.primary.opacity(0.08)))
    }
}

struct PopupView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude usage").font(.system(size: 15, weight: .bold))
                Spacer()
                if let plan = model.planLabel, !plan.isEmpty {
                    Text(plan).font(.system(size: 12, weight: .semibold)).foregroundColor(
                        .secondary)
                }
            }

            if let err = model.errorText, model.cards.isEmpty {
                Text(err).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.cards) { CardView(card: $0, spark: model.spark(for: $0.id)) }
            }

            if let cost = model.costText {
                Text("Session cost: \(cost)").font(.system(size: 12, weight: .semibold))
            }
            Text("Updated \(model.updated)").font(.system(size: 11)).foregroundColor(.secondary)

            if model.cursorEnabled {
                CursorSectionView(model: model)
            }

            Divider()

            HStack {
                Toggle("Cost", isOn: $model.showCost).toggleStyle(.checkbox).font(.system(size: 12))
                Toggle("Alerts", isOn: $model.alertsEnabled).toggleStyle(.checkbox).font(
                    .system(size: 12))
                Spacer()
                Text("Refresh").font(.system(size: 12)).foregroundColor(.secondary)
                Picker("", selection: $model.refreshMinutes) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0)m").tag($0) }
                }.labelsHidden().frame(width: 70)
            }

            HStack {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh now", systemImage: "arrow.clockwise")
                }
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Label("Settings…", systemImage: "gearshape")
                    }
                } else {
                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(
                            Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 340)
    }
}

// Cursor spend block in the dropdown (shown when enabled).
private struct CursorSectionView: View {
    @ObservedObject var model: UsageModel
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cursor").font(.system(size: 13, weight: .bold))
            if let s = model.cursorSummary {
                if let pct = s.percent {
                    Text(
                        String(
                            format: "This cycle: $%.2f / $%.0f (%d%%) · %d members",
                            s.cycleUSD, s.limitUSD, pct, s.members)
                    ).font(.system(size: 12, weight: .semibold))
                    ProgressBar(
                        percent: pct,
                        color: pct >= 100 ? .cuCritical : (pct >= 90 ? .cuWarning : .cuAccent))
                } else {
                    Text(String(format: "This cycle: $%.2f · %d members", s.cycleUSD, s.members))
                        .font(.system(size: 12, weight: .semibold))
                }
                if let today = s.todayUSD {
                    Text(String(format: "Today: $%.2f", today))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                if let top = s.top {
                    Text(String(format: "Top: %@ $%.2f", top.email, top.usd))
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            } else if let err = model.cursorError {
                Text("Cursor: \(err)").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text("Loading…").font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        Form {
            Section("General") {
                Picker("Refresh interval", selection: $model.refreshMinutes) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                Toggle("Limit-crossing alerts (90% / 100%)", isOn: $model.alertsEnabled)
                Toggle("Show session cost (ccusage)", isOn: $model.showCost)
            }
            Section("Cursor (optional)") {
                Toggle("Show Cursor team spend", isOn: $model.cursorEnabled)
                SecureField("Cursor Admin API key", text: $model.cursorApiKey)
                    .disabled(!model.cursorEnabled)
                Text("Create a key at cursor.com → your team → Settings → Admin API.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no Dock icon
    }
}

@main
struct ClaudeUsagePanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = UsageModel()

    var body: some Scene {
        MenuBarExtra {
            PopupView(model: model)
        } label: {
            Text(model.titleText)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
