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
STOW_PACKAGES=(zsh nvim tmux fastfetch starship nano)
ERRORS=0
# ================================

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}!${NC}  $*"; ERRORS=$((ERRORS + 1)); }
die()  { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }

OS="$(uname -s)"
log "Detected OS: $OS"

# ──────────────────────────────────────────────
# Section picker
# ──────────────────────────────────────────────
# Track skipped sections as a space-padded string (bash 3.2 safe — macOS
# ships bash 3.2, which has no associative arrays). Sections default to on;
# a section is "skipped" only if its key appears in $SKIPPED.
SKIPPED=" "

if [[ "$OS" == "Darwin" ]]; then
  SECTIONS=(
    "packages:Homebrew packages (Brewfile)"
    "cli_tools:npm CLI tools (Claude Code, Codex)"
    "git_config:Git configuration"
    "shell:Oh My Zsh + plugins"
    "dotfiles:Stow dotfiles"
    "macos_defaults:macOS defaults (Dock autohide, Finder, keyboard, screenshots)"
    "dock:Dock layout (curated apps)"
    "power:Power & energy settings"
    "firewall:Firewall"
    "printers:Office printers"
  )
else
  SECTIONS=(
    "packages:apt packages + CLI tools"
    "git_config:Git configuration"
    "shell:Oh My Zsh + plugins"
    "dotfiles:Stow dotfiles"
  )
fi

echo
echo -e "${BOLD}Select which sections to run:${NC}"
echo -e "${BOLD}(all selected by default — enter numbers to toggle off, then press Enter)${NC}"
echo

for i in "${!SECTIONS[@]}"; do
  entry="${SECTIONS[$i]}"
  label="${entry#*:}"
  num=$((i + 1))
  echo -e "  ${GREEN}[$num]${NC} $label"
done

echo
echo -n "Toggle off (e.g. \"3 5 9\"), or press Enter to run all: "
read -r skip_input

if [[ -n "$skip_input" ]]; then
  for num in $skip_input; do
    idx=$((num - 1))
    if [[ $idx -ge 0 && $idx -lt ${#SECTIONS[@]} ]]; then
      entry="${SECTIONS[$idx]}"
      key="${entry%%:*}"
      label="${entry#*:}"
      SKIPPED="$SKIPPED$key "
      echo -e "  ${YELLOW}Skipping:${NC} $label"
    fi
  done
fi

echo

# Helper to check if a section is enabled (true unless it was toggled off)
run() { [[ "$SKIPPED" != *" $1 "* ]]; }

# ──────────────────────────────────────────────
# macOS
# ──────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then

  # ---------- Xcode CLI tools (always — needed for everything) ----------
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools"
    xcode-select --install
    echo "Press any key once the install finishes…"; read -rn1
  else
    ok "Xcode CLI tools already installed"
  fi

  # ---------- Homebrew (always — needed for packages) ----------
  if ! command -v brew &>/dev/null; then
    log "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew install failed"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    ok "Homebrew already installed"
  fi

  # ---------- Brewfile (with interactive package picker) ----------
  if run packages; then
    # Parse selectable entries (brew/cask lines) from the Brewfile
    PKG_KIND=(); PKG_NAME=(); PKG_ON=()
    while IFS= read -r line; do
      PKG_KIND+=("${line%% *}")
      PKG_NAME+=("$(echo "$line" | sed -E 's/^(brew|cask) "([^"]+)".*/\2/')")
      PKG_ON+=(1)   # default everything on
    done < <(grep -E '^(brew|cask) ' "$DOTFILES_DIR/Brewfile")

    echo
    echo -e "${BOLD}Select packages to install:${NC}"
    echo -e "(all selected by default — enter numbers to toggle off, then press Enter)"
    echo
    echo -e "${BOLD}Formulae (CLI tools):${NC}"
    for i in "${!PKG_NAME[@]}"; do
      [[ "${PKG_KIND[$i]}" == "brew" ]] && echo -e "  ${GREEN}[$((i + 1))]${NC} ${PKG_NAME[$i]}"
    done
    echo
    echo -e "${BOLD}Casks (apps & fonts):${NC}"
    for i in "${!PKG_NAME[@]}"; do
      [[ "${PKG_KIND[$i]}" == "cask" ]] && echo -e "  ${GREEN}[$((i + 1))]${NC} ${PKG_NAME[$i]}"
    done
    echo
    echo -n "Toggle off (e.g. \"3 5 9\"), or press Enter to install all: "
    read -r pkg_skip
    for num in $pkg_skip; do
      idx=$((num - 1))
      if [[ $idx -ge 0 && $idx -lt ${#PKG_NAME[@]} ]]; then
        PKG_ON[$idx]=0
        echo -e "  ${YELLOW}Skipping:${NC} ${PKG_NAME[$idx]}"
      fi
    done
    echo

    # Build a filtered Brewfile (keep taps, drop deselected packages)
    TMP_BREW=$(mktemp)
    grep -E '^tap ' "$DOTFILES_DIR/Brewfile" >> "$TMP_BREW" 2>/dev/null
    for i in "${!PKG_NAME[@]}"; do
      [[ "${PKG_ON[$i]}" -eq 1 ]] && echo "${PKG_KIND[$i]} \"${PKG_NAME[$i]}\"" >> "$TMP_BREW"
    done

    log "Installing selected packages"
    brew bundle --file="$TMP_BREW" || warn "Some Brewfile items may have failed"
    rm -f "$TMP_BREW"
  fi

  # ---------- npm CLI tools ----------
  if run cli_tools; then
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
  fi

  # ---------- Ghostty config (Mac only) ----------
  STOW_PACKAGES+=(ghostty)

# ──────────────────────────────────────────────
# Linux (Debian / Ubuntu)
# ──────────────────────────────────────────────
elif [[ "$OS" == "Linux" ]]; then

  [[ "$EUID" -eq 0 ]] && die "Don't run as root; the script will sudo when needed."
  command -v sudo >/dev/null || die "sudo is required."

  if run packages; then
    # ---------- apt packages ----------
    log "Updating apt and installing base packages"
    sudo apt-get update -qq || warn "apt-get update failed"
    sudo apt-get install -y \
      zsh git curl wget unzip stow tmux build-essential nano \
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
  fi # end packages

else
  die "Unsupported OS: $OS"
fi

# ──────────────────────────────────────────────
# Common setup (both platforms)
# ──────────────────────────────────────────────

# ---------- Git config ----------
if run git_config; then
  log "Configuring git"
  git config --global user.name "Roger Ferworn"
  git config --global user.email "rferworn@aetech.design"
  git config --global init.defaultBranch main
  git config --global core.editor nvim
  ok "Git configured"
fi

# ---------- Oh My Zsh + plugins ----------
if run shell; then
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      || warn "Failed to install Oh My Zsh"
  else
    ok "Oh My Zsh already installed"
  fi

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    log "Installing zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
      || warn "Failed to install zsh-autosuggestions"
  else
    ok "zsh-autosuggestions already installed"
  fi

  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    log "Installing zsh-syntax-highlighting"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
      || warn "Failed to install zsh-syntax-highlighting"
  else
    ok "zsh-syntax-highlighting already installed"
  fi

  # Default shell
  if [[ "${SHELL:-}" != *zsh ]]; then
    log "Setting zsh as default shell"
    chsh -s "$(command -v zsh)" || warn "chsh failed — run manually: chsh -s \$(which zsh)"
  else
    ok "zsh is already the default shell"
  fi
fi

# ---------- Stow dotfiles ----------
if run dotfiles; then
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
fi

# ──────────────────────────────────────────────
# macOS-specific settings
# ──────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then

  # ---------- Detect desktop vs laptop (needed for power settings) ----------
  if run macos_defaults || run power; then
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
  fi

  # ---------- macOS defaults ----------
  if run macos_defaults; then
    log "Configuring Dock"
    defaults write com.apple.dock autohide -bool true

    log "Configuring Finder"
    defaults write com.apple.finder AppleShowAllFiles -bool true
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    defaults write com.apple.finder ShowPathbar -bool true
    defaults write com.apple.finder ShowStatusBar -bool true
    defaults write com.apple.finder NewWindowTarget -string "PfHm"
    defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

    log "Configuring keyboard & input"
    defaults write NSGlobalDomain KeyRepeat -int 2
    defaults write NSGlobalDomain InitialKeyRepeat -int 15
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
    defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

    log "Configuring screenshots"
    mkdir -p "$HOME/Screenshots"
    defaults write com.apple.screencapture location -string "$HOME/Screenshots"
    defaults write com.apple.screencapture type -string "png"

    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

    log "Requiring password after sleep/screensaver"
    defaults write com.apple.screensaver askForPassword -int 1
    defaults write com.apple.screensaver askForPasswordDelay -int 0

    log "Restarting Dock and Finder to apply settings"
    killall Dock Finder SystemUIServer 2>/dev/null || true
  fi

  # ---------- Dock layout ----------
  # Finder is always pinned at the far left by macOS and isn't managed here.
  if run dock; then
    if ! command -v dockutil &>/dev/null; then
      warn "dockutil not found — skipping Dock layout (enable the packages section)"
    else
      log "Setting Dock layout"
      DOCK_APPS=(
        "/Applications/Ghostty.app"
        "/Applications/Google Chrome.app"
        "/Applications/Slack.app"
        "/Applications/Visual Studio Code.app"
        "/Applications/Obsidian.app"
        "/Applications/Claude.app"
      )
      dockutil --no-restart --remove all &>/dev/null || warn "Failed to clear Dock"
      for app in "${DOCK_APPS[@]}"; do
        name="$(basename "$app" .app)"
        if [[ -d "$app" ]]; then
          dockutil --no-restart --add "$app" &>/dev/null \
            && ok "  added $name" \
            || warn "Failed to add $name to Dock"
        else
          warn "Not installed, skipping in Dock: $name"
        fi
      done
      # Right side of the divider: Home folder, then Downloads.
      # Both shown as folder icons (not content piles).
      dockutil --no-restart --add "$HOME" \
        --view list --display folder --sort name &>/dev/null \
        || warn "Failed to add Home stack"
      dockutil --no-restart --add "$HOME/Downloads" \
        --view fan --display folder --sort dateadded &>/dev/null \
        || warn "Failed to add Downloads stack"
      killall Dock 2>/dev/null || true
      ok "Dock configured"
    fi
  fi

  # ---------- Firewall ----------
  if run firewall; then
    log "Enabling firewall"
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on \
      || warn "Failed to enable firewall"
  fi

  # ---------- Power settings ----------
  if run power; then
    log "Configuring power settings ($MAC_TYPE)"
    if [[ "$MAC_TYPE" == "desktop" ]]; then
      sudo pmset -a displaysleep 10 || warn "Failed to set displaysleep"
      sudo pmset -a sleep 0 || warn "Failed to set sleep"
      sudo pmset -a disksleep 0 || warn "Failed to set disksleep"
      sudo pmset -a womp 1 || warn "Failed to set wake on LAN"
      sudo pmset -a autorestart 1 || warn "Failed to set autorestart"
    else
      sudo pmset -b displaysleep 5 || warn "Failed to set battery displaysleep"
      sudo pmset -b sleep 15 || warn "Failed to set battery sleep"
      sudo pmset -c displaysleep 10 || warn "Failed to set AC displaysleep"
      sudo pmset -c sleep 0 || warn "Failed to set AC sleep"
    fi
  fi

  # ---------- Printers ----------
  if run printers; then
    if lpstat -p "Ricoh_MP_C4503" &>/dev/null && lpstat -p "HP_CM4540" &>/dev/null; then
      ok "Office printers already configured"
    else
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
