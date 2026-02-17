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

log() { printf '[%s] %s\n' "$1" "$2"; }

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --dry-run     Show actions without writing files
  --yes         Non-interactive install (accept defaults)
  -h, --help    Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

prompt_yes_no() {
  local question="$1"
  local default="${2:-Y}"
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

has_meslo_nerd_font() {
  local font_dir
  for font_dir in "$HOME/Library/Fonts" "/Library/Fonts"; do
    [[ -d "$font_dir" ]] || continue
    ls "$font_dir"/MesloLGS*NerdFont*.ttf >/dev/null 2>&1 && return 0
  done
  return 1
}

install_p10k_fonts() {
  if has_meslo_nerd_font; then
    log INFO "Meslo Nerd Font already installed"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    log WARN "Homebrew not found; skipping Meslo Nerd Font install"
    log INFO "Install manually: brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Install Powerlevel10k font via brew cask: font-meslo-lg-nerd-font"
    return 0
  fi

  brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
  if brew list --cask --versions font-meslo-lg-nerd-font >/dev/null 2>&1; then
    log INFO "font-meslo-lg-nerd-font already installed"
  elif brew install --cask font-meslo-lg-nerd-font >/dev/null 2>&1; then
    log OK "Installed font-meslo-lg-nerd-font"
  else
    log WARN "Failed to install font-meslo-lg-nerd-font via Homebrew"
    return 0
  fi

  if has_meslo_nerd_font; then
    log OK "MesloLGS Nerd Fonts detected"
    log INFO "Set your terminal profile font to 'MesloLGS Nerd Font' for best p10k rendering"
  else
    log WARN "MesloLGS Nerd Fonts not detected after install"
  fi
}

configure_iterm2_meslo_font() {
  local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  local font_name="${P10K_ITERM2_FONT:-MesloLGSNerdFontMono-Regular 12}"
  local i=0
  local changed=0

  if ! osascript -e 'id of app "iTerm"' >/dev/null 2>&1; then
    log INFO "iTerm2 not installed; skipping iTerm2 font profile config"
    return 0
  fi

  if [[ ! -f "$plist" ]]; then
    log INFO "iTerm2 preferences not found yet; skipping font profile config"
    return 0
  fi

  if ! has_meslo_nerd_font; then
    log WARN "Meslo Nerd Fonts not detected; skipping iTerm2 profile font config"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Set iTerm2 profile fonts to '$font_name' in $plist"
    return 0
  fi

  while /usr/libexec/PlistBuddy -c "Print :\"New Bookmarks\":$i:Guid" "$plist" >/dev/null 2>&1; do
    if ! /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Normal Font\" \"$font_name\"" "$plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Normal Font\" string \"$font_name\"" "$plist" >/dev/null 2>&1 || true
    fi

    if ! /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Non Ascii Font\" \"$font_name\"" "$plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Non Ascii Font\" string \"$font_name\"" "$plist" >/dev/null 2>&1 || true
    fi

    if ! /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":$i:\"Use Non-ASCII Font\" true" "$plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Add :\"New Bookmarks\":$i:\"Use Non-ASCII Font\" bool true" "$plist" >/dev/null 2>&1 || true
    fi

    changed=$((changed + 1))
    i=$((i + 1))
  done

  if [[ "$changed" -gt 0 ]]; then
    killall cfprefsd >/dev/null 2>&1 || true
    log OK "Configured iTerm2 fonts on $changed profile(s) to '$font_name'"
    log INFO "Restart iTerm2 to apply updated profile font settings"
  else
    log INFO "No iTerm2 profiles found to update"
  fi
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

  # Remove old prompt-pack command files that used to be hydrated globally.
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

log INFO "Installing minimal dotfiles from $DOTFILES_DIR"
[[ "$DRY_RUN" == "1" ]] && log INFO "Dry run mode enabled"

if prompt_yes_no "Install shell configs (zsh + aliases)?" "Y"; then
  run_copy "$DOTFILES_DIR/configs/zsh/zshenv" "$HOME/.zshenv"
  run_copy "$DOTFILES_DIR/configs/zsh/zprofile" "$HOME/.zprofile"
  run_copy "$DOTFILES_DIR/configs/zsh/zshrc" "$HOME/.zshrc"

  mkdir -p "$HOME/.zsh/aliases"
  for f in "$DOTFILES_DIR"/configs/zsh/aliases/*.zsh; do
    run_copy "$f" "$HOME/.zsh/aliases/$(basename "$f")"
  done

  if [[ ! -f "$HOME/.p10k.zsh" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Copy $DOTFILES_DIR/configs/zsh/p10k.zsh -> $HOME/.p10k.zsh"
    else
      cp "$DOTFILES_DIR/configs/zsh/p10k.zsh" "$HOME/.p10k.zsh"
      log OK "Installed $HOME/.p10k.zsh"
    fi
  else
    log INFO "Keeping existing $HOME/.p10k.zsh"
  fi
fi

if prompt_yes_no "Install Powerlevel10k Nerd Fonts (MesloLGS)?" "Y"; then
  install_p10k_fonts
fi

if prompt_yes_no "Configure iTerm2 profiles to use Meslo Nerd Font automatically?" "Y"; then
  configure_iterm2_meslo_font
fi

if [[ ! -f "$SECRETS_FILE" && -f "$SECRETS_TEMPLATE" ]]; then
  if prompt_yes_no "Create $SECRETS_FILE from template?" "Y"; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log PLAN "Copy $SECRETS_TEMPLATE -> $SECRETS_FILE"
    else
      cp "$SECRETS_TEMPLATE" "$SECRETS_FILE"
      chmod 600 "$SECRETS_FILE"
      log OK "Created $SECRETS_FILE"
      log INFO "Populate secrets before using MCP integrations"
    fi
  fi
fi

if prompt_yes_no "Install tmux config + helpers?" "Y"; then
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
      if command -v git >/dev/null 2>&1; then
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" >/dev/null 2>&1 || true
        log OK "Bootstrapped tmux TPM"
      else
        log WARN "git unavailable; skipped TPM bootstrap"
      fi
    fi
  fi
fi

if prompt_yes_no "Install CLI config files (Gemini/Claude/Kiro/AGENTS)?" "Y"; then
  run_copy "$DOTFILES_DIR/configs/gemini/settings.json" "$HOME/.gemini/settings.json"
  run_copy "$DOTFILES_DIR/configs/claude/settings.json" "$HOME/.claude/settings.json"
  run_copy "$DOTFILES_DIR/configs/kiro/cli.json" "$HOME/.kiro/settings/cli.json"
  run_copy "$DOTFILES_DIR/configs/kiro/mcp.json" "$HOME/.kiro/settings/mcp.json"

  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.gemini/AGENTS.md"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.claude/AGENTS.md"
  run_copy "$DOTFILES_DIR/configs/agents/AGENTS.md" "$HOME/.kiro/steering/AGENTS.md"

  run_copy "$DOTFILES_DIR/configs/gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"
  run_copy "$DOTFILES_DIR/configs/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
fi

if prompt_yes_no "Install software updater to ~/update_software.sh?" "Y"; then
  run_copy "$DOTFILES_DIR/update.sh" "$HOME/update_software.sh" "755"
fi

if prompt_yes_no "Delete stale prompt/tmux/repo-alias files from home paths?" "Y"; then
  cleanup_stale_paths
fi

if prompt_yes_no "Run software update now?" "N"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    log PLAN "Run $DOTFILES_DIR/update.sh -i"
  else
    "$DOTFILES_DIR/update.sh" -i
  fi
fi

log OK "Dotfiles install complete"
[[ -d "$BACKUP_DIR" ]] && log INFO "Backups: $BACKUP_DIR"
log INFO "Restart terminal after install"
