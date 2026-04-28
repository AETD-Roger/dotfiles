#!/usr/bin/env bash
# rice-setup.sh — Bootstrap a riced Ubuntu CLI environment.
#
# First run (on a fresh machine with an empty dotfiles repo):
#   • Installs every tool listed below.
#   • Generates sensible default configs for each.
#   • Moves them into your dotfiles repo and commits them.
#   • Stows them back into $HOME via symlinks.
#   You then `git push` to publish your baseline.
#
# Subsequent runs (on new VMs, after the repo is populated):
#   • Installs the tools.
#   • Clones the repo.
#   • Stows everything as-is.
#
# Tools: zsh + Oh My Zsh, AstroNvim v4, fastfetch, Starship, tmux,
#        JetBrainsMono Nerd Font, eza, bat, fd, ripgrep, zoxide, fzf.
#
# Usage:
#   1. Create an empty public repo on GitHub (e.g. github.com/you/dotfiles).
#   2. Edit the variables below.
#   3. chmod +x rice-setup.sh && ./rice-setup.sh

set -euo pipefail

# ============ EDIT THESE ============
GITHUB_USER="your-username"
DOTFILES_REPO="dotfiles"
DOTFILES_DIR="$HOME/dotfiles"
STOW_PACKAGES=(zsh nvim tmux fastfetch starship)
# ====================================

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}!${NC}  $*"; }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

# ---------- sanity ----------
[[ "$EUID" -eq 0 ]] && die "Don't run as root; the script will sudo when needed."
command -v sudo >/dev/null || die "sudo is required."
[[ "$GITHUB_USER" == "your-username" ]] && die "Edit GITHUB_USER at the top of the script first."

# ---------- apt packages ----------
log "Updating apt and installing base packages"
sudo apt-get update -qq
sudo apt-get install -y \
  zsh git curl wget unzip stow tmux build-essential \
  ripgrep fd-find fzf bat \
  fontconfig software-properties-common ca-certificates gpg \
  libfuse2 || sudo apt-get install -y libfuse2t64 || true

# Ubuntu installs these under odd names; symlink to expected names.
mkdir -p "$HOME/.local/bin"
[[ -e /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
[[ -e /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"

# ---------- eza ----------
if ! command -v eza >/dev/null; then
  log "Installing eza"
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  sudo apt-get update -qq && sudo apt-get install -y eza
fi

# ---------- zoxide ----------
if ! command -v zoxide >/dev/null; then
  log "Installing zoxide"
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi

# ---------- fastfetch ----------
if ! command -v fastfetch >/dev/null; then
  log "Installing fastfetch"
  if apt-cache show fastfetch >/dev/null 2>&1; then
    sudo apt-get install -y fastfetch
  else
    TMP_DEB=$(mktemp --suffix=.deb)
    curl -sSfL -o "$TMP_DEB" \
      "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
    sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y
    rm -f "$TMP_DEB"
  fi
fi

# ---------- JetBrainsMono Nerd Font ----------
if ! fc-list | grep -qi "JetBrainsMono Nerd Font"; then
  log "Installing JetBrainsMono Nerd Font"
  FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
  mkdir -p "$FONT_DIR"
  TMP_ZIP=$(mktemp --suffix=.zip)
  curl -sSfL -o "$TMP_ZIP" \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  unzip -oq "$TMP_ZIP" -d "$FONT_DIR"
  rm -f "$TMP_ZIP"
  fc-cache -f
fi

# ---------- Starship ----------
if ! command -v starship >/dev/null; then
  log "Installing Starship"
  curl -sSfL https://starship.rs/install.sh | sh -s -- -y
fi

# ---------- Neovim (need 0.10+ for AstroNvim v4) ----------
need_nvim=true
if command -v nvim >/dev/null; then
  ver=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0.0")
  major=${ver%.*}; minor=${ver#*.}
  if (( major > 0 || (major == 0 && minor >= 10) )); then need_nvim=false; fi
fi
if $need_nvim; then
  log "Installing latest Neovim (appimage)"
  sudo curl -sSfL -o /usr/local/bin/nvim \
    "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
  sudo chmod +x /usr/local/bin/nvim
fi

# ---------- Clone (or update) dotfiles repo ----------
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
  log "Cloning dotfiles from github.com/${GITHUB_USER}/${DOTFILES_REPO}"
  git clone "https://github.com/${GITHUB_USER}/${DOTFILES_REPO}.git" "$DOTFILES_DIR" \
    || die "Clone failed. Make sure the repo exists and is public."
else
  log "Updating existing dotfiles repo"
  git -C "$DOTFILES_DIR" pull --ff-only || warn "Couldn't fast-forward dotfiles"
fi

# ---------- Helpers for seeding empty packages ----------
is_pkg_empty() {
  local d="$DOTFILES_DIR/$1"
  [[ ! -d "$d" ]] && return 0
  # Treat dir as empty if it only contains git/readme placeholders.
  [[ -z "$(find "$d" -mindepth 1 -type f \
            -not -name '.gitkeep' -not -name '.gitignore' \
            -not -iname 'README*' -print -quit 2>/dev/null)" ]]
}

ensure_omz() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
}

seed_zsh() {
  local pkg_dir="$DOTFILES_DIR/zsh"
  mkdir -p "$pkg_dir"
  rm -f "$HOME/.zshrc"
  ensure_omz
  # Copy the omz template as a starting point
  cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
  # Disable omz theme so Starship can take over
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME=""/' "$HOME/.zshrc"
  # Append the riced bits
  cat >> "$HOME/.zshrc" <<'EOF'

# ----- riced additions -----
export PATH="$HOME/.local/bin:$PATH"

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

# fzf key bindings (Ctrl-R history, Ctrl-T file search, Alt-C cd)
[[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && \
  source /usr/share/doc/fzf/examples/key-bindings.zsh
[[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && \
  source /usr/share/doc/fzf/examples/completion.zsh

# System info on shell open (interactive only)
[[ $- == *i* ]] && command -v fastfetch >/dev/null && fastfetch
EOF
  mv "$HOME/.zshrc" "$pkg_dir/.zshrc"
  ok "  seeded zsh/.zshrc"
}

seed_nvim() {
  local pkg_dir="$DOTFILES_DIR/nvim"
  mkdir -p "$pkg_dir/.config"
  rm -rf "$HOME/.config/nvim" "$HOME/.local/share/nvim" \
         "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
  git clone --depth 1 https://github.com/AstroNvim/template "$HOME/.config/nvim"
  rm -rf "$HOME/.config/nvim/.git"
  mv "$HOME/.config/nvim" "$pkg_dir/.config/nvim"
  ok "  seeded nvim/.config/nvim (AstroNvim v4)"
}

seed_tmux() {
  local pkg_dir="$DOTFILES_DIR/tmux"
  mkdir -p "$pkg_dir"
  cat > "$pkg_dir/.tmux.conf" <<'EOF'
# ----- sane defaults -----
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g history-limit 50000
set -g escape-time 10
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB"

# Prefix C-a (more comfortable than C-b)
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded!"

# Splits keep current path
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-style pane nav
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
EOF
  ok "  seeded tmux/.tmux.conf"
}

seed_fastfetch() {
  local pkg_dir="$DOTFILES_DIR/fastfetch"
  mkdir -p "$pkg_dir/.config/fastfetch"
  fastfetch --gen-config-force >/dev/null 2>&1 || true
  if [[ -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
    mv "$HOME/.config/fastfetch/config.jsonc" "$pkg_dir/.config/fastfetch/config.jsonc"
  else
    echo '{"$schema":"https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json"}' \
      > "$pkg_dir/.config/fastfetch/config.jsonc"
  fi
  ok "  seeded fastfetch/.config/fastfetch/config.jsonc"
}

seed_starship() {
  local pkg_dir="$DOTFILES_DIR/starship"
  mkdir -p "$pkg_dir/.config"
  cat > "$pkg_dir/.config/starship.toml" <<'EOF'
# Starship config — run `starship preset -l` to browse other presets,
# then `starship preset <n> -o ~/.config/starship.toml` to swap one in.
add_newline = true

format = """
[╭─](bold green)$username$hostname$directory$git_branch$git_status$cmd_duration
[╰─](bold green)$character """

[character]
success_symbol = "[➜](bold green)"
error_symbol   = "[➜](bold red)"

[directory]
truncation_length = 3
truncate_to_repo  = true
style             = "bold cyan"

[git_branch]
symbol = " "
style  = "bold purple"

[cmd_duration]
min_time = 2000
format   = " took [$duration]($style) "
style    = "yellow"
EOF
  ok "  seeded starship/.config/starship.toml"
}

# ---------- Seed empty packages ----------
seeded_any=false
log "Checking which packages need seeding"
for pkg in "${STOW_PACKAGES[@]}"; do
  if is_pkg_empty "$pkg"; then
    log "Seeding $pkg with defaults"
    case "$pkg" in
      zsh)        seed_zsh ;;
      nvim)       seed_nvim ;;
      tmux)       seed_tmux ;;
      fastfetch)  seed_fastfetch ;;
      starship)   seed_starship ;;
      *)          warn "no seeder for '$pkg' — leaving empty" ;;
    esac
    seeded_any=true
  else
    ok "$pkg already populated in repo"
  fi
done

# Make sure omz is installed even if zsh wasn't seeded (its .zshrc depends on it)
ensure_omz

# ---------- Stow (overwrite mode) ----------
log "Stowing dotfiles (overwriting existing configs)"
cd "$DOTFILES_DIR"
for pkg in "${STOW_PACKAGES[@]}"; do
  if [[ ! -d "$pkg" ]]; then
    warn "skipping '$pkg' — not in repo"
    continue
  fi
  while IFS= read -r src; do
    rel="${src#$pkg/}"
    target="$HOME/$rel"
    [[ -e "$target" || -L "$target" ]] && rm -rf "$target"
    mkdir -p "$(dirname "$target")"
  done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \))
  stow -v --target="$HOME" "$pkg"
  ok "stowed $pkg"
done

# ---------- Commit seeded baseline ----------
if $seeded_any; then
  log "Committing seeded baseline to dotfiles repo"
  cd "$DOTFILES_DIR"
  git add -A
  if git config user.email >/dev/null && git config user.name >/dev/null; then
    git commit -m "Seed initial rice baseline (zsh, nvim, tmux, fastfetch, starship)" \
      || warn "Nothing to commit"
    ok "Committed. Run 'git -C $DOTFILES_DIR push' to publish your baseline."
  else
    warn "git user.name / user.email aren't configured — skipped auto-commit."
    warn "Set them and commit manually:"
    warn "  git config --global user.name  \"Your Name\""
    warn "  git config --global user.email \"you@example.com\""
    warn "  cd $DOTFILES_DIR && git add -A && git commit -m 'Initial baseline' && git push"
  fi
fi

# ---------- Default shell ----------
if [[ "${SHELL:-}" != *zsh ]]; then
  log "Setting zsh as default shell (you may be prompted for your password)"
  chsh -s "$(command -v zsh)" || warn "chsh failed; run manually: chsh -s \$(which zsh)"
fi

ok "Done."
echo
echo "Next steps:"
echo "  • Set your terminal font to 'JetBrainsMono Nerd Font'."
echo "  • Log out and back in (or run 'zsh') to enter your new shell."
echo "  • Open nvim once to let AstroNvim install plugins (:Lazy sync if needed)."
if $seeded_any; then
  echo "  • Push your seeded baseline:  git -C $DOTFILES_DIR push"
fi
