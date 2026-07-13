#!/usr/bin/env bash
# Bump the project version in every place that carries it, from a single source
# of truth, so they can never drift:
#
#   • package.json               "version"          (macOS bundle reads this)
#   • metadata.json              "version-name"     (GNOME extension manifest)
#   • PUBLISHING.md              Homebrew cask       version "…"
#   • CHANGELOG.md               opens a dated section, leaves a fresh [Unreleased]
#
# Usage:  scripts/bump-version.sh 1.4.0
# It only edits files — review the diff, then commit. Nothing is pushed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

V="${1:-}"
if ! [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/bump-version.sh <major.minor.patch>   e.g. 1.4.0" >&2
    exit 2
fi
DATE="$(date +%F)"

# JSON files — edit with Node so formatting/key order is preserved exactly.
V="$V" node <<'JS'
const fs = require('fs');
const v = process.env.V;
for (const [f, key] of [
  ['package.json', 'version'],
  ['claude-usage-panel@fschmutz.github.io/metadata.json', 'version-name'],
]) {
  const j = JSON.parse(fs.readFileSync(f, 'utf8'));
  j[key] = v;
  fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
  console.log(`  ${f} → ${v}`);
}
JS

# Homebrew cask example in PUBLISHING.md: `  version "x.y.z"`.
V="$V" perl -pi -e 's/^(  version ")\d+\.\d+\.\d+(")/${1}$ENV{V}${2}/' PUBLISHING.md
echo "  PUBLISHING.md cask → $V"

# CHANGELOG: turn the top [Unreleased] into a dated release, above a fresh one.
V="$V" DATE="$DATE" perl -pi -e '
  if (!$seen && /^## \[Unreleased\]/) {
    $_ .= "\n## [$ENV{V}] — $ENV{DATE}\n";
    $seen = 1;
  }' CHANGELOG.md
echo "  CHANGELOG.md → ## [$V] — $DATE (with a fresh [Unreleased])"

echo
echo "Bumped to $V. Review the diff, then commit:"
echo "  git -C \"$ROOT\" add -A && git -C \"$ROOT\" commit -m \"chore(release): v$V\""
