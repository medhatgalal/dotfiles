#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$HOME/.dotfiles-backups"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$STAMP"
SECRETS_FILE="$HOME/.secrets.env"
SECRETS_TEMPLATE="$DOTFILES_DIR/templates/secrets.env.example"

DRY_RUN=0
ASSUME_YES=0
TARGET_REPO_PATH=""
BACKUP_COUNT=0

# Core CLI utilities combined with pre-work needs
BASE_BREW_PACKAGES=(git jq node python3 tmux pre-commit awscli eza bat fd ripgrep fzf zoxide tree glab kiro kiro-cli beads beads-viewer uv)

log() { printf '[%s] %s\n' "$1" "$2"; }

usage() {
  cat <<'USAGE'
EngOS Dotfiles & Environment Installer

Usage: ./install.sh [options]

Description:
  Installs core CLI utilities, AI tools, and shell configurations.
  By default, it runs interactively, performs an environment audit,
  and asks whether you want a safe "Additive" install (tools only)
  or a "Clean" install (full shell config takeover with backups).

Options:
  --dry-run     Show actions without writing files or making changes
  --yes         Non-interactive install (accepts defaults: Additive mode)
  --repo-path   Also install this package into <repo>/scripts/setup/dotfiles
  -h, --help    Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    --repo-path)
      [[ $# -ge 2 ]] || { echo "Missing value for --repo-path" >&2; exit 1; }
      TARGET_REPO_PATH="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

prompt_yes_no() {
  local question="$1"
  local default="${2:-N}"
  if [[ "$ASSUME_YES" == "1" ]]; then
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi

  local ans
  if [[ "$default" == "Y" ]]; then
    read -r -p "$question [Y/n] " ans
    ans="${ans:-Y}"
  else
    read -r -p "$question [y/N] " ans
    ans="${ans:-N}"
  fi

  [[ "$ans" =~ ^([yY]|[yY][eE][sS])$ ]]
}

run_copy() {
  local src="$1"
  local dst="$2"
  local mode="${3:-}"
  local backup_name

  [[ -f "$src" ]] || { log ERROR "Missing source: $src"; exit 1; }

  if [[ -e "$dst" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup_name="$(printf '%s' "$dst" | sed "s|$HOME/||; s|/|__|g")"
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Backup $dst -> $BACKUP_DIR/$backup_name"
    else
      cp -a "$dst" "$BACKUP_DIR/$backup_name"
      BACKUP_COUNT=$((BACKUP_COUNT + 1))
      log INFO "Backed up $dst"
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Copy $src -> $dst"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  [[ -n "$mode" ]] && chmod "$mode" "$dst"
  log OK "Installed $dst"
}

# --- 1. Initial Environment Audit ---
echo ""
echo "======================================================================="
echo "                  Environment Setup & Audit                            "
echo "======================================================================="
echo ""

AUDIT_MISSING_TOOLS=0
AUDIT_HAS_ZSH=0
AUDIT_HAS_P10K=0
AUDIT_HAS_BREW=0

if command -v brew >/dev/null 2>&1; then
  AUDIT_HAS_BREW=1
fi

if [[ "$SHELL" == *"zsh"* ]]; then
  AUDIT_HAS_ZSH=1
fi

if [[ -f "$HOME/.p10k.zsh" ]]; then
  AUDIT_HAS_P10K=1
fi

for pkg in "${BASE_BREW_PACKAGES[@]}"; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    AUDIT_MISSING_TOOLS=$((AUDIT_MISSING_TOOLS + 1))
  fi
done

echo "[AUDIT RESULTS]"
[[ $AUDIT_HAS_BREW -eq 1 ]] && echo " ✓ Homebrew is installed" || echo " ✗ Homebrew is MISSING (Required)"
[[ $AUDIT_HAS_ZSH -eq 1 ]] && echo " ✓ Zsh is default shell" || echo " ✗ Zsh is not default shell"
[[ $AUDIT_MISSING_TOOLS -gt 0 ]] && echo " ✗ Missing $AUDIT_MISSING_TOOLS core CLI tools (e.g. glab, kiro, jq, fd)" || echo " ✓ All core CLI tools installed"
[[ $AUDIT_HAS_P10K -eq 1 ]] && echo " ✓ Powerlevel10k configured" || echo " ✗ Powerlevel10k not configured"
echo ""

echo "WHAT THIS SCRIPT WILL IMPROVE:"
echo " - Ensure all modern CLI tools are installed (awscli, eza, fzf, glab, kiro, etc.)"
echo " - Safely back up existing configurations to: $BACKUP_DIR"
echo " - Prevent terminal 'blow ups' by applying safe p10k configurations"
echo " - Install AI agent configs and prompt helpers"
echo "======================================================================="
echo ""

if [[ $AUDIT_HAS_BREW -eq 0 ]]; then
  log ERROR "Homebrew is required. Install it first: https://brew.sh"
  exit 1
fi

echo "INSTALLATION MODES:"
echo " 1) Additive Install : Safely install missing CLI tools ONLY (Non-destructive)."
echo " 2) Clean Install    : Full optimized shell experience (Oh-My-Zsh, Tmux, p10k)."
echo "                       Will backup & overwrite ~/.zshrc, ~/.tmux.conf, etc."
echo ""
read -r -p "Select mode (1 for Additive, 2 for Clean) [1/2]: " INSTALL_MODE
if [[ "$INSTALL_MODE" != "2" ]]; then
  INSTALL_MODE="1"
fi
echo ""

# --- Shared: Install Baseline CLI Tools ---
if prompt_yes_no "Install baseline CLI tools (kiro, glab, fzf, etc.)?" "Y"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    for pkg in "${BASE_BREW_PACKAGES[@]}"; do
      log PLAN "Ensure brew package installed: $pkg"
    done
  else
    for pkg in "${BASE_BREW_PACKAGES[@]}"; do
      if brew list --versions "$pkg" >/dev/null 2>&1; then
        log INFO "Already installed: $pkg"
      else
        brew install "$pkg"
        log OK "Installed $pkg"
      fi
    done
  fi
fi

# Install speckit via uv
if prompt_yes_no "Install Speckit via uv tool?" "N"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "uv tool install specify-cli --from git+https://github.com/github/spec-kit.git"
  else
    if command -v uv >/dev/null 2>&1; then
      uv tool install specify-cli --from git+https://github.com/github/spec-kit.git || log WARN "Failed to install Speckit"
      log OK "Installed Speckit"
    else
      log WARN "uv not found, skipping Speckit"
    fi
  fi
fi

# --- 2. Clean Install (Shell & Terminal) ---
if [[ "$INSTALL_MODE" == "2" ]]; then
  
  if prompt_yes_no "Install Oh-My-Zsh and Custom Zsh Configs?" "N"; then
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
      if [[ "$DRY_RUN" == "1" ]]; then
        log PLAN "Install Oh-My-Zsh via curl script"
      else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
        log OK "Installed Oh-My-Zsh"
      fi
    fi

    run_copy "$DOTFILES_DIR/configs/zsh/zshenv" "$HOME/.zshenv"
    run_copy "$DOTFILES_DIR/configs/zsh/zprofile" "$HOME/.zprofile"
    run_copy "$DOTFILES_DIR/configs/zsh/zshrc" "$HOME/.zshrc"

    mkdir -p "$HOME/.zsh/aliases"
    for f in "$DOTFILES_DIR"/configs/zsh/aliases/*.zsh; do
      run_copy "$f" "$HOME/.zsh/aliases/$(basename "$f")"
    done
  fi

  if prompt_yes_no "Deploy safe Powerlevel10k (p10k) configuration?" "N"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Copy $DOTFILES_DIR/configs/zsh/p10k.zsh -> $HOME/.p10k.zsh"
    else
      cp "$DOTFILES_DIR/configs/zsh/p10k.zsh" "$HOME/.p10k.zsh"
      log OK "Installed $HOME/.p10k.zsh (Wizard bypassed)"
    fi
  fi

  if prompt_yes_no "Install Powerlevel10k Nerd Fonts (MesloLGS) via Homebrew?" "N"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Install Powerlevel10k font via brew cask: font-meslo-lg-nerd-font"
    else
      brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
      brew install --cask font-meslo-lg-nerd-font >/dev/null 2>&1 || log WARN "Failed to install font or already installed"
      log OK "Ensured font-meslo-lg-nerd-font is installed"
    fi
  fi

  if prompt_yes_no "Configure iTerm2 profiles to use Meslo Nerd Font automatically?" "N"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Set iTerm2 profile fonts to MesloLGS Nerd Font"
    else
      local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
      local font_name="MesloLGSNerdFontMono-Regular 12"
      if [[ -f "$plist" ]]; then
        local i=0
        while /usr/libexec/PlistBuddy -c "Print :\"New Bookmarks\":$i:Guid" "$plist" >/dev/null 2>&1; do
          /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Normal Font\" \"$font_name\"" "$plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Normal Font\" string \"$font_name\"" "$plist" >/dev/null 2>&1 || true
          /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Non Ascii Font\" \"$font_name\"" "$plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Non Ascii Font\" string \"$font_name\"" "$plist" >/dev/null 2>&1 || true
          /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Use Non-ASCII Font\" true" "$plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Use Non-ASCII Font\" bool true" "$plist" >/dev/null 2>&1 || true
          i=$((i + 1))
        done
        killall cfprefsd >/dev/null 2>&1 || true
        log OK "Configured iTerm2 fonts on profile(s) to '$font_name'"
      fi
    fi
  fi

  if prompt_yes_no "Install tmux config + helpers?" "N"; then
    run_copy "$DOTFILES_DIR/configs/tmux/tmux.conf" "$HOME/.tmux.conf"

    mkdir -p "$HOME/.local/bin"
    for f in "$DOTFILES_DIR"/configs/bin/*; do
      run_copy "$f" "$HOME/.local/bin/$(basename "$f")" "755"
    done

    if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
      if [[ "$DRY_RUN" == "1" ]]; then
        log PLAN "Install TPM into $HOME/.tmux/plugins/tpm"
      else
        mkdir -p "$HOME/.tmux/plugins"
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" >/dev/null 2>&1 || true
        log OK "Bootstrapped tmux TPM"
      fi
    fi
  fi
fi

# --- 3. Configuration & Secrets ---
if [[ ! -f "$SECRETS_FILE" && -f "$SECRETS_TEMPLATE" ]]; then
  if prompt_yes_no "Create and configure $SECRETS_FILE from template?" "N"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Copy $SECRETS_TEMPLATE -> $SECRETS_FILE and open in editor"
    else
      cp "$SECRETS_TEMPLATE" "$SECRETS_FILE"
      chmod 600 "$SECRETS_FILE"
      log OK "Created $SECRETS_FILE"
      
      if prompt_yes_no "Open $SECRETS_FILE in editor now to fill in access tokens?" "Y"; then
        ${EDITOR:-nano} "$SECRETS_FILE"
      else
        log INFO "Please remember to populate $SECRETS_FILE before using MCP integrations."
      fi
    fi
  fi
fi

if prompt_yes_no "Install CLI config files (Gemini/Claude/Kiro/AGENTS)?" "N"; then
  run_copy "$DOTFILES_DIR/configs/gemini/settings.json" "$HOME/.gemini/settings.json"
  run_copy "$DOTFILES_DIR/configs/claude/settings.json" "$HOME/.claude/settings.json"
  run_copy "$DOTFILES_DIR/configs/kiro/cli.json" "$HOME/.kiro/settings/cli.json"
  run_copy "$DOTFILES_DIR/configs/kiro/mcp.json" "$HOME/.kiro/settings/mcp.json"
  run_copy "$DOTFILES_DIR/configs/kiro/lsp.json" "$HOME/.kiro/settings/lsp.json"

  mkdir -p "$HOME/.codex"
  run_copy "$DOTFILES_DIR/configs/codex/config.toml" "$HOME/.codex/config.toml"

  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.gemini/AGENTS.md"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.claude/AGENTS.md"
  
  mkdir -p "$HOME/.kiro/steering"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.kiro/steering/AGENTS.md"

  run_copy "$DOTFILES_DIR/configs/gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"
  run_copy "$DOTFILES_DIR/configs/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

if prompt_yes_no "Install software updater to ~/update_software.sh?" "N"; then
  run_copy "$DOTFILES_DIR/update.sh" "$HOME/update_software.sh" "755"
fi

cleanup_stale_paths() {
  local removed=0
  local target

  for target in \
    "$HOME/.zsh/aliases/repo.zsh" \
    "$HOME/.config/tmuxinator/calendar-gemini-spec-project.yml" \
    "$HOME/.config/tmuxinator/shapeup-base-v6clone.yml" \
    "$HOME/.config/tmuxinator/pengos.yml" \
    "$HOME/.config/tmuxinator/engos.yml"
  do
    [[ -e "$target" ]] || continue
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Delete stale $target"
    else
      rm -f "$target"
      log OK "Deleted stale $target"
    fi
    removed=$((removed + 1))
  done

  for target in \
    "$HOME/.gemini/commands/analyze-context.toml" \
    "$HOME/.gemini/commands/auditor.toml" \
    "$HOME/.gemini/commands/converge.toml" \
    "$HOME/.gemini/commands/mentor.toml" \
    "$HOME/.gemini/commands/supercharge.toml" \
    "$HOME/.gemini/commands/threader.toml" \
    "$HOME/.claude/commands/analyze-context.md" \
    "$HOME/.claude/commands/auditor.md" \
    "$HOME/.claude/commands/converge.md" \
    "$HOME/.claude/commands/mentor.md" \
    "$HOME/.claude/commands/supercharge.md" \
    "$HOME/.claude/commands/threader.md" \
    "$HOME/.codex/prompts/analyze-context.md" \
    "$HOME/.codex/prompts/auditor.md" \
    "$HOME/.codex/prompts/converge.md" \
    "$HOME/.codex/prompts/mentor.md" \
    "$HOME/.codex/prompts/supercharge.md" \
    "$HOME/.codex/prompts/threader.md"
  do
    [[ -e "$target" ]] || continue
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Delete stale $target"
    else
      rm -f "$target"
      log OK "Deleted stale $target"
    fi
    removed=$((removed + 1))
  done

  log INFO "Stale cleanup removals: $removed"
}

if prompt_yes_no "Delete stale prompt/tmux/repo-alias files from home paths?" "N"; then
  cleanup_stale_paths
fi

install_repo_bundle() {
  local repo_path="$1"
  local dest backup_name

  [[ -n "$repo_path" ]] || { log WARN "Repo path is empty; skipping repo bundle install"; return 0; }
  repo_path="${repo_path%/}"
  dest="$repo_path/scripts/setup/dotfiles"

  if [[ ! -d "$repo_path" ]]; then
    log WARN "Repo path not found: $repo_path"
    return 0
  fi

  if [[ -e "$dest" ]]; then
    mkdir -p "$BACKUP_DIR"
    backup_name="$(printf '%s' "$dest" | sed "s|$HOME/||; s|/|__|g")"
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Backup existing repo bundle $dest -> $BACKUP_DIR/$backup_name"
    else
      cp -a "$dest" "$BACKUP_DIR/$backup_name"
      BACKUP_COUNT=$((BACKUP_COUNT + 1))
      log INFO "Backed up existing repo bundle at $dest"
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Install dotfiles package to $dest"
    return 0
  fi

  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude ".git/" "$DOTFILES_DIR"/ "$dest"/
  else
    log WARN "rsync not found; copying without delete (stale files may remain)"
    (cd "$DOTFILES_DIR" && find . -mindepth 1 -maxdepth 1 ! -name ".git" -exec cp -a {} "$dest"/ \;)
  fi

  log OK "Installed dotfiles package to $dest"
}

if [[ -n "$TARGET_REPO_PATH" ]]; then
  install_repo_bundle "$TARGET_REPO_PATH"
elif prompt_yes_no "Install into repo path? Outcome: <repo>/scripts/setup/dotfiles gets this package." "N"; then
  read -r -p "Repo local path: " TARGET_REPO_PATH
  install_repo_bundle "$TARGET_REPO_PATH"
fi

if prompt_yes_no "Run software update now?" "N"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Run $DOTFILES_DIR/update.sh"
  else
    "$DOTFILES_DIR/update.sh"
  fi
fi

echo "======================================================================="
log OK "Dotfiles setup complete"
if [[ "$DRY_RUN" == "1" ]]; then
  log INFO "Backup snapshot (dry run): $BACKUP_DIR"
elif [[ "$BACKUP_COUNT" -gt 0 ]]; then
  log INFO "Backup snapshot: $BACKUP_DIR ($BACKUP_COUNT item(s))"
else
  log INFO "No backups were created in this run."
fi
log INFO "Backup root: $BACKUP_ROOT"
log INFO "Please restart your terminal."
echo "======================================================================="
