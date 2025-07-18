#!/usr/bin/env bash

#set -euo pipefail
set +x

# Requirement version for some tools
MIN_VERSION='0.9.0' # Min version for neovim

#################################################
### ENVIRONMENT SETUP
#################################################
log_info() {
  echo -e "\033[0;32m[INFO]$1\033[0m"
}

# Determine distro & package manager
if [ -f /etc/debian_version ]; then
  PM="apt"
  UPDATE_CMD="apt-get update"
  INSTALL_CMD=(apt-get --yes satisfy)
  QUERY_INSTALLED="dpkg-query -W -f='\${Version}' neovim"
elif [ -f /etc/arch-release ]; then
  PM="pacman"
  UPDATE_CMD="pacman -Sy"
  INSTALL_CMD="pacman -Ss neovim"
  QUERY_INSTALLED="pacman -Qi neovim | awk '/MIN_VERSION/ {print \$3}'"
else
  log_info "Unsupported Linux distribution." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Backup old dot files
mkdir -p ~/migration/dotfiles
cp -Rp \
  ~/.bash_history \
  ~/.gitconfig.local \
  ~/.ssh \
  ~/.bashrc \
  ~/.bashrc.user \
  ~/migration/dotfiles 2>/dev/null

# Function to test if $1 < $2 using sort -V
version_lt() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ] && [ "$1" != "$2" ]
}

#################################################
### SETUP FUNCTIONS
#################################################
setup_bash() {
  log_info "Copy bashrc and aliases to $HOME"
  cp ${SCRIPT_DIR}/bash/bashrc ~/.bashrc
  cp ${SCRIPT_DIR}/aliases ~/.bash_aliases

  # Install ble.sh
  log_info "Install ble.sh"
  curl -L https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJf -
  bash ble-nightly/ble.sh --install ~/.local/share
  rm -rf ble-nightly
  log_info "Done seting up Bash"
}

setup_neovim() {
  log_info "Searching for 'neovim' package..."
  $SEARCH_CMD || true

  # Check installed version (empty if not installed)
  INSTALLED_PKG_VERSION=$(eval $QUERY_INSTALLED 2>/dev/null || echo "")
  INSTALLED_VERSION="$INSTALLED_PKG_VERSION"

  # Check for manual installed nvim binary
  if [ -z "$INSTALLED_PKG_VERSION" ] && command -v nvim &>/dev/null; then
    NVIM_BIN=$(command -v nvim)
    log_info "Found manual nvim binary at $NVIM_BIN"
    # parse version from first line, e.g. "NVIM v0.8.3"
    INSTALLED_VERSION=$($NVIM_BIN --version | head -n1 | awk '{print $2}')
  fi

  if [ -n "$INSTALLED_VERSION" ]; then
    log_info "Installed Neovim version: $INSTALLED_VERSION"
  else
    log_info "Neovim is not installed."
  fi

  if [ -z "$INSTALLED_VERSION" ] || version_lt "$INSTALLED_VERSION" "$MIN_VERSION"; then
    if [ -n "$INSTALLED_PKG_VERSION" ]; then
      log_info "Removing distro‐managed neovim ($INSTALLED_PKG_VERSION)…"
      case "$PM" in
      apt) sudo apt autoremove -y neovim ;;
      dnf) sudo dnf remove -y neovim ;;
      yum) sudo yum remove -y neovim ;;
      pacman) sudo pacman -Rns --noconfirm neovim ;;
      zypper) sudo zypper remove -y neovim ;;
      esac
    fi

    log_info "Clean up old nvim binary if any..."
    sudo rm -rf /usr/bin/nvim \
      /usr/lib/nvim \
      /usr/share/nvim \
      /usr/local/bin/nvim \
      /usr/local/lib/nvim \
      /usr/local/share/nvim
    log_info "Installing/upgrading to the latest Neovim release…"

    # Fetch latest tag and download URL for linux64 tarball
    API="https://api.github.com/repos/neovim/neovim/releases/latest"
    LATEST_TAG=$(curl -s "$API" | grep -m1 '"tag_name":' | cut -d\" -f4)
    ASSET_URL=$(curl -s "$API" |
      grep "browser_download_url.*nvim-linux-x86_64.tar.gz" |
      cut -d\" -f4 || true)

    if [ -z "$ASSET_URL" ]; then
      log_info "Error: Could not find Linux x86_64 asset in latest release." >&2
      exit 1
    fi

    # Download and extract
    TMPDIR=$(mktemp -d)
    curl -L "$ASSET_URL" -o "$TMPDIR/nvim.tar.gz"
    sudo tar xzf "$TMPDIR/nvim.tar.gz" -C /usr/local --strip-components=1
    rm -rf "$TMPDIR"

    log_info "Neovim $LATEST_TAG has been installed to /usr/local/bin/nvim"
  else
    log_info
    log_info "Installed Neovim ($INSTALLED_VERSION) ≥ $MIN_VERSION; no action needed."
  fi
}

setup_starship() {
  if "${INSTALL_CMD[@]}" starship; then
    log_info "Install Starship from $PM"
  else
    log_info "Install Starship from Git"
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
  fi
}

# Main
setup_bash
setup_starship

# PS3=$'\n'"Select one to install (or “quit (6)” to exit): "
#
# log_info "Detected package manager: ${PM:-none}"
# select opt in "${OPTIONS[@]}"; do
#   case "$opt" in
#   bash)
#     setup_bash
#     ;;
#   starship)
#     setup_starship
#     ;;
#   git)
#     ./setup_git
#     ;;
#   neovim)
#     ./setup_neovim
#     ;;
#   lazyvim)
#     ./setup_lazyvim
#     ;;
#   quit)
#     echo "Done."
#     break
#     ;;
#   *)
#     echo "Invalid selection. Please enter number instead of text."
#     ;;
#   esac
# done
