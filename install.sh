#!/usr/bin/env bash
# Install Claude multi-agent pipeline global commands
# Run from the repo root: bash install.sh

set -e

COMMANDS_DIR="$HOME/.claude/commands"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude pipeline global commands..."
mkdir -p "$COMMANDS_DIR"

for cmd in bootstrap backlog reformat-backlog; do
  src="$REPO_DIR/commands/${cmd}.md"
  dst="$COMMANDS_DIR/${cmd}.md"
  if [ -f "$dst" ]; then
    echo "  ⚠️  $dst already exists — skipping (delete it first to reinstall)"
  else
    cp "$src" "$dst"
    echo "  ✅  Installed ${cmd}.md"
  fi
done

echo ""
echo "Done. Open Claude Code in any repo and run /bootstrap to set it up."
