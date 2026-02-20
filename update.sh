#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=0
LOG_FILE="update_log.txt"
REPORT_FILE="update_summary.txt"
UPDATED_LOG="$(mktemp)"
UNCHANGED_LOG="$(mktemp)"
START_TIME=$(date +%s)
trap 'rm -f "$UPDATED_LOG" "$UNCHANGED_LOG"' EXIT

# Baseline packages to track explicitly
BASELINE_PACKAGES=(git jq node python3 tmux awscli eza bat fd ripgrep fzf zoxide tree)

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

# We want stdout to user, but detailed logs to file.
# We'll redirect specific verbose commands to LOG_FILE, but keep main output visible.
# Actually, the original script redirected EVERYTHING to LOG_FILE and tee-d to stdout.
# That's why it was noisy. But user says "it feels like hanging", which usually means SILENCE.
# If it's slow and silent, they need a spinner.
# If it's slow and noisy, they see progress.
# The user asked for a spinner, implying they want to know it's working during long silent blocks.

# Redirecting only specific noisy commands to log file to keep UI clean,
# but using a spinner for them.

log() { printf '[%s] %s\n' "$1" "$2"; }

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

run_with_spinner() {
  local msg="$1"
  shift
  printf "[INFO] %s " "$msg"
  "$@" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  spinner $pid
  wait $pid
  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    printf "✔\n"
  else
    printf "✖ (See %s)\n" "$LOG_FILE"
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
    # log OK "$name updated ($old -> $new)" # Suppress individual update noise in main UI
  else
    echo "$name|$new" >> "$UNCHANGED_LOG"
    # log INFO "$name unchanged ($new)" # Suppress noise
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

# Capture versions before update
declare -A PRE_UPDATE_VERSIONS
capture_versions() {
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
      PRE_UPDATE_VERSIONS[$pkg]="$(brew_ver "$pkg")"
    else
      PRE_UPDATE_VERSIONS[$pkg]="Not Installed"
    fi
  done
}

echo "=========================================="
echo "System update started: $(date)"
echo "Mode: $( [[ "$INTERACTIVE" == "1" ]] && echo Interactive || echo Automatic )"
echo "=========================================="

# Clear log file
: > "$LOG_FILE"

if ! have brew; then
  log ERROR "Homebrew is required"
  exit 1
fi

if prompt "Update Homebrew and core formulae?" "Y"; then
  capture_versions

  run_with_spinner "Updating Homebrew..." brew update
  
  OUTDATED_FORMULAE="$(brew outdated --verbose --formula || true)"
  OUTDATED_CASKS="$(brew outdated --verbose --cask || true)"
  
  run_with_spinner "Upgrading formulae..." brew upgrade --formula

  # Track general updates from output parsing (fallback/extra)
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

  # Verify baseline packages and track changes
  # We do this quietly without spinner as it's fast per package usually
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    if ! brew list --versions "$pkg" >/dev/null 2>&1; then
      run_with_spinner "Installing $pkg..." brew install "$pkg"
    fi
    new="$(brew_ver "$pkg")"
    old="${PRE_UPDATE_VERSIONS[$pkg]:-Unknown}"
    track "$pkg" "$old" "$new"
  done

  if prompt "Run Homebrew cask operations (may require sudo)?" "N"; then
    old="$(brew_cask_ver font-meslo-lg-nerd-font)"
    if ! brew list --cask --versions font-meslo-lg-nerd-font >/dev/null 2>&1; then
      brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
      run_with_spinner "Installing font-meslo-lg-nerd-font..." brew install --cask font-meslo-lg-nerd-font
    fi
    new="$(brew_cask_ver font-meslo-lg-nerd-font)"
    track "font-meslo-lg-nerd-font(cask)" "$old" "$new"
  else
    log INFO "Skipping cask operations."
  fi

  run_with_spinner "Cleaning up Homebrew..." brew cleanup
fi

if prompt "Update Oh My Zsh + plugins?" "Y"; then
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    old="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    if [[ -f "$HOME/.oh-my-zsh/tools/upgrade.sh" ]]; then
      # Run in subshell to avoid env pollution and capture output
      run_with_spinner "Updating Oh My Zsh..." zsh "$HOME/.oh-my-zsh/tools/upgrade.sh" --non-interactive
    elif have omz; then
      run_with_spinner "Updating Oh My Zsh..." omz update
    fi
    new="$(git -C "$HOME/.oh-my-zsh" rev-parse --short HEAD 2>/dev/null || true)"
    track "oh-my-zsh" "$old" "$new"

    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
      path="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
      if [[ -d "$path/.git" ]]; then
        old="$(git -C "$path" rev-parse --short HEAD 2>/dev/null || true)"
        run_with_spinner "Updating $plugin..." git -C "$path" pull
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
  run_with_spinner "Upgrading Beads..." brew upgrade beads || brew reinstall beads
  hash -r 2>/dev/null || true
  new="$(bd_ver)"
  track "beads(bd)" "$old" "$new"
fi

if prompt "Update npm global AI CLIs?" "Y"; then
  if have npm; then
    for pkg in @openai/codex @google/gemini-cli @google/jules specify-cli; do
      old="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || true)"
      run_with_spinner "Updating $pkg..." npm install -g "$pkg"
      new="$(npm list -g "$pkg" --depth=0 2>/dev/null | grep -Eo "${pkg//@/\\@}@[0-9A-Za-z._-]+" | head -n1 | awk -F@ '{print $NF}' || true)"
      track "$pkg" "${old:-Unknown}" "${new:-Unknown}"
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
