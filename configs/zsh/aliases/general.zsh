# General Aliases
if command -v eza >/dev/null 2>&1; then
  alias ls="eza"
  alias ll="eza --long"
  alias la="eza --long --all"
  alias lt="eza --tree"
else
  alias ls="command ls"
  alias ll="command ls -lh"
  alias la="command ls -lah"
  if command -v tree >/dev/null 2>&1; then
    alias lt="command tree -C"
  else
    alias lt="command ls -lah"
  fi
fi

if command -v lsd >/dev/null 2>&1; then
  alias lsd="lsd --long"
fi
if command -v bat >/dev/null 2>&1; then
  alias cat="bat --paging=never"
fi
if command -v tree >/dev/null 2>&1; then
  alias tree="command tree -C"
fi
alias c='clear'
alias ports='lsof -i -n -P | grep TCP'
alias python='python3'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias home='cd ~'
alias dl='cd ~/Downloads'

# Configuration
alias config='code ~/.zshrc'
alias reloadzsh='source ~/.zshrc'
