#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=1
LOG_FILE="update_log.txt"
REPORT_FILE="update_summary.txt"
UPDATED_LOG="$(mktemp)"
UNCHANGED_LOG="$(mktemp)"
FAILED_LOG="$(mktemp)"
START_TIME=$(date +%s)
trap 'rm -f "$UPDATED_LOG" "$UNCHANGED_LOG" "$FAILED_LOG"' EXIT

usage() {
  cat <<'USAGE'
EngOS System Updater

Usage: ./update.sh [options]

Description:
  Discovers and applies updates for Homebrew packages, Oh-My-Zsh,
  NPM globals, and Beads. By default, it runs interactively,
  previewing available updates and asking for confirmation before
  applying them to each component group.

Options:
  -y, --yes         Non-interactive mode (automatically update everything)
  -h, --help        Show this help message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) INTERACTIVE=0 ;;
    -i|--interactive) INTERACTIVE=1 ;; # Legacy flag, now the default
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
  "$@" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  spinner $pid
  wait $pid
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    printf "✔\n"
  else
    printf "✖\n"
    echo "$msg" >> "$FAILED_LOG"
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
  if [[ "$old" != "$new" && "$new" != "Unknown" && "$new" != "Not Installed" ]]; then
    echo "$name|$old|$new" >> "$UPDATED_LOG"
  else
    echo "$name|$new" >> "$UNCHANGED_LOG"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

brew_ver() { brew list --versions "$1" 2>/dev/null | awk '{print $NF}' || echo "Unknown"; }
brew_cask_ver() { brew list --cask --versions "$1" 2>/dev/null | awk '{print $NF}' || echo "Unknown"; }

bd_ver() {
  if ! have bd; then
    echo "Not Installed"
    return
  fi
  bd version 2>/dev/null | awk 'NR==1{print $3}'
}

# --- Main Update Logic ---

echo "======================================================================="
echo "                  System Update & Discovery                            "
echo "======================================================================="
echo "Mode: $( [[ "$INTERACTIVE" == "1" ]] && echo "Interactive (Opt-in)" || echo "Automatic (--yes)" )"
echo ""

if ! have brew; then
  log ERROR "Homebrew is required"
  exit 1
fi

# Pre-fetch outdated packages to show the user what will change
echo "Discovering available updates... (This might take a moment)"
run_task "Updating Homebrew index..." brew update

OUTDATED_BREW="$(brew outdated --formula 2>/dev/null || true)"
OUTDATED_CASK="$(brew outdated --cask 2>/dev/null || true)"

if [[ -n "$OUTDATED_BREW" ]] || [[ -n "$OUTDATED_CASK" ]]; then
  echo ""
  echo "--- Available Homebrew Updates ---"
  [[ -n "$OUTDATED_BREW" ]] && echo "$OUTDATED_BREW" | sed 's/^/  /'
  [[ -n "$OUTDATED_CASK" ]] && echo "$OUTDATED_CASK" | sed 's/^/  /'
  echo "----------------------------------"
else
  echo " ✓ Homebrew packages are up to date."
fi
echo ""

if prompt "Upgrade outdated Homebrew formulae and casks?" "N"; then
  run_task "Upgrading Homebrew formulae..." brew upgrade --formula
  run_task "Upgrading Homebrew casks..." brew upgrade --cask
  
  # Baseline packages verification
  for pkg in git jq node python3 tmux pre-commit awscli eza bat fd ripgrep fzf zoxide tree glab kiro kiro-cli beads beads-viewer uv; do
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      run_task "Installing missing $pkg..." brew install "$pkg" || true
    fi
    new="$(brew_ver "$pkg")"
    track "$pkg" "Unknown" "$new"
  done
  run_task "Cleaning up Homebrew..." brew cleanup
fi

echo ""
if prompt "Update Oh My Zsh and plugins?" "N"; then
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

echo ""
if prompt "Update global NPM packages (e.g. AI CLIs)?" "N"; then
  if have npm; then
    OUTDATED_NPM="$(npm outdated -g --depth=0 2>/dev/null || true)"
    if [[ -n "$OUTDATED_NPM" ]]; then
      echo "--- Available NPM Updates ---"
      echo "$OUTDATED_NPM" | sed 's/^/  /'
      echo "-----------------------------"
    fi
    for pkg in @openai/codex @google/gemini-cli @google/jules specify-cli; do
      old="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || echo "Not Installed")"
      run_task "Updating NPM package $pkg..." npm install -g "$pkg" || true
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
  echo "======================================================================="
  echo "                  Update Final Report                                  "
  echo "======================================================================="
  echo "Date: $(date)"
  echo "Elapsed Time: ${MINUTES}m ${SECONDS}s"
  echo ""
  
  echo "[ ✅ SUCCESSFULLY UPDATED ]"
  echo "---------------------------------------------------"
  if [[ -s "$UPDATED_LOG" ]]; then
    printf "%-30s | %-10s -> %s\n" "SOFTWARE" "PREVIOUS" "CURRENT"
    echo "---------------------------------------------------"
    sort -u "$UPDATED_LOG" | awk -F'|' '{printf "%-30s | %-10s -> %s\n", $1, $2, $3}'
  else
    echo "  (No packages were updated)"
  fi
  echo ""

  echo "[ ➖ NO CHANGES NEEDED ]"
  echo "---------------------------------------------------"
  if [[ -s "$UNCHANGED_LOG" ]]; then
    sort -u "$UNCHANGED_LOG" | awk -F'|' '{printf "  %-30s : %s\n", $1, $2}'
  else
    echo "  (None)"
  fi
  echo ""

  if [[ -s "$FAILED_LOG" ]]; then
    echo "[ ❌ ERRORS / WARNINGS ]"
    echo "---------------------------------------------------"
    sed 's/^/  - /' "$FAILED_LOG"
    echo ""
  fi

  echo "======================================================================="
} > "$REPORT_FILE"

echo ""
cat "$REPORT_FILE"
log INFO "Full detailed log available at: $LOG_FILE"
