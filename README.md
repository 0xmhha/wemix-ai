# wemix-ai — go-wemix Claude Code Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet)](https://docs.anthropic.com/en/docs/claude-code/overview)

Claude Code configuration package for the [go-wemix](https://github.com/wemixarchive/go-wemix) blockchain client.

When installed into the go-wemix project root, Claude Code gains accurate understanding of the codebase — distinguishing Wemix-specific code from geth, governance contracts from Solidity sources, etcd-based mining-token logic, the Pangyo → Applepie → Brioche hardfork chain, and the security invariants that must not be regressed.

> Tracking go-wemix `dev` @ `4e0005fbe` (**v0.10.14-stable**), verified 2026-07-29.

## Table of Contents

- [What This Provides](#what-this-provides)
- [Installation](#installation)
- [Usage](#usage)
- [File Structure After Installation](#file-structure-after-installation)
- [Uninstall](#uninstall)
- [Prerequisites](#prerequisites)
- [Design Principles](#design-principles)
- [Contributing](#contributing)
- [License](#license)

## What This Provides

- **Project Context** (`CLAUDE.md`) — Project overview, build, hardfork chain, go-wemix-specific code map, and a security-invariant table of defenses that must not be reverted
- **Settings** (`.claude/settings.json`) — Hooks (auto-generated file warnings, pre-commit reminder) and approved Bash command allowlist (make / go test / golangci-lint / gh / git)
- **Code Review Command** (`.claude/commands/wemix-review-code.md`) — `/wemix-review-code` slash command with project context loading
- **PR Reviewer Agent** (`.claude/agents/pr-reviewer.md`) — Sub-agent that auto-detects project analysis tools (golangci-lint, Makefile, .claude/docs) and runs structured PR reviews
- **Governance Workflow Skill** (`.claude/skills/wemix-governance-workflow/`) — End-to-end workflow for Solidity → solc 0.8.14 → abigen → Registry/Gov deploy
- **Dev Guide** (`.claude/docs/CLAUDE_DEV_GUIDE.md`) — Build system, architecture, hardforks, Fee Delegation (`RecoverFeePayer` single entry point), Brioche halving, etcd cluster, `syncCheck` guard chain, and §15 StatusEx trust boundary / `wemixWorkKey` protection
- **Governance Flow** (`.claude/docs/GOVERNANCE_FLOW.md`) — Registry/Gov/Staking/EnvStorage/BallotStorage/NCPExit deploy & upgrade flow, plus §6 GovImp security invariants (removed arbitrary-execute proposals, member-index integrity, CertiK W1G-01~04)
- **Review Guide** (`.claude/docs/REVIEW_GUIDE.md`) — Question-type exploration guide, consensus flow, Wemix-specific review dimensions, response format
- **Build Reference** (`.claude/docs/BUILD_SOURCE_FILES.md`) — Every file in the `gwemix` build (120 packages / 630 files) and the `logrot` build, **plus the 302 test files attached to those packages** and which ones cover Wemix-specific code

## Installation

> **Must be run from the go-wemix project root.**
>
> This is a private repository. [GitHub CLI](https://cli.github.com/) (`gh`) login is required.

### Method 1: One-liner (Recommended)

Run from the **go-wemix project root** (requires `gh auth login`):

```bash
curl -fsSL -H "Authorization: token $(gh auth token)" \
  https://raw.githubusercontent.com/0xmhha/wemix-ai/main/install.sh | bash
```

Or specify the project path explicitly:

```bash
GO_WEMIX_DIR=/path/to/go-wemix \
  curl -fsSL -H "Authorization: token $(gh auth token)" \
  https://raw.githubusercontent.com/0xmhha/wemix-ai/main/install.sh | bash
```

> **Note:** The install script auto-detects the `gh` CLI token. You can also set `GITHUB_TOKEN` explicitly:
> ```bash
> GITHUB_TOKEN=ghp_xxx curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
>   https://raw.githubusercontent.com/0xmhha/wemix-ai/main/install.sh | bash
> ```

### Method 2: Git Clone + Local Install

```bash
git clone https://github.com/0xmhha/wemix-ai.git
cd wemix-ai
./install-local.sh /path/to/go-wemix
```

### Method 3: Manual Install

```bash
cd /path/to/go-wemix
mkdir -p .claude/agents .claude/commands .claude/docs .claude/skills/wemix-governance-workflow

TOKEN=$(gh auth token)
BASE=https://raw.githubusercontent.com/0xmhha/wemix-ai/main
AUTH="-H \"Authorization: token $TOKEN\""

curl -fsSL $AUTH $BASE/CLAUDE.md -o CLAUDE.md
curl -fsSL $AUTH $BASE/.claude/settings.json -o .claude/settings.json
curl -fsSL $AUTH $BASE/.claude/agents/pr-reviewer.md -o .claude/agents/pr-reviewer.md
curl -fsSL $AUTH $BASE/.claude/commands/wemix-review-code.md -o .claude/commands/wemix-review-code.md
for doc in BUILD_SOURCE_FILES CLAUDE_DEV_GUIDE GOVERNANCE_FLOW REVIEW_GUIDE; do
  curl -fsSL $AUTH $BASE/.claude/docs/${doc}.md -o .claude/docs/${doc}.md
done
curl -fsSL $AUTH $BASE/.claude/skills/wemix-governance-workflow/SKILL.md \
  -o .claude/skills/wemix-governance-workflow/SKILL.md
```

## Usage

```bash
cd /path/to/go-wemix
claude
```

### Code Review Command

```
/wemix-review-code wemixAdmin 마이닝 토큰 흐름을 설명해줘
/wemix-review-code feedelegate_dynamic_fee_tx의 서명 검증 로직은?
/wemix-review-code 거버넌스 컨트랙트 배포 흐름을 분석해줘
/wemix-review-code Brioche halving 곡선 적용 분기는?
```

The command supports:
- Function/type explanations
- Call-flow tracing
- Impact analysis for modifications
- Wemix consensus / mining token / etcd cluster
- Governance contract architecture & UUPS upgrades
- Fee Delegation transaction handling
- Brioche halving & reward distribution
- Hardfork and upgrade paths

### PR Review Sub-Agent

Invoke the `pr-reviewer` agent (e.g., via the Agent tool or by asking Claude to review a PR). It auto-detects:

- `.golangci.yml` → runs `golangci-lint`
- Makefile targets (`gwemix`, `lint`, `test-short`) → runs build/lint/test
- `.claude/docs/` → loads project context

Produces a `REVIEW_REPORT.md` with critical/warning/suggestion findings classified by Wemix-specific perspectives (consensus safety, governance consistency, hardfork gating, reward distribution, Fee Delegation, etc.).

### Governance Workflow Skill

Activated by keywords (거버넌스 컨트랙트, GovImp, EnvStorage, Registry, governancedeploy, abigen, ...) or explicit user invocation. Provides layered procedure:

```
Layer 0: 사전 점검 (solc 0.8.14 / 변경 유형 분류)
Layer 1: Solidity 소스 변경 (UUPS 스토리지 호환성)
Layer 2: solc 0.8.14 컴파일
Layer 3: abigen → wemix/bind/gen_*_abi.go 재생성
Layer 4: wemix/admin.go 호출 코드
Layer 5: 제네시스 / 거버넌스 배포 동기화
Layer 6: 하드포크 게이팅 (Optional)
Layer 7: 검증 (build / lint / test)
```

## File Structure After Installation

```
go-wemix/
├── CLAUDE.md                                  # Project context for Claude Code
└── .claude/
    ├── settings.json                          # Hooks + Bash allowlist
    ├── agents/
    │   └── pr-reviewer.md                     # Auto-detecting PR review sub-agent
    ├── commands/
    │   └── wemix-review-code.md               # /wemix-review-code slash command
    ├── docs/
    │   ├── BUILD_SOURCE_FILES.md              # gwemix + logrot build files & their tests
    │   ├── CLAUDE_DEV_GUIDE.md                # Dev guide (build/arch/hardfork/etcd/security)
    │   ├── GOVERNANCE_FLOW.md                 # Governance deploy, upgrade & security invariants
    │   └── REVIEW_GUIDE.md                    # Code review exploration guide
    └── skills/
        └── wemix-governance-workflow/
            └── SKILL.md                       # Solidity → abigen → deploy workflow
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/0xmhha/wemix-ai/main/uninstall.sh | bash
```

Or run locally:

```bash
./uninstall.sh /path/to/go-wemix
```

> **Note:** The path argument is required when running locally. Without it, the script defaults to the current directory and will remove `.claude/` and `CLAUDE.md` from wherever you run it.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) installed
- [go-wemix](https://github.com/wemixarchive/go-wemix) project cloned locally
- [GitHub CLI](https://cli.github.com/) (`gh`) — for one-liner install of this private repo

## Design Principles

1. **Token-efficient** — Docs split by topic; only relevant sections are loaded on demand
2. **Build-based** — References only the files actually included in `gwemix` / `logrot` (`go list -deps`), regenerable with the commands in `BUILD_SOURCE_FILES.md` §8
3. **Test-aware** — Every build-participating package is mapped to its test files, so a change lands with the right regression suite
4. **geth-distinct** — Clearly separates Wemix-specific code from geth origin
5. **Terminology-accurate** — `wemixgov` not `systemcontracts`, `gwemix` not `gstable`, `wemixAdmin` not `bridgeAdmin`
6. **Index-driven** — Question classifier + keyword → file → heading lookup; references load only when needed
7. **Regression-resistant** — Documents the defenses that already shipped *and the mitigations that were deliberately rejected*, so a plausible-looking "improvement" doesn't reintroduce a known vulnerability or a known false-positive
8. **Safe-by-default settings** — Hooks warn before editing auto-generated files (`wemix/bind/gen_*_abi.go`) and embedded genesis (`core/wemix_genesis.go`)

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, submitting pull requests, and updating documentation.

## License

MIT
