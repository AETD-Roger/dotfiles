#!/usr/bin/env bash
# setup.sh — Bootstrap a new Mac or Linux (Debian/Ubuntu) machine.
# Safe to re-run — skips steps that are already complete.
#
# Usage:
#   git clone https://github.com/AETD-Roger/dotfiles.git ~/dotfiles
#   cd ~/dotfiles && chmod +x setup.sh && ./setup.sh

set -uo pipefail

# ============ CONFIG ============
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_USER="AETD-Roger"
STOW_PACKAGES=(zsh nvim tmux fastfetch starship)
ERRORS=0
# ================================

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}!${NC}  $*"; ERRORS=$((ERRORS + 1)); }
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
  else
    ok "Xcode CLI tools already installed"
  fi

  # ---------- Homebrew ----------
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew install failed"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    ok "Homebrew already installed"
  fi

  # ---------- Brewfile ----------
  log "Installing packages from Brewfile"
  brew bundle --file="$DOTFILES_DIR/Brewfile" || warn "Some Brewfile items may have failed"

  # ---------- npm CLI tools ----------
  if ! command -v npm &>/dev/null; then
    warn "npm not found — skipping Claude Code and Codex CLI install"
  else
    if ! command -v claude &>/dev/null; then
      log "Installing Claude Code CLI"
      npm install -g @anthropic-ai/claude-code || warn "Failed to install Claude Code CLI"
    else
      ok "Claude Code CLI already installed"
    fi
    if ! command -v codex &>/dev/null; then
      log "Installing Codex CLI"
      npm install -g @openai/codex || warn "Failed to install Codex CLI"
    else
      ok "Codex CLI already installed"
    fi
  fi

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
  sudo apt-get update -qq || warn "apt-get update failed"
  sudo apt-get install -y \
    zsh git curl wget unzip stow tmux build-essential \
    ripgrep fd-find fzf bat \
    fontconfig software-properties-common ca-certificates gpg \
    || warn "Some apt packages may have failed"
  sudo apt-get install -y libfuse2 2>/dev/null \
    || sudo apt-get install -y libfuse2t64 2>/dev/null \
    || warn "libfuse2 not available — neovim appimage may not work"

  # Ubuntu installs these under odd names
  mkdir -p "$HOME/.local/bin"
  [[ -e /usr/bin/batcat ]] && ln -sf /usr/bin/batcat "$HOME/.local/bin/bat"
  [[ -e /usr/bin/fdfind ]] && ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"

  # ---------- eza ----------
  if ! command -v eza &>/dev/null; then
    log "Installing eza"
    sudo mkdir -p /etc/apt/keyrings
    if wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null; then
      echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
      sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
      sudo apt-get update -qq && sudo apt-get install -y eza || warn "Failed to install eza"
    else
      warn "Failed to install eza — GPG key download failed"
    fi
  else
    ok "eza already installed"
  fi

  # ---------- zoxide ----------
  if ! command -v zoxide &>/dev/null; then
    log "Installing zoxide"
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
      || warn "Failed to install zoxide"
  else
    ok "zoxide already installed"
  fi

  # ---------- fastfetch ----------
  if ! command -v fastfetch &>/dev/null; then
    log "Installing fastfetch"
    if apt-cache show fastfetch &>/dev/null; then
      sudo apt-get install -y fastfetch || warn "Failed to install fastfetch"
    else
      TMP_DEB=$(mktemp --suffix=.deb)
      if curl -sSfL -o "$TMP_DEB" \
          "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"; then
        sudo dpkg -i "$TMP_DEB" || sudo apt-get install -f -y || warn "Failed to install fastfetch"
      else
        warn "Failed to download fastfetch"
      fi
      rm -f "$TMP_DEB"
    fi
  else
    ok "fastfetch already installed"
  fi

  # ---------- Starship ----------
  if ! command -v starship &>/dev/null; then
    log "Installing Starship"
    curl -sSfL https://starship.rs/install.sh | sh -s -- -y \
      || warn "Failed to install Starship"
  else
    ok "Starship already installed"
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
      "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage" \
      && sudo chmod +x /usr/local/bin/nvim \
      || warn "Failed to install Neovim"
  else
    ok "Neovim already installed (0.10+)"
  fi

  # ---------- JetBrainsMono Nerd Font ----------
  if ! fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    log "Installing JetBrainsMono Nerd Font"
    FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
    mkdir -p "$FONT_DIR"
    TMP_ZIP=$(mktemp --suffix=.zip)
    if curl -sSfL -o "$TMP_ZIP" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
      unzip -oq "$TMP_ZIP" -d "$FONT_DIR"
      fc-cache -f
    else
      warn "Failed to download JetBrainsMono Nerd Font"
    fi
    rm -f "$TMP_ZIP"
  else
    ok "JetBrainsMono Nerd Font already installed"
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
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    || warn "Failed to install Oh My Zsh"
else
  ok "Oh My Zsh already installed"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---------- zsh-autosuggestions ----------
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  log "Installing zsh-autosuggestions"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
    || warn "Failed to install zsh-autosuggestions"
else
  ok "zsh-autosuggestions already installed"
fi

# ---------- zsh-syntax-highlighting ----------
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  log "Installing zsh-syntax-highlighting"
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
    || warn "Failed to install zsh-syntax-highlighting"
else
  ok "zsh-syntax-highlighting already installed"
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
  stow -v --target="$HOME" "$pkg" && ok "Stowed $pkg" || warn "Failed to stow $pkg"
done

# ---------- Default shell ----------
if [[ "${SHELL:-}" != *zsh ]]; then
  log "Setting zsh as default shell"
  chsh -s "$(command -v zsh)" || warn "chsh failed — run manually: chsh -s \$(which zsh)"
else
  ok "zsh is already the default shell"
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
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on \
    || warn "Failed to enable firewall"

  # ---------- Power settings ----------
  log "Configuring power settings ($MAC_TYPE)"
  if [[ "$MAC_TYPE" == "desktop" ]]; then
    sudo pmset -a displaysleep 10 || warn "Failed to set displaysleep"
    sudo pmset -a sleep 0 || warn "Failed to set sleep"
    sudo pmset -a disksleep 0 || warn "Failed to set disksleep"
    sudo pmset -a womp 1 || warn "Failed to set wake on LAN"
    sudo pmset -a autorestart 1 || warn "Failed to set autorestart"
  else
    # Laptop — battery
    sudo pmset -b displaysleep 5 || warn "Failed to set battery displaysleep"
    sudo pmset -b sleep 15 || warn "Failed to set battery sleep"
    # Laptop — AC
    sudo pmset -c displaysleep 10 || warn "Failed to set AC displaysleep"
    sudo pmset -c sleep 0 || warn "Failed to set AC sleep"
  fi

  # ---------- Printers (optional) ----------
  echo
  if lpstat -p "Ricoh_MP_C4503" &>/dev/null && lpstat -p "HP_CM4540" &>/dev/null; then
    ok "Office printers already configured"
  else
    echo -n "Set up office printers (Ricoh MP C4503 + HP CM4540)? (y/n) "
    read -r setup_printers
    if [[ "$setup_printers" == "y" ]]; then
      if ! lpstat -p "Ricoh_MP_C4503" &>/dev/null; then
        log "Adding Ricoh MP C4503"
        lpadmin -p "Ricoh_MP_C4503" -E -v "socket://10.10.1.240" -m everywhere \
          && ok "Ricoh added" || warn "Failed to add Ricoh — check the IP"
      else
        ok "Ricoh already configured"
      fi

      if ! lpstat -p "HP_CM4540" &>/dev/null; then
        log "Adding HP Color LaserJet CM4540"
        lpadmin -p "HP_CM4540" -E -v "socket://NPI3E5ABA.local" -m everywhere \
          && ok "HP added" || warn "Failed to add HP — check network"
      else
        ok "HP already configured"
      fi
    fi
  fi

  # ---------- Restart affected services ----------
  log "Restarting Dock and Finder to apply settings"
  killall Dock Finder SystemUIServer 2>/dev/null || true
fi

# ──────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────
echo
if [[ "$ERRORS" -gt 0 ]]; then
  warn "Setup finished with $ERRORS warning(s) — review the output above"
else
  ok "Setup complete — no errors!"
fi
echo
echo "Next steps:"
echo "  • Log out and back in (or run 'zsh') to enter your new shell."
echo "  • Set your terminal font to 'JetBrainsMono Nerd Font'."
echo "  • Open nvim once to let AstroNvim install plugins (:Lazy sync if needed)."
if [[ "$OS" == "Darwin" ]]; then
  echo "  • Add your home folder to the Finder sidebar manually."
fi
