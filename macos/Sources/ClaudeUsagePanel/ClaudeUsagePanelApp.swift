import SwiftUI
import AppKit

// MARK: - Palette (matches the GNOME extension)

private extension Color {
    static let cuAccent   = Color(red: 0xd9/255, green: 0x77/255, blue: 0x57/255) // Claude orange
    static let cuWarning  = Color(red: 0xe0/255, green: 0xa4/255, blue: 0x58/255)
    static let cuCritical = Color(red: 0xe5/255, green: 0x48/255, blue: 0x4d/255)

    static func severity(_ s: Severity) -> Color {
        switch s {
        case .normal:   return .cuAccent
        case .warning:  return .cuWarning
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
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); restart() }
    }
    @Published var showCost: Bool {
        didSet { UserDefaults.standard.set(showCost, forKey: "showCost"); Task { await refresh() } }
    }

    private var loopTask: Task<Void, Never>?

    init() {
        refreshMinutes = UserDefaults.standard.object(forKey: "refreshMinutes") as? Int ?? 10
        showCost = UserDefaults.standard.bool(forKey: "showCost")
        restart() // didSet does not fire from init, so start the loop explicitly
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
        } catch {
            errorText = error.localizedDescription
        }

        guard showCost else { costText = nil; return }
        costText = "computing…"
        if let cost = await Cost.fetchActiveCost() {
            costText = String(format: "$%.2f · %@ tokens", cost.costUSD, Self.compact(cost.tokens))
        } else {
            costText = "unavailable (install ccusage)"
        }
    }

    /// Worst (highest %) limit, for the menu-bar title.
    var titleText: String {
        guard let worst = cards.max(by: { $0.percent < $1.percent }) else {
            return errorText == nil ? "✳ …" : "✳ ?"
        }
        let short = worst.label.components(separatedBy: "·").last?.trimmingCharacters(in: .whitespaces) ?? worst.label
        return "✳ \(short) \(worst.percent)%"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(Int((Double(n) / 1_000).rounded()))k" }
        return "\(n)"
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}

// MARK: - Reset-time helper

private func resetsText(_ date: Date?) -> String {
    guard let date else { return "" }
    let delta = Int(date.timeIntervalSinceNow)
    if delta <= 0 { return "Resetting…" }
    let d = delta / 86400, h = (delta % 86400) / 3600, m = (delta % 3600) / 60
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
            Text(resetsText(card.resetsAt)).font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(card.severity == .critical ? color.opacity(0.35) : Color.primary.opacity(0.08)))
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
                    Text(plan).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                }
            }

            if let err = model.errorText, model.cards.isEmpty {
                Text(err).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.cards) { CardView(card: $0) }
            }

            if let cost = model.costText {
                Text("Session cost: \(cost)").font(.system(size: 12, weight: .semibold))
            }
            Text("Updated \(model.updated)").font(.system(size: 11)).foregroundColor(.secondary)

            Divider()

            HStack {
                Toggle("Cost", isOn: $model.showCost).toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                Text("Refresh").font(.system(size: 12)).foregroundColor(.secondary)
                Picker("", selection: $model.refreshMinutes) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0)m").tag($0) }
                }.labelsHidden().frame(width: 70)
            }

            HStack {
                Button { Task { await model.refresh() } } label: { Label("Refresh now", systemImage: "arrow.clockwise") }
                Spacer()
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: {
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

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
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
    }
}
