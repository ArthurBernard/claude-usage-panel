# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
semantic versioning.

## [Unreleased]

### Added

- Unit tests: JS (`node --test`) for the extension's pure logic and Swift
  (`swift test`) for the `ClaudeUsageCore` library, wired into CI.
- Sparkline history now persists across restarts (dconf on GNOME,
  `UserDefaults` on macOS).
- GNOME: light-theme support for the dropdown.
- Internationalization scaffolding (gettext `.pot` + a French translation).

### Changed

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
