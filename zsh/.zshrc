# Path
export PATH="$HOME/.local/bin:$PATH"

# Homebrew — load its env and force its bin ahead of the macOS system dirs.
# macOS path_helper (/etc/zprofile) lists /usr/bin before /etc/paths.d/homebrew,
# so without this the ancient /usr/bin/nano (pico) shadows Homebrew's nano.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
typeset -U path PATH   # de-duplicate, keeping the first (Homebrew) occurrence

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# Plugins — brew only on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
  plugins=(git brew tmux zsh-autosuggestions zsh-syntax-highlighting)
else
  plugins=(git tmux zsh-autosuggestions zsh-syntax-highlighting)
fi

# Only source if actually installed — a missing/partial install shouldn't
# spew errors on every shell launch.
[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# Editor
export EDITOR='nvim'

# Prompt
eval "$(starship init zsh)"

# Smarter cd
eval "$(zoxide init zsh)"

# Modern CLI replacements — only alias if the tool is installed, otherwise
# fall back to built-ins so a failed/skipped install doesn't break ls/ll/cat.
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -lah --icons --group-directories-first'
  alias la='eza -a --icons --group-directories-first'
  alias tree='eza --tree --icons'
else
  alias ll='ls -lah'
  alias la='ls -A'
fi
command -v bat >/dev/null && alias cat='bat --paging=never'
alias vi='nvim'

# fzf key bindings & completion
if [[ "$(uname -s)" == "Darwin" ]]; then
  [[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]] && \
    source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
  [[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ]] && \
    source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
else
  [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && \
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && \
    source /usr/share/doc/fzf/examples/completion.zsh
fi

# yt-dlp helper: download in the background with a status ping
yt() { ( yt-dlp "$1" && echo "✅ yt-dlp finished OK" || echo "❌ yt-dlp FAILED" ) & }

# Source extra env (uv / cargo / rustup, etc.) if present
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# System info on shell open (interactive only)
[[ $- == *i* ]] && command -v fastfetch >/dev/null && fastfetch
