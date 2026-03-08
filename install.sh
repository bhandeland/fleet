#!/bin/sh
# fleet installer — run via: curl -fsSL <url> | sh
set -e

RELEASE_URL="https://gitlab.com/nighthawk-oss/fleet/-/raw/main"

INSTALL_DIR="$HOME/.local/bin"
FLEET_DIR="$HOME/.fleet"
INSTALL_PATH="$INSTALL_DIR/fleet"

# Download
mkdir -p "$INSTALL_DIR" "$FLEET_DIR"
echo "Downloading fleet..."
curl -fsSL "$RELEASE_URL/fleet.sh" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
curl -fsSL "$RELEASE_URL/VERSION" | tr -d '[:space:]' > "$FLEET_DIR/VERSION"

# Clear stale update-check cache from any previous install
rm -f "$FLEET_DIR/.latest_version" "$FLEET_DIR/.last_check"

# Install Claude Code skills
SKILLS_DIR="$HOME/.claude/skills"
for skill in fleet dispatch fleet-cleanup; do
  mkdir -p "$SKILLS_DIR/$skill"
  curl -fsSL "$RELEASE_URL/.claude/skills/$skill/SKILL.md" -o "$SKILLS_DIR/$skill/SKILL.md"
done
echo "Installed Claude Code skills: /fleet, /dispatch, /fleet-cleanup"

# Clean up old sourced install if present
rm -f "$FLEET_DIR/fleet.sh"

# Detect shell rc file
case "$SHELL" in
  */zsh)  RC_FILE="$HOME/.zshrc" ;;
  *)      RC_FILE="$HOME/.bashrc" ;;
esac

EVAL_LINE='eval "$(fleet init-shell)"'

# Remove old source line if present
if grep -qF '.fleet/fleet.sh' "$RC_FILE" 2>/dev/null; then
  tmp="$(mktemp)"
  grep -vF '.fleet/fleet.sh' "$RC_FILE" > "$tmp" && mv "$tmp" "$RC_FILE"
  echo "Removed old source line from $RC_FILE"
fi

# Idempotently add eval line
if ! grep -qF 'fleet init-shell' "$RC_FILE" 2>/dev/null; then
  printf '\n# fleet\n%s\n' "$EVAL_LINE" >> "$RC_FILE"
  echo "Added eval line to $RC_FILE"
else
  echo "Eval line already in $RC_FILE"
fi

# Check if ~/.local/bin is in PATH
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "Note: $INSTALL_DIR is not in your PATH."
    echo "Add this to your $RC_FILE:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo ""
echo "fleet installed! To start using it:"
echo "  source $RC_FILE"
