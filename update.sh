#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=0
LOG_FILE="update_log.txt"
REPORT_FILE="update_summary.txt"
UPDATED_LOG="$(mktemp)"
UNCHANGED_LOG="$(mktemp)"
START_TIME=$(date +%s)
trap 'rm -f "$UPDATED_LOG" "$UNCHANGED_LOG"' EXIT

# Baseline packages to track
BASELINE_PACKAGES=(git jq node python3 tmux pre-commit awscli eza bat fd ripgrep fzf zoxide tree)

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

# Clear log file
: > "$LOG_FILE"

log() { printf '[%s] %s\n' "$1" "$2"; }

# Simple, stable spinner
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
  read -r -p "$q [Y/n] " ans
  ans="${ans:-$d}"
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
bd_ver() { have bd && bd version 2>/dev/null | awk 'NR==1{print $3}' || echo "Not Installed"; }

# Capture versions map
declare -A OLD_VERSIONS
capture_versions() {
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    OLD_VERSIONS[$pkg]="$(brew_ver "$pkg")"
    if [[ -z "${OLD_VERSIONS[$pkg]}" ]]; then
      OLD_VERSIONS[$pkg]="Not Installed"
    fi
  done
}

echo "=========================================="
echo "System update started: $(date)"
echo "Mode: $( [[ "$INTERACTIVE" == "1" ]] && echo Interactive || echo Automatic )"
echo "=========================================="

if prompt "Update Homebrew and core formulae?" "Y"; then
  capture_versions
  
  # Group update and upgrade into one spinner task to reduce jumps
  run_task "Updating Homebrew & Packages..." bash -c 'brew update && brew upgrade --formula' || true

  # Capture outdated for reporting (post-facto from log or just tracking)
  # We rely on version comparison now, which is faster/cleaner.

  # Verify baseline packages are installed (fast check)
  MISSING_PACKAGES=()
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      MISSING_PACKAGES+=("$pkg")
    fi
  done

  if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    run_task "Installing missing baseline packages..." brew install "${MISSING_PACKAGES[@]}"
  fi

  # Report changes
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    track "$pkg" "${OLD_VERSIONS[$pkg]:-Unknown}" "$(brew_ver "$pkg")"
  done

  run_task "Cleaning up Homebrew..." brew cleanup
fi

if prompt "Update Oh My Zsh?" "Y"; then
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    old="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    run_task "Updating Oh My Zsh..." env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/upgrade.sh" --non-interactive || true
    track "oh-my-zsh" "$old" "$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
  fi
fi

if prompt "Update Beads (bd)?" "Y"; then
  old="$(bd_ver)"
  run_task "Upgrading Beads..." bash -c 'brew upgrade beads || brew reinstall beads'
  hash -r 2>/dev/null || true
  track "beads(bd)" "$old" "$(bd_ver)"
fi

if prompt "Update npm global AI CLIs?" "Y"; then
  if have npm; then
    NPM_PACKAGES=(@openai/codex @google/gemini-cli @google/jules specify-cli)
    
    # Check outdated first (fast)
    log INFO "Checking npm packages..."
    OUTDATED_JSON=$(npm outdated -g --json 2>/dev/null || echo "{}")
    
    for pkg in "${NPM_PACKAGES[@]}"; do
      old="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || echo "Not Installed")"
      
      # If package is missing OR in outdated JSON, update/install it
      if [[ "$old" == "Not Installed" ]] || echo "$OUTDATED_JSON" | grep -q "\"$pkg\""; then
        run_task "Updating/Installing $pkg..." npm install -g "$pkg" || true
      else
        echo "npm install -g $pkg (skipped, up to date)" >> "$LOG_FILE"
      fi
      
      new="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || echo "Unknown")"
      track "$pkg" "$old" "$new"
    done
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
log OK "System update finished in ${MINUTES}m ${SECONDS}s"
