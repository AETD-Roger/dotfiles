# dotfiles

Cross-platform dotfiles and machine bootstrap for macOS and Linux (Debian/Ubuntu). Clone the repo, run one script, and you're up and running.

## Install

```bash
# macOS — git comes with Xcode CLI tools
git clone https://github.com/AETD-Roger/dotfiles.git ~/dotfiles
cd ~/dotfiles && chmod +x setup.sh && ./setup.sh

# Linux (Debian/Ubuntu)
sudo apt install git
git clone https://github.com/AETD-Roger/dotfiles.git ~/dotfiles
cd ~/dotfiles && chmod +x setup.sh && ./setup.sh
```

The script detects the OS and runs the appropriate setup path.

## What Gets Installed

### CLI Tools (both platforms)

| Tool | Purpose |
|------|---------|
| neovim | Editor (AstroNvim v4) |
| tmux | Terminal multiplexer |
| starship | Cross-platform shell prompt |
| fastfetch | System info display |
| eza | Modern `ls` replacement |
| bat | Modern `cat` replacement |
| fd | Modern `find` replacement |
| fzf | Fuzzy finder |
| ripgrep | Fast search |
| zoxide | Smart `cd` |
| zsh | Shell (with Oh My Zsh) |
| stow | Dotfile symlink manager |

### macOS Only

**Additional CLI tools:** git, gh, ffmpeg, yt-dlp, mosh, node@22

**GUI apps (via Homebrew casks):**
chatgpt, claude, codex, displaylink, elgato-camera-hub, ghostty, google-chrome, google-drive, maccy, obsidian, slack, telegram, visual-studio-code, vlc, wireguard

**npm CLI tools:** Claude Code (`@anthropic-ai/claude-code`), Codex (`@openai/codex`)

**Font:** JetBrains Mono Nerd Font

### Linux Only

Installs the same CLI tools via apt (with manual installs for eza, zoxide, starship, fastfetch, and neovim where needed). JetBrains Mono Nerd Font is installed from GitHub releases.

## What Gets Configured

### Dotfiles (stowed via GNU Stow)

All dotfiles are symlinked from the repo into `$HOME`, so editing them in place automatically updates the repo copy.

| Package | Files | Platforms |
|---------|-------|-----------|
| zsh | `~/.zshrc` | Both |
| nvim | `~/.config/nvim/` | Both |
| tmux | `~/.tmux.conf` | Both |
| starship | `~/.config/starship.toml` | Both |
| fastfetch | `~/.config/fastfetch/config.jsonc` | Both |
| ghostty | `~/.config/ghostty/config` | macOS only |

### macOS Defaults

**Dock:** Autohide enabled

**Finder:** Show hidden files, show file extensions, path bar, status bar, new windows open `~/`, search scoped to current folder, no extension change warning

**Keyboard & Input:** Fast key repeat, auto-correct off, smart quotes off, smart dashes off, auto-capitalize off

**Screenshots:** Saved to `~/Screenshots` as PNG

**Security:** Firewall enabled, password required after sleep/screensaver

**Power (desktop):** Display sleep 10 min, system sleep never, disk sleep never, wake on LAN, auto restart on power loss

**Power (laptop):** Battery — display sleep 5 min, system sleep 15 min. AC — display sleep 10 min, system sleep never

**Other:** No .DS_Store on network drives

### Printers (optional)

The script offers to add office printers:
- Ricoh MP C4503 (10.10.1.240)
- HP Color LaserJet CM4540 (NPI3E5ABA.local)

### Git

Configures `user.name`, `user.email`, default branch (`main`), and default editor (`nvim`).

### Zsh Plugins

- git, tmux, zsh-autosuggestions, zsh-syntax-highlighting (both platforms)
- brew (macOS only)

## Repo Structure

```
dotfiles/
├── Brewfile                                # Homebrew packages (macOS)
├── setup.sh                                # Cross-platform bootstrap
├── README.md
├── fastfetch/.config/fastfetch/config.jsonc
├── ghostty/.config/ghostty/config          # macOS only
├── nvim/.config/nvim/                      # AstroNvim v4
├── starship/.config/starship.toml
├── tmux/.tmux.conf
└── zsh/.zshrc
```

## Updating Dotfiles

Since everything is symlinked via stow, just edit the files in place — they're the same files the repo tracks.

```bash
# Edit a config (e.g., zsh)
nvim ~/.zshrc

# Commit and push
cd ~/dotfiles
git add -A
git commit -m "update zshrc"
git push
```

## Re-running on an Existing Machine

The script is idempotent — it skips tools that are already installed and overwrites stowed symlinks. Safe to re-run after pulling updates:

```bash
cd ~/dotfiles
git pull
./setup.sh
```
