# Architecture

Four ports over one shared normalization contract (the API's `limits[]`).
The business logic (kinds, order, percent clamping, severity, resets) is
deliberately duplicated per port and kept behaviorally identical by a shared
test fixture (`tests/fixtures/normalize.json`) — `tests/parity.test.js` asserts
the two JS ports, and the Swift `NormalizeParityTests` asserts the same file.

```text
claude-usage-panel@fschmutz.github.io/   # GNOME Shell extension (GJS / ESM)
├── extension.js        # panel button, dropdown, alerts, sparkline, Cursor section
├── prefs.js            # libadwaita preferences
├── stylesheet.css
├── schemas/            # GSettings schema
└── lib/
    ├── pure.js         # the reference normalization (unit-tested under node)
    ├── claudeUsage.js  # token read + /oauth/usage fetch
    ├── cost.js         # optional ccusage cost (subprocess)
    └── cursorUsage.js  # optional Cursor Admin API spend

macos/                  # native SwiftUI MenuBarExtra app (SwiftPM)
└── Sources/
    ├── ClaudeUsageCore/          # Foundation-only mirror of pure.js (tests on Linux)
    └── ClaudeUsagePanel/
        ├── Usage.swift               # token (file + Keychain) + fetch
        ├── Cost.swift                # ccusage via Process
        ├── Cursor.swift              # Cursor Admin API
        └── ClaudeUsagePanelApp.swift # MenuBarExtra, model, views, Settings

claude-code/            # status line under the Claude Code prompt
└── statusline.js       # renders purely from Claude Code's stdin — no network

mcp/                    # MCP server: get_usage tool (Claude Code, Cursor…)
└── server.js           # zero-dep stdio JSON-RPC, also the npx bin

plugin/                 # Claude Code plugin wrapping the MCP server
docs/                   # GitHub Pages site + the /install bootstrap
install.sh              # unified installer (gnome · statusline · mcp · macos)
```

## Data source

`GET https://api.anthropic.com/api/oauth/usage` with the local OAuth token and the
`anthropic-beta: oauth-2025-04-20` header. The response's `limits[]` array (kind / percent /
severity / resets_at / scope.model) drives one card per limit. Everything is read-only with
respect to the credentials. The status line is the exception: it renders only from what Claude
Code pipes on stdin — no credentials, no network.

## Quality

`pre-commit` (ESLint, swift-format, shellcheck, shfmt, markdownlint, gitleaks, actionlint,
version-drift guard) runs locally and in CI on every push; `npm test` + `swift test` cover the
pure logic and the cross-port parity contract.
