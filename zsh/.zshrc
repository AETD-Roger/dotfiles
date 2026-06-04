# Path
export PATH="$HOME/.local/bin:$PATH"
[[ -d /opt/homebrew/opt/node@22/bin ]] && export PATH="/opt/homebrew/opt/node@22/bin:$PATH"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# Plugins — brew only on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
  plugins=(git brew tmux zsh-autosuggestions zsh-syntax-highlighting)
else
  plugins=(git tmux zsh-autosuggestions zsh-syntax-highlighting)
fi

source "$ZSH/oh-my-zsh.sh"

# Editor
export EDITOR='nvim'

# Prompt
eval "$(starship init zsh)"

# Smarter cd
eval "$(zoxide init zsh)"

# Modern CLI replacements
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first'
alias la='eza -a --icons --group-directories-first'
alias tree='eza --tree --icons'
alias cat='bat --paging=never'
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

# System info on shell open (interactive only)
[[ $- == *i* ]] && command -v fastfetch >/dev/null && fastfetch
