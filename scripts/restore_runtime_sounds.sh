#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/Assets/SoundsSeed"
TARGET_DIR="$HOME/Library/Application Support/SlapForce/Sounds"

mkdir -p "$TARGET_DIR"

find "$SOURCE_DIR" -maxdepth 1 -type f ! -name '.DS_Store' -exec cp -f {} "$TARGET_DIR/" \;

echo "Restored sounds from:"
echo "  $SOURCE_DIR"
echo "to:"
echo "  $TARGET_DIR"
