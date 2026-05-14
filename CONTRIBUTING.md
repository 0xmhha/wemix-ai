# Contributing to wemix-ai

## Reporting Issues

Open a [GitHub Issue](https://github.com/0xmhha/wemix-ai/issues) and include:

- Claude Code version (`claude --version`)
- go-wemix commit hash (`git rev-parse HEAD` in the go-wemix repo)
- Steps to reproduce the problem
- What you expected vs. what happened

## Submitting Pull Requests

1. Fork the repository and create a branch from `main`:
   ```
   git checkout -b feat/your-change
   ```
2. Make your changes (see guidelines below).
3. Open a PR against `main`. Use a conventional commit-style title (see below).

Keep PRs focused — one logical change per PR.

## Development Setup

```bash
# Clone
git clone https://github.com/0xmhha/wemix-ai.git
cd wemix-ai

# Test locally against your go-wemix clone
./install-local.sh /path/to/go-wemix

# Verify the slash command loads correctly inside that project
# Open Claude Code in go-wemix and run /wemix-review-code
```

Use `uninstall.sh` to clean up before reinstalling:

```bash
./uninstall.sh /path/to/go-wemix
```

> **Note:** The path argument is required. Without it, the script defaults to the current directory and will remove `.claude/` and `CLAUDE.md` from wherever you run it.

## Updating Documentation

The docs live in `.claude/docs/`. A few rules:

- **Keep files lean** — 500 lines max per file. Split into a new doc if needed. (`BUILD_SOURCE_FILES.md` is auto-generated and exempt.)
- **Section numbers** — New sections in existing docs use the next available `§N` number (e.g., `§18`, `§19`). Do not renumber existing sections.
- **Keyword index** — `.claude/commands/wemix-review-code.md` and `.claude/skills/wemix-governance-workflow/SKILL.md` reference the docs by path. Update them whenever you add or rename a section.
- **Test before opening a PR** — Install locally with `install-local.sh`, open Claude Code in go-wemix, and confirm `/wemix-review-code` and the `wemix-governance-workflow` skill behave as expected with the changed content.
- **`CLAUDE.md`** — Project-level context doc. Edit only for project-scope changes (new docs added, install path changes, etc.).
- **`.claude/settings.json`** — Hooks and Bash allowlist. Add new allowlist entries when introducing new tooling; keep hook payloads under 1KB.

## Updating Install Scripts

Changes to `install.sh` / `install-local.sh` / `uninstall.sh` should preserve:

- **Backup behavior** — Existing `.claude/` and `CLAUDE.md` are backed up with timestamp before overwrite
- **Project detection** — `go.mod` must declare `module github.com/ethereum/go-ethereum` and `wemix/` directory must exist
- **Idempotency** — Re-running should produce the same result (backup → install)
- **Token-aware download** — `install.sh` uses `Authorization: token` header for private repo

When adding a new file to the plugin:

1. Add it under `.claude/` in this repo
2. Update `install.sh` (add `download` call)
3. Update `install-local.sh` (add `cp` call)
4. Update `README.md` "File Structure After Installation"

## Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <short description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

Examples:

```
docs: add §18 NCPExit-flow section to GOVERNANCE_FLOW
fix: correct go.mod detection in install-local.sh for symlinked paths
chore: add make rocksdb to settings.json Bash allowlist
```

- Write in English.
- Keep the subject line under 72 characters.
- No co-author lines.

## Code of Conduct

This project follows the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
