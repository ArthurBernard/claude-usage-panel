# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
semantic versioning.

## [Unreleased]

### Added

- `install.sh update [target…]` upgrades an existing install in place —
  reinstalling only the targets already present (detected), with `--pull` to
  `git pull --ff-only` first. macOS quits the running app and relaunches the new
  build so the upgrade actually takes effect; `--list` now shows detected vs
  installed targets.

## [1.4.0] — 2026-07-13

### Added

- Claude Code **terminal status line** (`claude-code/`): a condensed one-line
  usage view under the prompt, with cache + rate-limit backoff and a stdin
  `rate_limits` fallback. Contributed by @Giovannibthx (#7).
- Unit tests: JS (`node --test`) for the extension's pure logic and Swift
  (`swift test`) for the `ClaudeUsageCore` library, wired into CI.
- Sparkline history now persists across restarts (dconf on GNOME,
  `UserDefaults` on macOS).
- GNOME: light-theme support for the dropdown.
- Internationalization scaffolding (gettext `.pot` + a French translation).
- **Cross-port parity test**: one shared `tests/fixtures/normalize.json` asserts
  the GNOME, status-line, and macOS normalizers all agree on the semantic core —
  drift between the three hand-written copies now reddens CI.
- **macOS CI job** (`macos-latest`) compiles the real SwiftUI app, not just the
  Foundation-only core, so app-layer type errors are caught in CI.
- `scripts/bump-version.sh <ver>` bumps the version in every file at once
  (`package.json`, `metadata.json`, the Homebrew cask, and `CHANGELOG.md`).
- `install.sh --dry-run` prints every action without touching the filesystem,
  `settings.json`, or dconf.
- Unit tests for the status line's disk cache, TTL boundary, and rate-limit
  backoff (`readCache` / `writeCache` / `touchCache` made injectable).
- macOS: **Start at login** via `SMAppService` (macOS 13+), on by default on
  first launch (matching the GNOME auto-enable) and toggleable in Settings.
  `install.sh macos` now ad-hoc signs the bundle, installs it to `/Applications`,
  and launches it; `--uninstall macos` removes it.

### Changed

- **One unified `install.sh`** replaces the three separate scripts: it takes
  `gnome` / `statusline` / `macos` targets (auto-detecting the OS with no
  argument), adds `--uninstall`, `--list`, and `-h`, and each target guards its
  own dependencies and skips cleanly instead of failing the run. Removed
  `claude-code/install.sh` and `macos/build-app.sh`.
- The macOS bundle version is now read from `package.json` (single source of
  truth), fixing a drift where `build-app.sh` hardcoded a different version.
- Refactored the pure logic into a testable `lib/pure.js` (GNOME) and a
  Foundation-only `ClaudeUsageCore` Swift library (macOS), separated from the
  GJS / SwiftUI / networking layers.

### Fixed

- macOS: correct legacy-usage fallback ids (`session` / `weekly_all`).

## [1.2.2] — 2026-07-07

### Added

- Cursor spend **gauge**: a colored `%` bar when the team has a monthly spend
  limit set (falls back to spend text otherwise), on GNOME and macOS.

## [1.2.1] — 2026-07-07

### Fixed

- GNOME: clicking **Refresh now** no longer closes the popup.

## [1.2.0] — 2026-07-07

### Added

- Limit-crossing alerts (90% / 100%), usage sparkline, severity-colored top-bar glyph.
- macOS: native Settings window + Cursor support; token read from the login Keychain.
- Optional Cursor team-spend section (Cursor Admin API).

## [1.0.0] — 2026-07-03

### Added

- Initial release: GNOME Shell extension + native SwiftUI macOS menu-bar app
  showing Claude Code session / weekly / per-model plan limits from the official
  usage API, with a designed dropdown and optional `ccusage` cost.
