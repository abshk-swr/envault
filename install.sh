#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 Installing envault..."

if [ ! -f "$REPO_DIR/envault" ]; then
    echo "❌ Error: Could not find envault executable at $REPO_DIR/envault"
    exit 1
fi

chmod +x "$REPO_DIR/envault"
chmod +x "$REPO_DIR/install.sh"

mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/envault" "$HOME/.local/bin/envault"

echo "✅ Symlink created successfully at ~/.local/bin/envault"
echo "💡 Make sure ~/.local/bin is in your system PATH!"
