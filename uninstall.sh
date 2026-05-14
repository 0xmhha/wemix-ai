#!/bin/bash
# go-wemix Claude Code 플러그인 제거 스크립트
#
# 사용법 (curl):  curl -fsSL -H "Authorization: token $(gh auth token)" \
#                   https://raw.githubusercontent.com/0xmhha/wemix-ai/main/uninstall.sh | bash
# 사용법 (로컬): ./uninstall.sh /path/to/go-wemix

set -e

TARGET_DIR="${1:-${GO_WEMIX_DIR:-$(pwd)}}"

echo "=== go-wemix Claude Code 플러그인 제거 ==="
echo "대상 디렉토리: $TARGET_DIR"

if [ -d "$TARGET_DIR/.claude" ]; then
    rm -rf "$TARGET_DIR/.claude"
    echo "삭제: $TARGET_DIR/.claude/"
fi

if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    rm "$TARGET_DIR/CLAUDE.md"
    echo "삭제: $TARGET_DIR/CLAUDE.md"
fi

echo "=== 제거 완료 ==="
