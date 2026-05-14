#!/bin/bash
# go-wemix Claude Code 플러그인 로컬 설치 스크립트
# 사용법: ./install-local.sh /path/to/go-wemix

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${1:-${GO_WEMIX_DIR:-}}"

if [ -z "$TARGET_DIR" ]; then
    echo "사용법: $0 /path/to/go-wemix"
    echo "또는: GO_WEMIX_DIR=/path/to/go-wemix $0"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "오류: 디렉토리가 존재하지 않습니다: $TARGET_DIR"
    exit 1
fi

# go-wemix 프로젝트 루트 검증
if [ ! -f "$TARGET_DIR/go.mod" ] || ! grep -q 'module github.com/ethereum/go-ethereum' "$TARGET_DIR/go.mod" 2>/dev/null; then
    echo "오류: go-wemix(geth fork) 프로젝트 루트가 아닙니다."
    echo "go.mod에서 'module github.com/ethereum/go-ethereum' 선언을 찾지 못했습니다."
    exit 1
fi

if [ ! -d "$TARGET_DIR/wemix" ]; then
    echo "오류: wemix/ 디렉토리가 없습니다."
    echo "이 플러그인은 go-wemix 전용입니다."
    exit 1
fi

echo "=== go-wemix Claude Code 플러그인 설치 ==="
echo "대상: $TARGET_DIR"
echo ""

# 기존 파일 백업
if [ -d "$TARGET_DIR/.claude" ]; then
    BACKUP_DIR="$TARGET_DIR/.claude.backup.$(date +%Y%m%d%H%M%S)"
    echo "기존 .claude/ 백업: $BACKUP_DIR"
    cp -r "$TARGET_DIR/.claude" "$BACKUP_DIR"
fi

if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    BACKUP_FILE="$TARGET_DIR/CLAUDE.md.backup.$(date +%Y%m%d%H%M%S)"
    echo "기존 CLAUDE.md 백업: $BACKUP_FILE"
    cp "$TARGET_DIR/CLAUDE.md" "$BACKUP_FILE"
fi

# 디렉토리 생성
mkdir -p "$TARGET_DIR/.claude/agents"
mkdir -p "$TARGET_DIR/.claude/commands"
mkdir -p "$TARGET_DIR/.claude/docs"
mkdir -p "$TARGET_DIR/.claude/skills/wemix-governance-workflow"

# 파일 복사
echo "파일 복사 중..."

cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"

# 에이전트
cp "$SCRIPT_DIR/.claude/agents/pr-reviewer.md" "$TARGET_DIR/.claude/agents/pr-reviewer.md"

# 커맨드
cp "$SCRIPT_DIR/.claude/commands/wemix-review-code.md" "$TARGET_DIR/.claude/commands/wemix-review-code.md"

# 문서
for doc in BUILD_SOURCE_FILES.md CLAUDE_DEV_GUIDE.md GOVERNANCE_FLOW.md REVIEW_GUIDE.md; do
    cp "$SCRIPT_DIR/.claude/docs/$doc" "$TARGET_DIR/.claude/docs/$doc"
done

# 스킬
cp "$SCRIPT_DIR/.claude/skills/wemix-governance-workflow/SKILL.md" \
   "$TARGET_DIR/.claude/skills/wemix-governance-workflow/SKILL.md"

echo ""
echo "=== 설치 완료 ==="
echo ""
echo "설치된 파일:"
echo "  $TARGET_DIR/CLAUDE.md"
echo "  $TARGET_DIR/.claude/settings.json"
echo "  $TARGET_DIR/.claude/agents/pr-reviewer.md"
echo "  $TARGET_DIR/.claude/commands/wemix-review-code.md"
echo "  $TARGET_DIR/.claude/docs/ (4개 문서)"
echo "  $TARGET_DIR/.claude/skills/wemix-governance-workflow/SKILL.md"
echo ""
echo "사용법:"
echo "  cd $TARGET_DIR"
echo "  claude  # Claude Code 실행"
echo "  /wemix-review-code [질문]  # 코드 리뷰 커맨드"
