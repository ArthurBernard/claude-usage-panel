#!/usr/bin/env bash
# Guard against version drift: every place that carries the version must match
# package.json (the single source of truth), and no build path may hardcode a
# version literal. Runs in pre-commit and CI. This is what makes the
# build-app.sh "1.4.0 vs 1.3.0" class of bug impossible to commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
note() {
    echo "  ✗ $1" >&2
    fail=1
}

want="$(sed -nE 's/.*"version": *"([^"]+)".*/\1/p' package.json | head -1)"
if [ -z "$want" ]; then
    echo "check-versions: could not read version from package.json" >&2
    exit 2
fi

# metadata.json version-name must match.
meta="$(sed -nE 's/.*"version-name": *"([^"]+)".*/\1/p' \
    "claude-usage-panel@fschmutz.github.io/metadata.json" | head -1)"
[ "$meta" = "$want" ] || note "metadata.json version-name is '$meta', expected '$want'"

# PUBLISHING.md Homebrew cask example must match.
cask="$(sed -nE 's/^  version "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' PUBLISHING.md | head -1)"
[ "$cask" = "$want" ] || note "PUBLISHING.md cask version is '$cask', expected '$want'"

# MCP server exported VERSION const must match.
mcp="$(sed -nE "s/^export const VERSION = '([^']+)';.*/\1/p" mcp/server.js | head -1)"
[ "$mcp" = "$want" ] || note "mcp/server.js VERSION is '$mcp', expected '$want'"

# Claude Code plugin manifest + marketplace entry must match.
plug="$(sed -nE 's/.*"version": *"([^"]+)".*/\1/p' plugin/.claude-plugin/plugin.json | head -1)"
[ "$plug" = "$want" ] || note "plugin/.claude-plugin/plugin.json version is '$plug', expected '$want'"
mkt="$(sed -nE 's/.*"version": *"([^"]+)".*/\1/p' .claude-plugin/marketplace.json | head -1)"
[ "$mkt" = "$want" ] || note ".claude-plugin/marketplace.json plugin version is '$mkt', expected '$want'"

# install.sh must read the macOS bundle version from package.json, never hardcode
# it — the plist lines must interpolate \$ver, not a literal semver.
if grep -nE 'CFBundle(Short)?Version(String)?</key><string>[0-9]+\.[0-9]+\.[0-9]+<' install.sh; then
    note "install.sh hardcodes a bundle version — it must use \$ver from package.json"
fi

if [ "$fail" -ne 0 ]; then
    echo "check-versions: drift detected — run scripts/bump-version.sh <ver> to sync." >&2
    exit 1
fi
echo "check-versions: all version sites match $want"
