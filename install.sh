#!/bin/sh
# Installs undead into ~/.local/share/undead, links the `undead` command into ~/.local/bin and runs `undead install`.
# From a checkout:  ./install.sh
# Without one:      curl -fsSL https://raw.githubusercontent.com/dimabalony/undead-ai-sessions/main/install.sh | sh
# Options are passed on to `undead install` (e.g. --no-codex).
set -eu

REPO=https://github.com/dimabalony/undead-ai-sessions
DEST="$HOME/.local/share/undead"
BIN="$HOME/.local/bin"

[ "$(uname -s)" = Darwin ] || { echo "undead only supports macOS" >&2; exit 1; }
command -v zsh >/dev/null || { echo "undead needs zsh" >&2; exit 1; }

SRC=$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)
if [ ! -f "$SRC/lib/hook" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading undead..."
  curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP" --strip-components 1
  SRC=$TMP
fi

mkdir -p "$DEST" "$BIN"
rm -rf "$DEST/bin" "$DEST/lib"
cp -R "$SRC/bin" "$SRC/lib" "$DEST/"
chmod +x "$DEST/bin/undead" "$DEST/lib/hook"
ln -sf "$DEST/bin/undead" "$BIN/undead"

"$DEST/bin/undead" install "$@"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo; echo "Add ~/.local/bin to your PATH to use the undead command, e.g.:"; echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc" ;;
esac
