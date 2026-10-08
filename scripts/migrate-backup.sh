#!/usr/bin/env bash
#
# Run on the OLD Mac. Produces two artifacts:
#   ~/dotfiles/Brewfile                       - package list (safe to git commit/push)
#   ~/Desktop/mac-migration-<date>.tar.gz      - local-only app data (DO NOT commit/push,
#                                                 it can contain saved DB connections/licenses)
#
# Usage: ./migrate-backup.sh [--claude-only | --herd-only]
#   --claude-only   Only archive Claude Code memory/settings/hooks to
#                   ~/Desktop/claude-migration-<date>.tar.gz.
#   --herd-only     Only archive Herd config, linked sites and databases to
#                   ~/Desktop/herd-migration-<date>.tar.gz.
#   Either one skips the Brewfile dump, so the Brewfile is left untouched.
#
set -euo pipefail

ONLY=""
case "${1:-}" in
    --claude-only) ONLY=claude ;;
    --herd-only)   ONLY=herd ;;
    "") ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

DOTFILES="$HOME/dotfiles"
STAMP="$(date +%Y%m%d)"
ARCHIVE="$HOME/Desktop/${ONLY:-mac}-migration-${STAMP}.tar.gz"
STAGING="$(mktemp -d)"

# Each entry: "source path" "relative destination inside archive"
add() {
    local src="$1" dest="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$STAGING/$dest")"
        cp -a "$src" "$STAGING/$dest"
        echo "  + $dest"
    fi
}

if [[ -z "$ONLY" ]]; then
    echo "==> Installing mas (Mac App Store CLI) so App Store apps are captured too"
    brew list mas &>/dev/null || brew install mas

    echo "==> Dumping Brewfile (formulae, casks, taps, mas apps) to $DOTFILES/Brewfile"
    mkdir -p "$DOTFILES"
    brew bundle dump --force --file="$DOTFILES/Brewfile"

    echo "==> Staging local-only app data"

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
fi

HERD="$HOME/Library/Application Support/Herd"
if [[ ( -z "$ONLY" || "$ONLY" == herd ) && -d "$HERD/config" ]]; then
    echo "==> Staging Herd config, linked sites and databases"
    # Settings only. PHP/service binaries, logs, sockets, the dumps/mail history DB and
    # TLS certificates are left out - they're re-downloaded or regenerated (a copied CA
    # wouldn't be trusted by the new Mac's keychain anyway).
    add "$HERD/config/herd.json" "herd/herd.json"
    add "$HERD/config/services.plist" "herd/services.plist"
    add "$HERD/config/valet/config.json" "herd/valet/config.json"
    add "$HERD/config/valet/Nginx" "herd/valet/Nginx"
    if [[ -d "$HERD/config/php" ]]; then
        mkdir -p "$STAGING/herd/php"
        rsync -a --include='*/' --include='*.ini' --exclude='*' "$HERD/config/php/" "$STAGING/herd/php/"
        echo "  + herd/php/*/*.ini"
    fi

    # Linked sites as "<name><TAB><path>". Claude worktree links are temporary - skip them.
    : > "$STAGING/herd/links.tsv"
    for link in "$HERD/config/valet/Sites"/*; do
        [[ -L "$link" ]] || continue
        target="$(readlink "$link")"
        [[ "$target" == "$HOME/.claude-worktrees/"* ]] && continue
        printf '%s\t%s\n' "$(basename "$link")" "$target" >> "$STAGING/herd/links.tsv"
    done
    echo "  + herd/links.tsv ($(wc -l < "$STAGING/herd/links.tsv" | tr -d ' ') sites)"

    # Sites served over HTTPS, by domain (certificates get re-issued on restore).
    : > "$STAGING/herd/secured.txt"
    for crt in "$HERD/config/valet/Certificates"/*.crt; do
        [[ -e "$crt" ]] && basename "$crt" .crt >> "$STAGING/herd/secured.txt"
    done
    echo "  + herd/secured.txt ($(wc -l < "$STAGING/herd/secured.txt" | tr -d ' ') sites)"

    # Installed PHP versions; the global one is marked with * in `herd php:list`.
    if [[ -x "$HERD/bin/herd" ]]; then
        "$HERD/bin/herd" php:list 2>/dev/null | awk -F'|' '$3 ~ /^ *Installed *$/ { gsub(/ /, "", $2); print $2 }' \
            > "$STAGING/herd/php-versions.txt"
        echo "  + herd/php-versions.txt ($(tr '\n' ' ' < "$STAGING/herd/php-versions.txt"))"
    fi

    # Databases: dumped one file per DB rather than copying MariaDB's data folder, which
    # isn't safe while it's running. System schemas and test-run DBs are skipped.
    MARIADB="$HERD/bin/mariadb"
    if [[ -x "$MARIADB" ]] && "$MARIADB" -u root -h 127.0.0.1 -e 'SELECT 1' &>/dev/null; then
        mkdir -p "$STAGING/herd/databases"
        for db in $("$MARIADB" -u root -h 127.0.0.1 -N -e 'SHOW DATABASES' 2>/dev/null); do
            case "$db" in
                information_schema|performance_schema|mysql|sys|test|*_test|*_test_[0-9]*) continue ;;
            esac
            if "$HERD/bin/mariadb-dump" -u root -h 127.0.0.1 --single-transaction --routines \
                --triggers --events --databases "$db" 2>/dev/null | gzip > "$STAGING/herd/databases/$db.sql.gz"; then
                echo "  + herd/databases/$db.sql.gz"
            else
                rm -f "$STAGING/herd/databases/$db.sql.gz"
                echo "  ! failed to dump $db - skipped"
            fi
        done
    else
        echo "  ! Herd's MariaDB isn't running - databases NOT backed up. Start it in Herd and re-run."
    fi
fi

if [[ -z "$ONLY" || "$ONLY" == claude ]]; then
    echo "==> Staging Claude Code memory, settings and hooks"
    # Claude Code: per-project memory, settings and hooks. Transcripts, caches and synced
    # skills are left out - they're large, regenerable, or come back on sign-in.
    add "$HOME/.claude/settings.json" "claude/settings.json"
    add "$HOME/.claude/hooks" "claude/hooks"
    if [[ -d "$HOME/.claude/projects" ]]; then
        for mem in "$HOME/.claude/projects"/*/memory; do
            [[ -n "$(ls -A "$mem" 2>/dev/null)" ]] || continue
            add "$mem" "claude/projects/$(basename "$(dirname "$mem")")/memory"
        done
    fi
fi

echo "==> Creating archive: $ARCHIVE"
tar -czf "$ARCHIVE" -C "$STAGING" .
rm -rf "$STAGING"

echo
echo "Done."
[[ -n "$ONLY" ]] || echo "  Brewfile:  $DOTFILES/Brewfile  (commit this to git)"
echo "  App data:  $ARCHIVE  (transfer via AirDrop / USB / private cloud folder - NOT git)"
