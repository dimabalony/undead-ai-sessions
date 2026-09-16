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
  # The latest release, falling back to main when GitHub gives nothing. The tag comes from the redirect the release
  # page performs, because the API allows only 60 unauthenticated calls an hour per network address and a shared
  # office address runs out of them; the API is the fallback. This repeats `undead upgrade`'s lookup on purpose:
  # install.sh runs before undead exists, so it can't source lib/common.zsh and stays POSIX sh.
  TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$REPO/releases/latest" 2>/dev/null |
        sed -n 's|.*/tag/\(v[0-9][0-9.]*\)$|\1|p')
  if [ -z "$TAG" ]; then
    TAG=$(curl -fsSL "https://api.github.com/repos/dimabalony/undead-ai-sessions/releases/latest" 2>/dev/null |
          sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  fi
  case "$TAG" in v[0-9]*.[0-9]*.[0-9]*) ;; *) TAG= ;; esac
  if [ -n "$TAG" ]; then
    echo "Downloading undead $TAG..."
    URL="$REPO/archive/refs/tags/$TAG.tar.gz"
  else
    echo "Downloading undead..."
    URL="$REPO/archive/refs/heads/main.tar.gz"
  fi
  curl -fsSL "$URL" | tar -xz -C "$TMP" --strip-components 1
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
