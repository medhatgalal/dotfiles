#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT=0

check_file() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$dst" ]]; then
    echo "[MISSING] $label -> $dst"
    DRIFT=$((DRIFT + 1))
    return
  fi

  if cmp -s "$src" "$dst"; then
    echo "[OK]      $label"
  else
    echo "[DRIFT]   $label"
    diff -u "$src" "$dst" | sed -n '1,12p'
    DRIFT=$((DRIFT + 1))
  fi
}

echo "Dotfiles drift check at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=========================================="

check_file "$DOTFILES_DIR/configs/zsh/zshenv" "$HOME/.zshenv" ".zshenv"
check_file "$DOTFILES_DIR/configs/zsh/zprofile" "$HOME/.zprofile" ".zprofile"
check_file "$DOTFILES_DIR/configs/zsh/zshrc" "$HOME/.zshrc" ".zshrc"
check_file "$DOTFILES_DIR/configs/tmux/tmux.conf" "$HOME/.tmux.conf" ".tmux.conf"
check_file "$DOTFILES_DIR/configs/gemini/settings.json" "$HOME/.gemini/settings.json" "gemini/settings.json"
check_file "$DOTFILES_DIR/configs/claude/settings.json" "$HOME/.claude/settings.json" "claude/settings.json"
check_file "$DOTFILES_DIR/configs/kiro/cli.json" "$HOME/.kiro/settings/cli.json" "kiro/cli.json"
check_file "$DOTFILES_DIR/configs/kiro/mcp.json" "$HOME/.kiro/settings/mcp.json" "kiro/mcp.json"
check_file "$DOTFILES_DIR/update.sh" "$HOME/update_software.sh" "update_software.sh"

for f in "$DOTFILES_DIR"/configs/zsh/aliases/*.zsh; do
  check_file "$f" "$HOME/.zsh/aliases/$(basename "$f")" "aliases/$(basename "$f")"
done

for f in "$DOTFILES_DIR"/configs/bin/*; do
  check_file "$f" "$HOME/.local/bin/$(basename "$f")" "bin/$(basename "$f")"
done

echo "=========================================="
if [[ "$DRIFT" -eq 0 ]]; then
  echo "Drift Status: clear"
  exit 0
fi

echo "Drift Status: alert ($DRIFT files)"
exit 1
