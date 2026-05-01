#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_SOUNDS="$HOME/Library/Application Support/SlapForce/Sounds"
SEED_SOUNDS="$REPO_ROOT/Assets/SoundsSeed"
README_PATH="$REPO_ROOT/README.md"
GUIDE_PATH="$REPO_ROOT/docs/CONTINUE_WITH_CODEX.md"

echo "SlapForce resume context"
echo
echo "Project:"
echo "  $REPO_ROOT"
echo
echo "Read first:"
echo "  $README_PATH"
echo "  $GUIDE_PATH"
echo
echo "Runtime sounds:"
echo "  $RUNTIME_SOUNDS"
echo
echo "Repo seed sounds:"
echo "  $SEED_SOUNDS"
echo
echo "Suggested new-thread prompt:"
echo
cat <<EOF
继续开发 SlapForce。
项目在 $REPO_ROOT
先读 README.md 和 docs/CONTINUE_WITH_CODEX.md。
如果需要声音素材，先检查：
$RUNTIME_SOUNDS
和
$SEED_SOUNDS
是否一致。
然后继续当前优化工作。
EOF
