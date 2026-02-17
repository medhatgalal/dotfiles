# Minimal Dotfiles (EngOS Baseline)

Canonical path on this machine: `~/Desktop/dotfiles`.
Embedded copies also live at `scripts/setup/dotfiles` inside repos.

This package installs a minimal, portable local environment for EngOS workflows:
- guarded zsh startup (PTY-safe Kiro bootstrap)
- explicit zsh vi-mode defaults for interactive shells
- automatic Powerlevel10k Meslo Nerd Font installation
- generic tmux UX helpers (main/watcher pane flow)
- minimal CLI config files (`.gemini`, `.claude`, `.kiro`, AGENTS docs)
- software updater with strict Beads Dolt+CGO verification and self-heal

## What Is Managed

- `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.zsh/aliases/*.zsh`
- `~/.tmux.conf`, `~/.local/bin/{pty-clean-safe,tmux-*}`
- `~/.gemini/settings.json`, `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`
- `~/.claude/settings.json`, `~/.claude/AGENTS.md`, `~/.claude/CLAUDE.md`
- `~/.kiro/settings/{cli.json,mcp.json}`, `~/.kiro/steering/AGENTS.md`
- `~/.codex/AGENTS.md`
- `~/update_software.sh`

## Token Precedence

- Set `GITLAB_READ_WRITE_TOKEN` in `~/.secrets.env` as the primary GitLab token.
- `~/.zshrc` maps `GITLAB_READ_WRITE_TOKEN` to `GITLAB_TOKEN` for compatibility.
- Kiro MCP GitLab config consumes `GITLAB_READ_WRITE_TOKEN` directly.

## What Is Not Managed

- prompt-pack hydration into repo-local `.gemini/.claude/.codex`
- repo-specific tmuxinator session files
- CLI history/cache/session artifacts

## Install

```bash
cd ~/Desktop/dotfiles
./install.sh
```

Non-interactive:

```bash
./install.sh --yes
```

Dry run:

```bash
./install.sh --dry-run
```

Install into a local repo path (intent: embed this package into the repo):

```bash
./install.sh --repo-path ~/Desktop/shapeup-base-v6clone
```

Result:
- `~/Desktop/shapeup-base-v6clone/scripts/setup/dotfiles` becomes the repo-local install source.

## Update Software + Beads Runtime

```bash
~/update_software.sh -i
```

This updater enforces:
- Homebrew `bd` install path
- Dolt backend runtime validation (`bd init --backend dolt` smoke test)
- CGO regression detection
- repo-local Beads self-heal when run inside a repo with `.beads/`
- core shell tools including `eza`
- Meslo Nerd Font cask (`font-meslo-lg-nerd-font`)

## Shell Ergonomics

- zsh vi-mode is enabled by default in interactive shells (`bindkey -v`).
- `KEYTIMEOUT` defaults to `20` (override with `DOTFILES_ZSH_KEYTIMEOUT`).
- Kiro terminal sessions inherit this behavior because they source the same `~/.zshrc`.
- Installer also installs Meslo Nerd Fonts for p10k when Homebrew is available.
- Installer can also update iTerm2 profile fonts automatically to Meslo Nerd Font.
- For terminal apps other than iTerm2, set profile font manually to `MesloLGS Nerd Font` (or `MesloLGS NF`).

`ls` aliases are resilient:
- If `eza` is installed: `ls`, `ll`, `la`, `lt` use `eza`.
- If `eza` is missing: aliases gracefully fall back to native commands.

## Tmux Main/Watcher Pattern

Inside tmux:
- `Prefix + 1` -> main/watcher layout
- `Prefix + y` -> copy last pane output
- `Prefix + Y` -> preview last pane output
- `Prefix + ?` -> full help popup

Shell helpers:
- `tmux-main-watch`
- `tmux-copy-main`
- `tmux-read-main`

Capture depth defaults to `3000` lines and is configurable:
- shell env: `export TMUX_PANE_READ_LINES=5000`
- tmux options: `set -g @pane_read_lines 5000`, `set -g @pane_read_preview_lines 5000`
- command override: `tmux-pane-read --lines 8000 --last --stdout`

## PTY Recovery

Safe cleanup helpers:
- `fix-zsh`
- `fix-zsh-dry`
- `fix-zsh-aggressive`
- `shell-recover-help`

## Backups

At the end of every install run, the script prints:
- backup snapshot path for that run (when backups are created)
- backup root path: `~/.dotfiles-backups`

This makes rollback location explicit.

## Open Source

- License: MIT (`LICENSE`)
- Contributions: see `CONTRIBUTING.md`
- Community conduct: see `CODE_OF_CONDUCT.md`
