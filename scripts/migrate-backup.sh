#!/usr/bin/env bash
#
# Run on the OLD Mac. Produces two artifacts:
#   ~/dotfiles/Brewfile                       - package list (safe to git commit/push)
#   ~/Desktop/mac-migration-<date>.tar.gz      - local-only app data (DO NOT commit/push,
#                                                 it can contain saved DB connections/licenses)
#
set -euo pipefail

DOTFILES="$HOME/dotfiles"
STAMP="$(date +%Y%m%d)"
ARCHIVE="$HOME/Desktop/mac-migration-${STAMP}.tar.gz"
STAGING="$(mktemp -d)"

echo "==> Installing mas (Mac App Store CLI) so App Store apps are captured too"
brew list mas &>/dev/null || brew install mas

echo "==> Dumping Brewfile (formulae, casks, taps, mas apps) to $DOTFILES/Brewfile"
mkdir -p "$DOTFILES"
brew bundle dump --force --file="$DOTFILES/Brewfile"

echo "==> Staging local-only app data"

# Each entry: "source path" "relative destination inside archive"
add() {
    local src="$1" dest="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$STAGING/$dest")"
        cp -a "$src" "$STAGING/$dest"
        echo "  + $dest"
    fi
}

add "$HOME/.config/karabiner/karabiner.json" "karabiner/karabiner.json"

add "$HOME/Library/Application Support/Transmit/Connections.transmitstore" "transmit/Connections.transmitstore"
add "$HOME/Library/Application Support/Transmit/s3Regions.json" "transmit/s3Regions.json"
add "$HOME/Library/Application Support/Transmit/Metadata" "transmit/Metadata"

add "$HOME/Library/Application Support/Tinkerwell/snippets.json" "tinkerwell/snippets.json"
add "$HOME/Library/Application Support/Tinkerwell/settings.json" "tinkerwell/settings.json"
add "$HOME/Library/Application Support/Tinkerwell/history.json" "tinkerwell/history.json"
add "$HOME/Library/Application Support/Tinkerwell/completion.json" "tinkerwell/completion.json"
add "$HOME/Library/Application Support/Tinkerwell/vuex.json" "tinkerwell/vuex.json"

add "$HOME/Library/Application Support/com.tinyapp.TablePlus/Data" "tableplus/Data"
add "$HOME/Library/Application Support/com.tinyapp.TablePlus/.licensemac" "tableplus/.licensemac"

for f in site-groups.json site-statuses.json user-preferences.json profiles-user.json \
         settings-new-site-defaults.json settings-theme-appearance.json graphql-connection-info.json; do
    add "$HOME/Library/Application Support/Local/$f" "local-flywheel/$f"
done

add "$HOME/Library/Application Support/Herd/config/herd.json" "herd/herd.json"

# Cura: keep profiles/materials/machine instances, skip cache/log
if [[ -d "$HOME/Library/Application Support/cura" ]]; then
    for ver_dir in "$HOME/Library/Application Support/cura"/*/; do
        ver="$(basename "$ver_dir")"
        [[ "$ver" == ".sentry-native" ]] && continue
        mkdir -p "$STAGING/cura/$ver"
        rsync -a --exclude=cache --exclude='*.log' "$ver_dir" "$STAGING/cura/$ver/"
    done
    echo "  + cura/*"
fi

# Blender: keep prefs, skip cache
if [[ -d "$HOME/Library/Application Support/Blender" ]]; then
    rsync -a --exclude=Cache --exclude=cache "$HOME/Library/Application Support/Blender/" "$STAGING/blender/"
    echo "  + blender/*"
fi

echo "==> Creating archive: $ARCHIVE"
tar -czf "$ARCHIVE" -C "$STAGING" .
rm -rf "$STAGING"

echo
echo "Done."
echo "  Brewfile:  $DOTFILES/Brewfile  (commit this to git)"
echo "  App data:  $ARCHIVE  (transfer via AirDrop / USB / private cloud folder - NOT git)"
