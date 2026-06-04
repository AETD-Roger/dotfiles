#!/usr/bin/env bash
# setup.sh — Bootstrap a new Mac or Linux (Debian/Ubuntu) machine.
#
# Usage:
#   git clone https://github.com/AETD-Roger/dotfiles.git ~/dotfiles
#   cd ~/dotfiles && chmod +x setup.sh && ./setup.sh

set -euo pipefail

# ============ CONFIG ============
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="AETD-Roger"
STOW_PACKAGES=(zsh nvim tmux fastfetch starship)
# ================================

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}!${NC}  $*"; }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

OS="$(uname -s)"
log "Detected OS: $OS"

# ──────────────────────────────────────────────
# macOS
# ──────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then

  # ---------- Xcode CLI tools ----------
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools"
    xcode-select --install
    echo "Press any key once the install finishes…"; read -rn1
  fi

  # ---------- Homebrew ----------
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  # ---------- Brewfile ----------
  log "Installing packages from Brewfile"
  brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some Brewfile items may have failed"

  # ---------- npm CLI tools ----------
  log "Installing Claude Code CLI and Codex CLI"
  npm install -g @anthropic-ai/claude-code @openai/codex

  # ---------- Ghostty config (Mac only) ----------
  STOW_PACKAGES+=(ghostty)

# ──────────────────────────────────────────────
# Linux (Debian / Ubuntu)
# ──────────────────────────────────────────────
elif [[ "$OS" == "Linux" ]]; then

  [[ "$EUID" -eq 0 ]] && die "Don't run as root; the script will sudo when needed."
  command -v sudo >/dev/null || die "sudo is required."

  # ---------- apt packages ----------
  log "Updating apt and installing base packages"
  sudo apt-get update -qq
  sudo apt-get install -y \
    zsh git curl wget unzip stow tmux build-essential \
    ripgrep fd-find fzf bat \
    fontconfig software-properties-common ca-certificates gpg \
    libfuse2 || sudo apt-get install -y libfuse2t64 || true

  # Ubuntu installs these under odd names
  mkdir -p "$HOME/.local/bin"
  [[ -e /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
  [[ -e /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"

  # ---------- eza ----------
  if ! command -v eza &>/dev/null; then
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
  if ! command -v zoxide &>/dev/null; then
    log "Installing zoxide"
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  fi

  # ---------- fastfetch ----------
  if ! command -v fastfetch &>/dev/null; then
    log "Installing fastfetch"
    if apt-cache show fastfetch &>/dev/null; then
      sudo apt-get install -y fastfetch
    else
      TMP_DEB=$(mktemp --suffix=.deb)
      curl -sSfL -o "$TMP_DEB" \
        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
      sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y
      rm -f "$TMP_DEB"
    fi
  fi

  # ---------- Starship ----------
  if ! command -v starship &>/dev/null; then
    log "Installing Starship"
    curl -sSfL https://starship.rs/install.sh | sh -s -- -y
  fi

  # ---------- Neovim (need 0.10+ for AstroNvim v4) ----------
  need_nvim=true
  if command -v nvim &>/dev/null; then
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

else
  die "Unsupported OS: $OS"
fi

# ──────────────────────────────────────────────
# Common setup (both platforms)
# ──────────────────────────────────────────────

# ---------- Git config ----------
log "Configuring git"
git config --global user.name "Roger Ferworn"
git config --global user.email "rferworn@aetech.design"
git config --global init.defaultBranch main
git config --global core.editor nvim
ok "Git configured"

# ---------- Oh My Zsh ----------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log "Installing Oh My Zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---------- zsh-autosuggestions ----------
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  log "Installing zsh-autosuggestions"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# ---------- zsh-syntax-highlighting ----------
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  log "Installing zsh-syntax-highlighting"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# ---------- Stow dotfiles ----------
log "Stowing dotfiles"
cd "$DOTFILES_DIR"
for pkg in "${STOW_PACKAGES[@]}"; do
  if [[ ! -d "$pkg" ]]; then
    warn "Skipping '$pkg' — not in repo"
    continue
  fi
  # Remove existing files so stow can place symlinks
  while IFS= read -r src; do
    rel="${src#$pkg/}"
    target="$HOME/$rel"
    [[ -e "$target" || -L "$target" ]] && rm -rf "$target"
    mkdir -p "$(dirname "$target")"
  done < <(find "$pkg" -mindepth 1 \( -type f -o -type l \))
  stow -v --target="$HOME" "$pkg"
  ok "Stowed $pkg"
done

# ---------- Default shell ----------
if [[ "${SHELL:-}" != *zsh ]]; then
  log "Setting zsh as default shell"
  chsh -s "$(command -v zsh)" || warn "chsh failed — run manually: chsh -s \$(which zsh)"
fi

# ──────────────────────────────────────────────
# macOS-specific settings
# ──────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then

  # ---------- Detect desktop vs laptop ----------
  if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    MAC_TYPE="laptop"
  else
    MAC_TYPE="desktop"
  fi
  log "Detected Mac type: $MAC_TYPE"
  echo -n "Is this correct? (y/n) "
  read -r confirm
  if [[ "$confirm" != "y" ]]; then
    echo -n "Enter type (desktop/laptop): "
    read -r MAC_TYPE
  fi

  # ---------- Dock ----------
  log "Configuring Dock"
  defaults write com.apple.dock autohide -bool true

  # ---------- Finder ----------
  log "Configuring Finder"
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder NewWindowTarget -string "PfHm"
  defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

  # ---------- Keyboard & input ----------
  log "Configuring keyboard & input"
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

  # ---------- Screenshots ----------
  log "Configuring screenshots"
  mkdir -p "$HOME/Screenshots"
  defaults write com.apple.screencapture location -string "$HOME/Screenshots"
  defaults write com.apple.screencapture type -string "png"

  # ---------- Misc ----------
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # ---------- Screensaver / lock ----------
  log "Requiring password after sleep/screensaver"
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # ---------- Firewall ----------
  log "Enabling firewall"
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

  # ---------- Power settings ----------
  log "Configuring power settings ($MAC_TYPE)"
  if [[ "$MAC_TYPE" == "desktop" ]]; then
    sudo pmset -a displaysleep 10
    sudo pmset -a sleep 0
    sudo pmset -a disksleep 0
    sudo pmset -a womp 1
    sudo pmset -a autorestart 1
  else
    # Laptop — battery
    sudo pmset -b displaysleep 5
    sudo pmset -b sleep 15
    # Laptop — AC
    sudo pmset -c displaysleep 10
    sudo pmset -c sleep 0
  fi

  # ---------- Printers (optional) ----------
  echo
  echo -n "Set up office printers (Ricoh MP C4503 + HP CM4540)? (y/n) "
  read -r setup_printers
  if [[ "$setup_printers" == "y" ]]; then
    log "Adding Ricoh MP C4503"
    lpadmin -p "Ricoh_MP_C4503" -E -v "socket://10.10.1.240" -m everywhere \
      && ok "Ricoh added" || warn "Failed to add Ricoh — check the IP"

    log "Adding HP Color LaserJet CM4540"
    lpadmin -p "HP_CM4540" -E -v "socket://NPI3E5ABA.local" -m everywhere \
      && ok "HP added" || warn "Failed to add HP — check network"
  fi

  # ---------- Restart affected services ----------
  log "Restarting Dock and Finder to apply settings"
  killall Dock Finder SystemUIServer 2>/dev/null || true
fi

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
ok "Setup complete!"
echo
echo "Next steps:"
echo "  • Log out and back in (or run 'zsh') to enter your new shell."
echo "  • Set your terminal font to 'JetBrainsMono Nerd Font'."
echo "  • Open nvim once to let AstroNvim install plugins (:Lazy sync if needed)."
if [[ "$OS" == "Darwin" ]]; then
  echo "  • Add your home folder to the Finder sidebar manually."
fi
