#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$HOME/Library/Application Support/SlapForce/Sounds"
TARGET_DIR="$REPO_ROOT/Assets/SoundsSeed"

mkdir -p "$TARGET_DIR"

find "$TARGET_DIR" -maxdepth 1 -type f ! -name '.DS_Store' -delete
find "$SOURCE_DIR" -maxdepth 1 -type f ! -name '.DS_Store' -exec cp -f {} "$TARGET_DIR/" \;

echo "Synced sounds from:"
echo "  $SOURCE_DIR"
echo "to:"
echo "  $TARGET_DIR"
