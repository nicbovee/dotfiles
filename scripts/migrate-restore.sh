#!/usr/bin/env bash
#
# Run on the NEW Mac after: (1) cloning ~/dotfiles, (2) copying the
# mac-migration-<date>.tar.gz archive onto this machine.
#
# Usage: ./migrate-restore.sh /path/to/mac-migration-<date>.tar.gz
#
set -euo pipefail

ARCHIVE="${1:?Usage: migrate-restore.sh /path/to/mac-migration-<date>.tar.gz}"
DOTFILES="$HOME/dotfiles"
STAGING="$(mktemp -d)"

if ! xcode-select -p &>/dev/null; then
    echo "==> Installing Xcode Command Line Tools (required by Homebrew)"
    xcode-select --install
    echo "Re-run this script after the Command Line Tools install finishes."
    exit 1
fi

if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Installing everything from $DOTFILES/Brewfile"
brew bundle install --file="$DOTFILES/Brewfile"

echo "==> Extracting app data from $ARCHIVE"
tar -xzf "$ARCHIVE" -C "$STAGING"

restore() {
    local src="$STAGING/$1" dest="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        echo "  + restored $2"
    fi
}

restore "karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

restore "transmit/Connections.transmitstore" "$HOME/Library/Application Support/Transmit/Connections.transmitstore"
restore "transmit/s3Regions.json" "$HOME/Library/Application Support/Transmit/s3Regions.json"
restore "transmit/Metadata" "$HOME/Library/Application Support/Transmit/Metadata"

restore "tinkerwell/snippets.json" "$HOME/Library/Application Support/Tinkerwell/snippets.json"
restore "tinkerwell/settings.json" "$HOME/Library/Application Support/Tinkerwell/settings.json"
restore "tinkerwell/history.json" "$HOME/Library/Application Support/Tinkerwell/history.json"
restore "tinkerwell/completion.json" "$HOME/Library/Application Support/Tinkerwell/completion.json"
restore "tinkerwell/vuex.json" "$HOME/Library/Application Support/Tinkerwell/vuex.json"

restore "tableplus/Data" "$HOME/Library/Application Support/com.tinyapp.TablePlus/Data"
restore "tableplus/.licensemac" "$HOME/Library/Application Support/com.tinyapp.TablePlus/.licensemac"

for f in site-groups.json site-statuses.json user-preferences.json profiles-user.json \
         settings-new-site-defaults.json settings-theme-appearance.json graphql-connection-info.json; do
    restore "local-flywheel/$f" "$HOME/Library/Application Support/Local/$f"
done

restore "herd/herd.json" "$HOME/Library/Application Support/Herd/config/herd.json"

if [[ -d "$STAGING/cura" ]]; then
    for ver_dir in "$STAGING/cura"/*/; do
        ver="$(basename "$ver_dir")"
        mkdir -p "$HOME/Library/Application Support/cura/$ver"
        rsync -a "$ver_dir" "$HOME/Library/Application Support/cura/$ver/"
    done
    echo "  + restored cura/*"
fi

if [[ -d "$STAGING/blender" ]]; then
    mkdir -p "$HOME/Library/Application Support/Blender"
    rsync -a "$STAGING/blender/" "$HOME/Library/Application Support/Blender/"
    echo "  + restored blender/*"
fi

rm -rf "$STAGING"

echo
echo "Done. Some apps must be launched once before their data folder exists -"
echo "if a restore step above was skipped, open that app once then re-run this script."
