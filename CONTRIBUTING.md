# Contributing

Thanks for contributing.

## Scope

This repo is a minimal, portable environment pack for shell, tmux, and AI CLI tooling.
Keep changes focused, explicit, and reversible.

## Development Workflow

1. Fork and create a branch.
2. Make small, isolated changes.
3. Run basic checks:
   - `bash -n install.sh`
   - `bash -n update.sh`
   - `zsh -n configs/zsh/zshrc`
4. Update docs when behavior changes.
5. Open a pull request with:
   - problem statement
   - change summary
   - validation evidence

## Safety Rules

- Do not commit secrets.
- Keep all credentials/env-sensitive values as placeholders.
- Avoid destructive behavior in installer scripts.
- Preserve existing user files unless explicitly replacing managed targets.

## PR Guidelines

- Prefer clear commit messages (`feat:`, `fix:`, `chore:`).
- Include before/after examples for user-facing shell behavior.
- Keep platform assumptions explicit (this repo is macOS-first).
