# Security Policy

## Reporting a vulnerability

Please report security issues privately via
[GitHub Security Advisories](https://github.com/fschmutz/claude-usage-panel/security/advisories/new)
rather than a public issue.

## Scope & design

This project is **read-only** with respect to your credentials. It reads the OAuth
token Claude Code already stores locally and calls Anthropic's official usage API.
The optional Cursor integration calls `api.cursor.com` with a key you provide; the
optional cost feature runs `ccusage` locally. No telemetry, no third-party servers.

Secrets are never committed - `gitleaks` runs in pre-commit and CI.
