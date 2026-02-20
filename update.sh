#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=0
LOG_FILE="update_log.txt"
REPORT_FILE="update_summary.txt"
UPDATED_LOG="$(mktemp)"
UNCHANGED_LOG="$(mktemp)"
trap 'rm -f "$UPDATED_LOG" "$UNCHANGED_LOG"' EXIT

usage() {
  cat <<'USAGE'
Usage: ./update.sh [options]

Options:
  -i, --interactive   Prompt before each update group
  -h, --help          Show help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive) INTERACTIVE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf '[%s] %s\n' "$1" "$2"; }

prompt() {
  local q="$1"
  local d="${2:-Y}"
  if [[ "$INTERACTIVE" == "0" ]]; then
    [[ "$d" == "Y" ]] && return 0 || return 1
  fi

  local ans
  if [[ "$d" == "Y" ]]; then
    read -r -p "$q [Y/n] " ans
    ans="${ans:-Y}"
  else
    read -r -p "$q [y/N] " ans
    ans="${ans:-N}"
  fi
  [[ "$ans" =~ ^([yY]|[yY][eE][sS])$ ]]
}

track() {
  local name="$1" old="$2" new="$3"
  old="${old:-Unknown}"
  new="${new:-Unknown}"
  if [[ "$old" != "$new" ]]; then
    echo "$name|$old|$new" >> "$UPDATED_LOG"
    log OK "$name updated ($old -> $new)"
  else
    echo "$name|$new" >> "$UNCHANGED_LOG"
    log INFO "$name unchanged ($new)"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

brew_ver() { brew list --versions "$1" 2>/dev/null | awk '{print $NF}'; }
brew_cask_ver() { brew list --cask --versions "$1" 2>/dev/null | awk '{print $NF}'; }

bd_ver() {
  if ! have bd; then
    echo "Not Installed"
    return
  fi
  bd version 2>/dev/null | awk 'NR==1{print $3}'
}

echo "=========================================="
echo "System update started: $(date)"
echo "Mode: $( [[ "$INTERACTIVE" == "1" ]] && echo Interactive || echo Automatic )"
echo "=========================================="

if ! have brew; then
  log ERROR "Homebrew is required"
  exit 1
fi

if prompt "Update Homebrew and core formulae?" "Y"; then
  brew update
  OUTDATED_FORMULAE="$(brew outdated --verbose --formula || true)"
  OUTDATED_CASKS="$(brew outdated --verbose --cask || true)"
  brew upgrade --formula

  if [[ -n "$OUTDATED_FORMULAE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+\((.*)\)[[:space:]]+\<[[:space:]]+(.*)$ ]]; then
        echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}" >> "$UPDATED_LOG"
      fi
    done <<< "$OUTDATED_FORMULAE"
  fi

  if [[ -n "$OUTDATED_CASKS" ]]; then
    log INFO "Skipping Homebrew cask upgrades by default (may require sudo)."
  fi

  for pkg in git jq node python3 tmux awscli eza bat fd ripgrep fzf zoxide tree; do
    old="$(brew_ver "$pkg")"
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      brew install "$pkg"
    fi
    new="$(brew_ver "$pkg")"
    track "$pkg" "$old" "$new"
  done

  if prompt "Run Homebrew cask operations (may require sudo)?" "N"; then
    old="$(brew_cask_ver font-meslo-lg-nerd-font)"
    if ! brew list --cask --versions font-meslo-lg-nerd-font >/dev/null 2>&1; then
      brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
      brew install --cask font-meslo-lg-nerd-font >/dev/null 2>&1 || log WARN "font-meslo-lg-nerd-font install failed"
    fi
    new="$(brew_cask_ver font-meslo-lg-nerd-font)"
    track "font-meslo-lg-nerd-font(cask)" "$old" "$new"
  else
    log INFO "Skipping cask operations."
  fi

  brew cleanup
fi

if prompt "Update Oh My Zsh + plugins?" "Y"; then
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    old="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; then
      zsh "$HOME/.oh-my-zsh/tools/upgrade.sh" || true
    elif have omz; then
      omz update || true
    fi
    new="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    track "oh-my-zsh" "$old" "$new"

    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
      path="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
      if [[ -d "$path/.git" ]]; then
        old="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)"
        git -C "$path" pull >/dev/null 2>&1 || true
        new="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)"
        track "$plugin" "$old" "$new"
      fi
    done
  else
    log WARN "Oh My Zsh not found; skipping"
  fi
fi

if prompt "Update Beads (bd)?" "Y"; then
  old="$(bd_ver)"
  log INFO "Upgrading Beads..."
  brew upgrade beads || brew reinstall beads
  hash -r 2>/dev/null || true
  new="$(bd_ver)"
  track "beads(bd)" "$old" "$new"
fi

if prompt "Update npm global AI CLIs?" "Y"; then
  if have npm; then
    for pkg in @openai/codex @google/gemini-cli @google/jules specify-cli; do
      old="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || true)"
      npm install -g "$pkg" >/dev/null 2>&1 || true
      new="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || true)"
      track "$pkg" "${old:-Unknown}" "${new:-Unknown}"
    done
  else
    log WARN "npm not installed; skipping"
  fi
fi

{
  echo "Update Summary - $(date)"
  echo "=========================================="
  echo
  echo "UPDATED"
  echo "----------------"
  if [[ -s "$UPDATED_LOG" ]]; then
    echo "Software|Previous|Current"
    sort "$UPDATED_LOG"
  else
    echo "No updates applied."
  fi | column -t -s "|"

  echo
  echo "UNCHANGED"
  echo "----------------"
  if [[ -s "$UNCHANGED_LOG" ]]; then
    echo "Software|Current"
    sort -u "$UNCHANGED_LOG"
  else
    echo "None"
  fi | column -t -s "|"
} > "$REPORT_FILE"

cat "$REPORT_FILE"

echo "=========================================="
log OK "System update finished"
log INFO "Log file: $LOG_FILE"
log INFO "Summary: $REPORT_FILE"
