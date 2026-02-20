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

verify_dolt_cli() {
  local tmp out rc
  tmp="$(mktemp -d)"
  out="$(mktemp)"

  (
    cd "$tmp"
    dolt version >"$out" 2>&1
    dolt init --name "healthcheck" --email "healthcheck@example.com" >>"$out" 2>&1
    dolt sql -q "select 1 as ok;" >>"$out" 2>&1
  )
  rc=$?

  if [[ $rc -eq 0 ]]; then
    rm -rf "$tmp" "$out"
    return 0
  fi

  cat "$out"
  rm -rf "$tmp" "$out"
  return 1
}

verify_bd_dolt_runtime() {
  local tmp out doctor rc nodb
  tmp="$(mktemp -d)"
  out="$(mktemp)"
  doctor="$(mktemp)"

  (
    cd "$tmp"
    git init -q >/dev/null 2>&1 || true
    if ! bd init --quiet >"$out" 2>&1; then
      echo "bd init failed"
      cat "$out"
      exit 1
    fi
    bd doctor --json >"$doctor" 2>>"$out" || true
  )
  rc=$?

  if [[ $rc -ne 0 ]]; then
    rm -rf "$tmp" "$out" "$doctor"
    return 1
  fi

  if rg -qi "requires CGO|not available on this build|dolt backend requires CGO" "$out" "$doctor"; then
    rm -rf "$tmp" "$out" "$doctor"
    return 2
  fi

  if have jq; then
    if ! jq -e '.checks[] | select((.name=="Database" or .name=="Backend Migration") and (((.detail // "") + " " + (.message // "")) | test("Dolt"; "i")))' "$doctor" >/dev/null 2>&1; then
      cat "$doctor"
      rm -rf "$tmp" "$out" "$doctor"
      return 1
    fi
  else
    if ! rg -qi "Storage: Dolt|Backend: Dolt" "$doctor"; then
      cat "$doctor"
      rm -rf "$tmp" "$out" "$doctor"
      return 1
    fi
  fi

  nodb="$(cd "$tmp" && bd config get no-db 2>/dev/null || true)"
  if [[ "$nodb" == "true" ]]; then
    echo "bd config no-db=true (Dolt backend required)"
    rm -rf "$tmp" "$out" "$doctor"
    return 1
  fi

  rm -rf "$tmp" "$out" "$doctor"
  return 0
}

repo_has_beads() {
  [[ -d .beads ]]
}

safe_stop_bd_daemons() {
  bd dolt stop >/dev/null 2>&1 || true
}

ensure_repo_dolt_backend() {
  repo_has_beads || return 0
  have jq || { log WARN "jq missing: skipping repo-local beads self-heal"; return 0; }

  log INFO "Running repo-local Beads self-heal in $PWD"

  safe_stop_bd_daemons

  local doctor tmp backend
  tmp="$(mktemp)"
  bd doctor --json > "$tmp" 2>/dev/null || true

  # Check either "Backend Migration" (legacy) or "Database" (new) or "Database Config"
  backend="$(jq -r '.checks[] | select(.name=="Backend Migration" or .name=="Database" or .name=="Database Config") | (.detail // "") + " " + (.message // "")' "$tmp" 2>/dev/null || true)"
  
  if [[ "$backend" == *"SQLite"* ]]; then
    log WARN "Backend is SQLite; attempting migration to Dolt"
    safe_stop_bd_daemons
    printf 'y\n' | bd --sandbox migrate --to-dolt >/dev/null 2>&1 || true
  fi

  bd config set no-db false >/dev/null 2>&1 || true
  bd sync --import-only >/dev/null 2>&1 || true

  # Metadata repair attempts.
  safe_stop_bd_daemons
  bd --sandbox migrate >/dev/null 2>&1 || true
  safe_stop_bd_daemons
  bd --sandbox migrate --update-repo-id >/dev/null 2>&1 || true

  # Final checks.
  bd doctor --json > "$tmp" 2>/dev/null || true
  safe_stop_bd_daemons

  if jq -e '.checks[] | select(((.detail // "") + " " + (.message // "")) | test("requires CGO|not available on this build"; "i"))' "$tmp" >/dev/null 2>&1; then
    log ERROR "CGO/Dolt regression detected in repo-local self-heal"
    rm -f "$tmp"
    return 1
  fi

  if ! jq -e '.checks[] | select((.name=="Backend Migration" or .name=="Database" or .name=="Database Config") and (((.detail // "") + " " + (.message // "")) | contains("Dolt")))' "$tmp" >/dev/null 2>&1; then
    log ERROR "Repo backend is not Dolt after self-heal"
    # Debug info
    jq -c '.checks[] | select(.name=="Backend Migration" or .name=="Database" or .name=="Database Config")' "$tmp" 2>/dev/null || true
    rm -f "$tmp"
    return 1
  fi

  local nodb
  nodb="$(bd config get no-db 2>/dev/null || true)"
  if [[ "$nodb" != "false" ]]; then
    log ERROR "Repo config no-db is not false (found: $nodb)"
    rm -f "$tmp"
    return 1
  fi

  rm -f "$tmp"
  log OK "Repo-local Beads self-heal complete"
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

  for pkg in git jq node python3 tmux pre-commit awscli eza bat fd ripgrep fzf zoxide tree; do
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

if prompt "Update Beads (bd) via Homebrew with Dolt+CGO enforcement?" "Y"; then
  old="$(bd_ver)"

  if brew list beads >/dev/null 2>&1; then
    brew upgrade --force-bottle beads || brew reinstall --force-bottle beads
  else
    brew install --force-bottle beads
  fi

  hash -r 2>/dev/null || true

  if ! verify_dolt_cli; then
    log ERROR "dolt CLI health check failed"
    exit 1
  fi

  if ! verify_bd_dolt_runtime; then
    log WARN "bd runtime failed Dolt+CGO verification; retrying with brew reinstall beads"
    brew reinstall --force-bottle beads
    hash -r 2>/dev/null || true
    if ! verify_bd_dolt_runtime; then
      log ERROR "bd runtime still fails Dolt+CGO verification"
      log ERROR "Active bd path: $(command -v bd || echo not-found)"
      exit 1
    fi
  fi

  new="$(bd_ver)"
  track "beads(bd)" "$old" "$new"

  if repo_has_beads; then
    ensure_repo_dolt_backend
  fi
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
