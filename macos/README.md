# Claude Usage Panel — macOS

A native SwiftUI menu-bar app (`MenuBarExtra`) that mirrors the GNOME extension:
Claude Code plan limits (session / weekly / per-model like **Fable**) in the
macOS menu bar, with a designed dropdown, severity colors, reset timers, and
optional session cost via `ccusage`.

Same data source as the GNOME version — reads the local Claude Code OAuth token
(read-only) and calls `https://api.anthropic.com/api/oauth/usage`. On macOS the
token lives in the **login Keychain** (Claude Code stores it there, not in a
file), so the app reads it via `security find-generic-password`; it falls back
to `~/.claude/.credentials.json` if present. The first read may prompt for
Keychain access — click **Always Allow**.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ **or** the Swift toolchain (`swift --version`)
- An active Claude Code login (`~/.claude/.credentials.json` present)
- Optional, for cost: Node.js / `npx` (or a global `ccusage`)

## Build & run

```bash
cd macos
swift run          # builds and launches; icon appears in the menu bar
```

For a release build / a reusable `.app`:

```bash
swift build -c release
# binary at .build/release/ClaudeUsagePanel
```

Or open the folder in Xcode (`File ▸ Open ▸ macos/`) and Run.

### Start at login

System Settings ▸ General ▸ Login Items ▸ **+** and add the built app (or the
`.build/release/ClaudeUsagePanel` binary). The app is an "accessory" (no Dock
icon), so it lives only in the menu bar.

## Layout

| File | Role |
|---|---|
| `Sources/ClaudeUsagePanel/Usage.swift` | token read + endpoint fetch + `limits[]` normalization |
| `Sources/ClaudeUsagePanel/Cost.swift` | optional `ccusage` cost via `Process` |
| `Sources/ClaudeUsagePanel/ClaudeUsagePanelApp.swift` | `MenuBarExtra` app, view model, designed cards, Quit |

## Notes

- The menu bar title shows the worst limit, e.g. `✳ Fable 100%`.
- Toggle **Cost** and change the **Refresh** interval directly in the dropdown;
  both persist via `UserDefaults`.
- **Quit** terminates the app. Remove it from Login Items to stop it starting
  at login.
- Read-only w.r.t. credentials; one request per refresh to Anthropic's API with
  your own token. No telemetry.

> Note: this app was authored on Linux and has **not** been compiled on a Mac
> yet — build it once with `swift run` and report any type errors. The data
> layer is a direct port of the verified GNOME logic.
