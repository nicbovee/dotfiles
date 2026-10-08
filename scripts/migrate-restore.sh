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
# brew bundle install already passes --adopt for every cask by default, so if an app
# is already present (pre-installed, downloaded manually, etc.) it gets taken over by
# Homebrew instead of failing - unless its version doesn't match the cask's current
# version, in which case brew will print an error for that one cask and skip it. If
# that happens, update the app to match (or delete it) and re-run this script. Kept
# non-fatal so one bad cask can't abort the whole restore under `set -e`.
brew bundle install --file="$DOTFILES/Brewfile" \
    || echo "  ! some Brewfile entries failed - see above; fix them and re-run this script"

echo "==> Cloning powerlevel10k theme (excluded from git, treated as a regenerable dependency)"
# Test for the theme file itself, not the directory: a stale or empty powerlevel10k/
# directory would otherwise look like a successful install and silently skip the clone.
if [[ ! -f "$DOTFILES/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
    rm -rf "$DOTFILES/powerlevel10k"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$DOTFILES/powerlevel10k"
else
    echo "  + already installed"
fi

echo "==> Installing Oh My Zsh (sourced by .zshrc)"
if [[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    # --keep-zshrc: otherwise the installer moves ~/.zshrc aside and writes its own template.
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
else
    echo "  + already installed"
fi

# .zshrc sets ZSH_THEME="powerlevel10k/powerlevel10k", which Oh My Zsh resolves under
# custom/themes - point it at the copy cloned above rather than cloning a second one.
P10K_THEME_LINK="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [[ ! -e "$P10K_THEME_LINK" ]]; then
    mkdir -p "$(dirname "$P10K_THEME_LINK")"
    ln -s "$DOTFILES/powerlevel10k" "$P10K_THEME_LINK"
fi

echo "==> Linking ~/.zshrc to $DOTFILES/.zshrc"
# Written as an `if` rather than `[[ ... ]] && mv`: under `set -e` that one-liner
# aborts the whole script when the test is false (i.e. on a clean Mac with no ~/.zshrc).
if [[ -e "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
    mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
fi
ln -sf "$DOTFILES/.zshrc" "$HOME/.zshrc"

echo "==> Linking ~/.p10k.zsh to $DOTFILES/.p10k.zsh"
if [[ -e "$HOME/.p10k.zsh" && ! -L "$HOME/.p10k.zsh" ]]; then
    mv "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.bak"
fi
ln -sf "$DOTFILES/.p10k.zsh" "$HOME/.p10k.zsh"

echo "==> Linking ~/.config/nvim to $DOTFILES/nvim"
mkdir -p "$HOME/.config"
if [[ -e "$HOME/.config/nvim" && ! -L "$HOME/.config/nvim" ]]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
fi
# ln -sfn (not -sf): without -n, if ~/.config/nvim is already a symlink to the repo,
# ln follows it and creates ~/.config/nvim/nvim instead of replacing the link.
ln -sfn "$DOTFILES/nvim" "$HOME/.config/nvim"

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

restore "claude/settings.json" "$HOME/.claude/settings.json"
if [[ -d "$STAGING/claude/hooks" ]]; then
    mkdir -p "$HOME/.claude/hooks"
    rsync -a "$STAGING/claude/hooks/" "$HOME/.claude/hooks/"
    echo "  + restored claude/hooks"
fi
# Memory folders are keyed by project path (e.g. -Users-nic-Projects-foo), so they only
# get picked up if the projects live at the same paths on this Mac.
if [[ -d "$STAGING/claude/projects" ]]; then
    mkdir -p "$HOME/.claude/projects"
    rsync -a "$STAGING/claude/projects/" "$HOME/.claude/projects/"
    echo "  + restored claude/projects/*/memory"
fi

rm -rf "$STAGING"

echo
echo "Done. Some apps must be launched once before their data folder exists -"
echo "if a restore step above was skipped, open that app once then re-run this script."
