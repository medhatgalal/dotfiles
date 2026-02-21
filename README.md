# Minimal Dotfiles (EngOS Baseline)

Canonical path on this machine: `~/Desktop/dotfiles`.
Embedded copies also live at `scripts/setup/dotfiles` inside repos.

This package installs a minimal, portable local environment for EngOS workflows. It has been designed to be transparent, educational, and safe.

Features:
- Initial environment audit before making any changes.
- Choice between a safe **Additive Install** (tools only) and a **Clean Install** (full shell configuration).
- Explicit `y/N` opt-in prompts (no "shock and awe" overwrites).
- Safe, automatic Powerlevel10k and Meslo Nerd Font installation (bypassing the wizard).
- Generic tmux UX helpers (main/watcher pane flow).
- Minimal CLI config files (`.gemini`, `.claude`, `.kiro`, AGENTS docs).
- Granular, interactive software updater with previews (`update.sh`).

## What Is Managed

- **Core Tools:** `git`, `jq`, `node`, `python3`, `tmux`, `pre-commit`, `awscli`, `eza`, `bat`, `fd`, `ripgrep`, `fzf`, `zoxide`, `tree`, `glab`, `kiro`, `kiro-cli`, `beads`, `beads-viewer`, `uv`, and `specify-cli`.
- `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.zsh/aliases/*.zsh`
- `~/.tmux.conf`, `~/.local/bin/{pty-clean-safe,tmux-*}`
- `~/.gemini/settings.json`, `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`
- `~/.claude/settings.json`, `~/.claude/AGENTS.md`, `~/.claude/CLAUDE.md`
- `~/.kiro/settings/{cli.json,mcp.json,lsp.json}`, `~/.kiro/steering/AGENTS.md`
- `~/.codex/{config.toml,AGENTS.md}`
- `~/update_software.sh`

## Token Precedence

- Set `GITLAB_TOKEN` in `~/.secrets.env` as the canonical GitLab token for git operations.
- Set `GITLAB_MCP_TOKEN` as a read-only token for MCP servers.
- Recommended scopes are `read_api`, `read_repository`, `read_user`, `read_registry`.
- GitLab MCP is disabled by default; enable only after setting a read-only `GITLAB_MCP_TOKEN`.
- Set `GLAB_HOST=gitlab.appian-stratus.com` to keep `glab` calls pinned to self-hosted GitLab.

## What Is Not Managed

- prompt-pack hydration into repo-local `.gemini/.claude/.codex`
- repo-specific tmuxinator session files
- CLI history/cache/session artifacts

## Install

By default, the installer runs interactively. It performs an audit and asks you to choose between an Additive or Clean install.

```bash
cd ~/Desktop/dotfiles
./install.sh
```

Non-interactive (Defaults to safe Additive Install):

```bash
./install.sh --yes
```

Dry run (Preview what will happen without writing files):

```bash
./install.sh --dry-run
```

Install into a local repo path (intent: embed this package into the repo):

```bash
./install.sh --repo-path ~/Desktop/shapeup-base-v6clone
```

## Addendum: Why Choose a Clean Install?
When you run the dotfiles installer interactively, you are offered an **Additive Install** (safe, installs only missing tools) or a **Clean Install** (a full, opinionated environment upgrade).

Here is why you should consider a **Clean Install**:
- **Snappier Zsh Experience:** We replace generic zsh loading with explicit, optimized `vi-mode` defaults, making terminal sessions faster and more predictable.
- **Automated & Safe P10K:** The `p10k` config wizard frequently "blows up" terminals or requires manual font fetching. The clean install entirely bypasses the wizard, silently installing the `MesloLGS Nerd Font` and injecting a guaranteed-stable, visually rich prompt.
- **Preconfigured Tmux UX:** Out of the box, you get a main/watcher pane workflow pattern. Custom helpers (`tmux-main-watch`, `tmux-copy-main`) allow seamless context switching.
- **Centralized Secrets Management:** It drops a structured `~/.secrets.env` template. All your tokens (like `GITLAB_TOKEN`) are securely unified in one place, preventing token sprawl across disparate configs.
- **Unified AI Memory & Tooling:** A Clean install aligns your environment to a shared standard. Your `gemini`, `claude`, `codex`, and `kiro` CLI configurations are modularly mapped, including a **Shared MCP Memory Server** so context persists seamlessly across all AI clients.

## Update Software + Beads Runtime

By default, the updater runs interactively. It previews available updates (e.g., via `brew outdated`) before prompting.

```bash
~/update_software.sh
```

Non-interactive update (auto-accepts all updates):

```bash
~/update_software.sh --yes
```

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

`cat` alias is resilient:
- If `bat` is installed: `cat` uses `bat --paging=never`.
- If `batcat` is installed: `cat` uses `batcat --paging=never`.
- If neither is installed: native `cat` remains unchanged.

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
