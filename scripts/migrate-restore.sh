#!/usr/bin/env bash
#
# Run on the NEW Mac after: (1) cloning ~/dotfiles, (2) copying the
# mac-migration-<date>.tar.gz archive onto this machine.
#
# Usage: ./migrate-restore.sh [--claude-only | --herd-only] /path/to/<archive>.tar.gz
#   --claude-only / --herd-only
#                   Skip Homebrew, the Brewfile and shell setup; just restore what's in
#                   the archive (e.g. one made with the matching migrate-backup.sh option).
#
# Safe to re-run: Herd sites already linked/secured, PHP versions already installed and
# databases that already exist are skipped.
#
set -euo pipefail

ONLY=""
case "${1:-}" in
    --claude-only) ONLY=claude; shift ;;
    --herd-only)   ONLY=herd; shift ;;
esac
ARCHIVE="${1:?Usage: migrate-restore.sh [--claude-only | --herd-only] /path/to/<archive>.tar.gz}"
DOTFILES="$HOME/dotfiles"
STAGING="$(mktemp -d)"

if [[ -z "$ONLY" ]]; then
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
fi

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

if [[ -d "$STAGING/herd" ]]; then
    echo "==> Restoring Herd"
    HERD="$HOME/Library/Application Support/Herd"
    HERD_BIN="$HERD/bin/herd"
    MARIADB="$HERD/bin/mariadb"

    if [[ ! -x "$HERD_BIN" ]]; then
        echo "  ! Herd hasn't been set up yet. Open Herd, finish its first-run setup, then run:"
        echo "      $0 --herd-only $ARCHIVE"
    else
        # Herd rewrites its config files on quit, so swap them in while it's closed.
        osascript -e 'quit app "Herd"' 2>/dev/null || true
        sleep 2
        restore "herd/herd.json" "$HERD/config/herd.json"
        restore "herd/services.plist" "$HERD/config/services.plist"
        restore "herd/valet/config.json" "$HERD/config/valet/config.json"
        if [[ -d "$STAGING/herd/php" ]]; then
            rsync -a "$STAGING/herd/php/" "$HERD/config/php/"
            echo "  + restored herd/php/*/*.ini"
        fi
        open -a Herd
        echo "  ... waiting for Herd to start"
        for _ in $(seq 30); do "$HERD_BIN" php:list &>/dev/null && break; sleep 2; done

        # PHP versions, then the global one (marked with *).
        installed="$("$HERD_BIN" php:list 2>/dev/null | awk -F'|' '$3 ~ /^ *Installed *$/ { gsub(/[ *]/, "", $2); print $2 }')"
        touch "$STAGING/herd/php-versions.txt" "$STAGING/herd/links.tsv" "$STAGING/herd/secured.txt"
        while read -r ver; do
            [[ -n "$ver" ]] || continue
            v="${ver%\*}"
            if grep -qx "$v" <<< "$installed"; then
                echo "  = PHP $v already installed"
            else
                "$HERD_BIN" php:install "$v" -n || echo "  ! couldn't install PHP $v"
            fi
            [[ "$ver" == *\* ]] && "$HERD_BIN" use "$v" >/dev/null && echo "  + global PHP set to $v"
        done < "$STAGING/herd/php-versions.txt"

        # Linked sites - the projects have to be at the same paths on this Mac.
        while IFS=$'\t' read -r name path; do
            [[ -n "$name" ]] || continue
            if [[ -L "$HERD/config/valet/Sites/$name" ]]; then
                echo "  = $name already linked"
            elif [[ -d "$path" ]]; then
                (cd "$path" && "$HERD_BIN" link "$name" >/dev/null) && echo "  + linked $name -> $path"
            else
                echo "  ! skipped $name: $path doesn't exist here yet (copy the project, then re-run)"
            fi
        done < "$STAGING/herd/links.tsv"

        # HTTPS: issue fresh certificates signed by this Mac's Herd CA.
        while read -r domain; do
            [[ -n "$domain" ]] || continue
            if [[ -e "$HERD/config/valet/Certificates/$domain.crt" ]]; then
                echo "  = $domain already secured"
            else
                # `secure` takes the site name and adds the TLD itself.
                "$HERD_BIN" secure "${domain%.*}" && echo "  + secured $domain"
            fi
        done < "$STAGING/herd/secured.txt"

        # Custom per-site Nginx configs go in after `secure`, which writes its own default.
        if [[ -d "$STAGING/herd/valet/Nginx" ]]; then
            mkdir -p "$HERD/config/valet/Nginx"
            rsync -a "$STAGING/herd/valet/Nginx/" "$HERD/config/valet/Nginx/"
            echo "  + restored herd/valet/Nginx"
            "$HERD_BIN" restart >/dev/null && echo "  + restarted Herd services"
        fi

        # Databases: imported only if they don't exist yet, so re-runs never clobber data.
        if [[ -d "$STAGING/herd/databases" ]]; then
            if "$MARIADB" -u root -h 127.0.0.1 -e 'SELECT 1' &>/dev/null; then
                for dump in "$STAGING/herd/databases"/*.sql.gz; do
                    db="$(basename "$dump" .sql.gz)"
                    if [[ -n "$("$MARIADB" -u root -h 127.0.0.1 -N -e "SHOW DATABASES LIKE '$db'")" ]]; then
                        echo "  = database $db already exists - left as is"
                    else
                        if gunzip -c "$dump" | "$MARIADB" -u root -h 127.0.0.1; then
                            echo "  + imported database $db"
                        else
                            echo "  ! failed to import $db"
                        fi
                    fi
                done
            else
                echo "  ! Herd's MariaDB isn't running, so databases weren't imported. Start it in"
                echo "    Herd > Settings > Services (it should already be listed), then run:"
                echo "      $0 --herd-only $ARCHIVE"
            fi
        fi
    fi
fi

rm -rf "$STAGING"

echo
echo "Done. Some apps must be launched once before their data folder exists -"
echo "if a restore step above was skipped, open that app once then re-run this script."
