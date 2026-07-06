# Claude Usage Panel

**See your Claude Code plan usage at a glance — in the GNOME top bar (Linux) or the macOS menu bar.**

Session, weekly, and **per-model** limits (like **Fable** and **Opus**) — the same numbers as `/usage`, always visible, auto-refreshing.

![GNOME Shell 45–50](https://img.shields.io/badge/GNOME%20Shell-45--50-4A86CF?logo=gnome&logoColor=white)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Swift 6.1](https://img.shields.io/badge/Swift-6.1-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-3DA639)
![Read-only](https://img.shields.io/badge/credentials-read--only-2ea44f)

<img src="docs/screenshot.png" alt="Claude Usage Panel dropdown showing session, weekly, and per-model Fable limits" width="420">

> **Linux + macOS.** GNOME Shell extension in the repo root; a native SwiftUI menu-bar app in [`macos/`](macos/) — same data layer, same designed dropdown.

## Why this one

Most Claude usage indicators read the endpoint's legacy `five_hour` / `seven_day`
fields and show only the aggregate session + weekly pair. This one reads the
modern **`limits[]` array**, so it shows **every** limit the Claude app shows —
including **per-model weekly limits** (Fable, Opus, …) that the others miss.

## Features

- **All plan limits** in one designed dropdown: current session, weekly (all models), and per-model weekly limits (Fable, Opus, …).
- **Severity colors** — normal / warning / **critical**, straight from the API's `severity` field.
- **Reset timers** — `Resets in 3h 06m`, `Resets in 4d 2h`.
- **Compact top-bar readout** — the worst limit (or the current session), e.g. `Fable 100%`.
- **Optional session cost** — computed locally via [`ccusage`](https://github.com/ryoppippi/ccusage) (the official API exposes no dollar cost on subscription plans).
- **Configurable refresh** — defaults to every 10 minutes.
- **Read-only & private** — uses your existing `~/.claude/.credentials.json` token, never writes it, and talks only to `api.anthropic.com`.
- **Quit** from the menu — unloads it and keeps it off until you re-enable.

## Install — GNOME (Linux)

```bash
git clone https://github.com/fschmutz/claude-usage-panel.git
cd claude-usage-panel
./install.sh
```

`install.sh` copies the extension, compiles its schema, clears the global
`disable-user-extensions` switch if set, and enables it to auto-start on every
login. Then **log out and back in** (Wayland loads new extensions only at login)
and confirm:

```bash
gnome-extensions info claude-usage-panel@fschmutz.github.io   # State: ACTIVE
```

## Install — macOS

```bash
cd macos
swift run          # icon appears in the menu bar
```

Full details, release build, and login-item setup in [macos/README.md](macos/README.md).

## Requirements

- **Linux:** GNOME Shell 45–50
- **macOS:** 13 Ventura or later (Xcode 15+ / Swift toolchain)
- An active Claude Code login (`~/.claude/.credentials.json` present)
- Optional, for cost: Node.js / `npx`, or a global `ccusage`

## How it works

Reads the OAuth access token Claude Code already stores in
`~/.claude/.credentials.json` and calls the official usage endpoint:

```
GET https://api.anthropic.com/api/oauth/usage
    authorization: Bearer <token>
    anthropic-beta: oauth-2025-04-20
```

The response contains a `limits[]` array — one entry per active limit, each with
a `percent`, a `severity`, a `resets_at`, and an optional model `scope`. The
panel renders one card per limit. If the token expires, it prompts you to run
any Claude Code command (which refreshes it) — it never touches the file.

## Settings

- **Refresh interval** — minutes between polls (default 10).
- **Top bar shows** — worst limit or current session.
- **Show session cost** — enable local `ccusage` cost computation.

GNOME: open via the dropdown's **Settings**, or
`gnome-extensions prefs claude-usage-panel@fschmutz.github.io`.
macOS: toggles live directly in the dropdown.

## Privacy

Read-only with respect to your credentials. One outbound request per refresh, to
Anthropic's official API, with your own token. No telemetry, no third parties.
When cost is enabled it additionally runs `ccusage` locally against your
`~/.claude/projects/*.jsonl` logs.

## License

MIT — see [LICENSE](LICENSE).

---

<sub>Keywords: Claude Code usage monitor, Claude usage GNOME Shell extension, Claude plan limits top bar, macOS menu bar Claude usage, Anthropic usage API, ccusage, Fable / Opus per-model weekly limit, session and weekly usage, Ubuntu GNOME extension, SwiftUI MenuBarExtra.</sub>
