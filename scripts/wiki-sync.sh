#!/usr/bin/env bash
# Publish wiki/ to the GitHub wiki (<repo>.wiki.git). The wiki/ directory in
# this repo is the single source of truth - pages are edited and reviewed here,
# and this script mirrors them to the wiki repo (deleting pages removed from
# wiki/). Runs in CI on every push that touches wiki/** (.github/workflows/
# wiki.yml); can also be run locally, where the push goes through the usual
# push-confirm safety.
#
#   scripts/wiki-sync.sh              # mirror wiki/ → the GitHub wiki
#   WIKI_URL=<url> scripts/wiki-sync.sh   # override the wiki remote (CI token URL)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI_URL="${WIKI_URL:-https://github.com/fschmutz/claude-usage-panel.wiki.git}"

if [ ! -d "$ROOT/wiki" ]; then
    echo "wiki-sync: no wiki/ directory in $ROOT" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> Cloning wiki"
git clone -q "$WIKI_URL" "$tmp/wiki"

echo "==> Mirroring wiki/ → wiki repo"
find "$tmp/wiki" -maxdepth 1 -name '*.md' -delete
cp "$ROOT"/wiki/*.md "$tmp/wiki/"

cd "$tmp/wiki"
if git diff --quiet && [ -z "$(git status --porcelain)" ]; then
    echo "wiki-sync: wiki already up to date"
    exit 0
fi

git add -A
# CI has no user identity configured; set a local one if missing.
git config user.name >/dev/null 2>&1 || git config user.name "wiki-sync"
git config user.email >/dev/null 2>&1 || git config user.email "wiki-sync@users.noreply.github.com"
git commit -m "docs(wiki): sync from main repo wiki/"

# In CI (no alias) this is a plain push; locally the push-confirm alias applies.
git push
echo "==> Wiki published"
