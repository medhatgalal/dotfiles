# Global Agent Operating Rules (Home Scope)

This file defines global behavior for AI agents running in your home environment.
It applies across CLIs (`gemini`, `claude`, `kiro`, `codex`) unless a repo-local policy is stricter.

## Scope
- Treat the working directory as potentially valuable user data.
- Prefer repo-local instructions when present (`AGENTS.md`, `.engos/`, project docs).
- If there is conflict, follow the stricter safety rule.

## Safety First (Non-Negotiable)
- Never run destructive commands without explicit user confirmation.
- Never run `rm -rf`, recursive `mv`, recursive overwrite/copy, or broad/glob deletes in home/global paths without approval.
- Prefer safe deletion via `trash` instead of permanent delete when cleanup is requested.
- Before deleting or moving anything outside the current repo, restate the exact targets and ask.
- If unsure whether a change is destructive, stop and ask.

## File Operations
- Default to read-only inspection until intent is clear.
- For edits, minimize blast radius and touch only requested files.
- Preserve user customizations; do not normalize or reformat unrelated files.
- Do not overwrite secrets files with templates when an existing file is present.

## Environment & Secrets
- Keep secrets in `~/.secrets.env` (or project-specific secret stores), not in tracked config files.
- Use environment-variable placeholders in shared templates.
- Do not print secret values in logs or summaries.

## Git & Change Discipline
- Do not reset/revert unrelated changes.
- Do not use destructive git commands (`reset --hard`, `checkout --`, force pushes) unless explicitly approved.
- Keep changes auditable and explain what was changed and why.

## Beads / EngOS Expectations
- Use Beads/EngOS workflows where present.
- Prefer deterministic CLI invocations and verifiable outcomes.
- Report failures with exact command context and actionable remediation.

## Communication Contract
- Before major changes, state intent and affected paths.
- After changes, provide a concise result with file references.
- If any action could impact active sessions, long-running processes, or user data, warn first.
