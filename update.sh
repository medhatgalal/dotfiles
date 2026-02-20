#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=0
LOG_FILE="update_log.txt"
REPORT_FILE="update_summary.txt"
UPDATED_LOG="$(mktemp)"
UNCHANGED_LOG="$(mktemp)"
START_TIME=$(date +%s)
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

# Initialize log file
: > "$LOG_FILE"

log() { printf '[%s] %s\n' "$1" "$2"; }

# Simple spinner for long-running tasks
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps -p $pid -o pid=)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

run_task() {
  local msg="$1"
  shift
  printf "[INFO] %-40s" "$msg"
  # Run command, redirect output to log, background it
  "$@" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  spinner $pid
  wait $pid
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    printf "✔\n"
  else
    printf "✖\n"
  fi
  return $exit_code
}

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
  else
    echo "$name|$new" >> "$UNCHANGED_LOG"
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

# --- Main Update Logic ---

echo "=========================================="
echo "System update started: $(date)"
echo "Mode: $( [[ "$INTERACTIVE" == "1" ]] && echo Interactive || echo Automatic )"
echo "=========================================="

if ! have brew; then
  log ERROR "Homebrew is required"
  exit 1
fi

if prompt "Update Homebrew and core formulae?" "Y"; then
  run_task "Updating Homebrew..." brew update
  
  # Capture outdated list for logging purposes
  OUTDATED_FORMULAE="$(brew outdated --verbose --formula || true)"
  if [[ -n "$OUTDATED_FORMULAE" ]]; then
    echo "Outdated Formulae:" >> "$LOG_FILE"
    echo "$OUTDATED_FORMULAE" >> "$LOG_FILE"
  fi

  run_task "Upgrading formulae..." brew upgrade --formula

  # Baseline packages to verify/install/track
  for pkg in git jq node python3 tmux pre-commit awscli eza bat fd ripgrep fzf zoxide tree; do
    # Capture 'old' version logic:
    # If we just upgraded, 'brew list' shows current.
    # To strictly track "old", we rely on the fact that we just ran 'brew upgrade'.
    # If the package was upgraded, it was in the outdated list.
    # But for simplicity and robustness (since we reverted complexity),
    # we will just check if it's installed, install if missing, and log current version.
    
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      run_task "Installing $pkg..." brew install "$pkg"
    fi
    # Current version
    new="$(brew_ver "$pkg")"
    track "$pkg" "Unknown" "$new"
  done

  if prompt "Run Homebrew cask operations (may require sudo)?" "N"; then
    if ! brew list --cask --versions font-meslo-lg-nerd-font >/dev/null 2>&1; then
      brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
      run_task "Installing font-meslo-lg-nerd-font..." brew install --cask font-meslo-lg-nerd-font
    fi
    new="$(brew_cask_ver font-meslo-lg-nerd-font)"
    track "font-meslo-lg-nerd-font(cask)" "Unknown" "$new"
  else
    log INFO "Skipping cask operations."
  fi

  run_task "Cleaning up Homebrew..." brew cleanup
fi

if prompt "Update Oh My Zsh + plugins?" "Y"; then
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    old="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; then
      run_task "Updating Oh My Zsh..." env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/upgrade.sh" --non-interactive || true
    elif have omz; then
      run_task "Updating Oh My Zsh..." omz update || true
    fi
    new="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    track "oh-my-zsh" "$old" "$new"

    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
      path="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
      if [[ -d "$path/.git" ]]; then
        old="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)"
        run_task "Updating $plugin..." git -C "$path" pull || true
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
  run_task "Upgrading Beads..." bash -c 'brew upgrade beads || brew reinstall beads' || true
  hash -r 2>/dev/null || true
  
  # Repo-local check (Simplified: just check status, don't crash)
  if [[ -d .beads ]]; then
     run_task "Checking repo-local beads..." bd doctor --json || true
  fi
  
  new="$(bd_ver)"
  track "beads(bd)" "$old" "$new"
fi

if prompt "Update npm global AI CLIs?" "Y"; then
  if have npm; then
    for pkg in @openai/codex @google/gemini-cli @google/jules specify-cli; do
      old="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || echo "Not Installed")"
      run_task "Updating $pkg..." npm install -g "$pkg" || true
      new="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || echo "Unknown")"
      track "$pkg" "$old" "$new"
    done
  else
    log WARN "npm not installed; skipping"
  fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

{
  echo "Update Summary - $(date)"
  echo "Elapsed Time: ${MINUTES}m ${SECONDS}s"
  echo "=========================================="
  echo
  echo "UPDATED"
  echo "----------------"
  if [[ -s "$UPDATED_LOG" ]]; then
    echo "Software|Previous|Current"
    sort -u "$UPDATED_LOG"
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
log OK "System update finished in ${MINUTES}m ${SECONDS}s"
log INFO "Full log: $LOG_FILE"
