#!/bin/sh
# fleet installer — run via: curl -fsSL <url> | sh
set -e

RELEASE_URL="https://gitlab.com/nighthawk-oss/fleet/-/raw/main"

INSTALL_DIR="$HOME/.fleet"
INSTALL_PATH="$INSTALL_DIR/fleet.sh"

# Download
mkdir -p "$INSTALL_DIR"
echo "Downloading fleet..."
curl -fsSL "$RELEASE_URL/fleet.sh" -o "$INSTALL_PATH"
curl -fsSL "$RELEASE_URL/VERSION" | tr -d '[:space:]' > "$INSTALL_DIR/VERSION"

# Clear stale update-check cache from any previous install
rm -f "$INSTALL_DIR/.latest_version" "$INSTALL_DIR/.last_check"

# Detect shell rc file
case "$SHELL" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  *)      RC_FILE="$HOME/.bashrc" ;;
esac

SOURCE_LINE='source "$HOME/.fleet/fleet.sh"'

# Idempotently add source line
if ! grep -qF '.fleet/fleet.sh' "$RC_FILE" 2>/dev/null; then
  printf '\n# fleet\n%s\n' "$SOURCE_LINE" >> "$RC_FILE"
  echo "Added source line to $RC_FILE"
else
  echo "Source line already in $RC_FILE"
fi

echo ""
echo "fleet installed! To start using it:"
echo "  source $RC_FILE"
