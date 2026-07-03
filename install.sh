#!/usr/bin/env bash
# Install Claude Usage Panel into the user's GNOME Shell extensions directory.
set -euo pipefail

UUID="claude-usage-panel@fschmutz.github.io"
SRC="$(cd "$(dirname "$0")" && pwd)/$UUID"
DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

if [ ! -d "$SRC" ]; then
    echo "Source directory not found: $SRC" >&2
    exit 1
fi

echo "Installing to $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"

# Compile the GSettings schema in place.
glib-compile-schemas "$DEST/schemas/"

echo
echo "Installed. Next:"
echo "  1. Log out and back in (Wayland requires this to load a new extension)."
echo "  2. gnome-extensions enable $UUID"
echo "  3. Sign in with Claude Code if you have not (creates ~/.claude/.credentials.json)."
