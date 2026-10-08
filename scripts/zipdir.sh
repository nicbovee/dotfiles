#!/usr/bin/env bash
#
# Zips one or more directories, leaving out anything git ignores.
#
# Inside a git repo, only files git would show (tracked + untracked-but-not-ignored)
# are included; this respects .gitignore, .git/info/exclude and your global excludes.
# Repos nested inside the directory (embedded repos, submodules) are handled with
# their own ignore rules. Folders that aren't in any repo are included in full, minus
# the usual regenerable dependency folders (node_modules, vendor, venv, ...).
#
# Usage: zipdir.sh [-o out-dir] [-k pattern]... DIR...
#   -o out-dir   Where to write the zips (default: ~/Desktop)
#   -k pattern   Keep ignored files/folders whose name matches this glob anyway,
#                e.g. -k '.env*'. Repeatable. Matches entries git ignores directly;
#                a matching folder is kept whole.
#
# Each DIR becomes <out-dir>/<dir-name>-<YYYYMMDD>.zip with the folder at its root.
#
set -euo pipefail

OUT_DIR="$HOME/Desktop"
KEEP=()
# Only applied outside git repos, where there's no .gitignore to go by.
NON_GIT_SKIP=(node_modules vendor .venv venv __pycache__ .DS_Store)

usage() { sed -n '/^# Usage:/,/^# Each DIR/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:k:h" opt; do
    case "$opt" in
        o) OUT_DIR="$OPTARG" ;;
        k) KEEP+=("$OPTARG") ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] || usage 1

matches_keep() {
    local name="$1" pat
    for pat in ${KEEP[@]+"${KEEP[@]}"}; do
        # shellcheck disable=SC2254
        case "$name" in $pat) return 0 ;; esac
    done
    return 1
}

skipped_non_git() {
    local name="$1" s
    for s in "${NON_GIT_SKIP[@]}"; do [[ "$name" == "$s" ]] && return 0; done
    return 1
}

# Every file under $1, as NUL-separated paths. Callers cd to the zip's base dir first.
list_all() {
    find "$1" -type f -print0 -o -type l -print0
}

# Listings go through temp files rather than `< <(...)`: macOS's bash 3.2 aborts when
# process substitution is nested through these recursive functions.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Files git would keep in repo $1 (paths prefixed with $1/).
list_git() {
    local repo="$1" entry name listing
    listing="$(mktemp "$TMP_DIR/ls.XXXXXX")"
    git -C "$repo" ls-files -z --cached --others --exclude-standard > "$listing"
    while IFS= read -r -d '' entry; do
        if [[ "$entry" == */ ]]; then
            # Untracked nested repo - git lists it as a folder; apply its own rules.
            [[ -e "$repo/$entry/.git" ]] && list_git "$repo/${entry%/}" || list_all "$repo/${entry%/}"
        elif [[ -d "$repo/$entry" && ! -L "$repo/$entry" ]]; then
            # Submodule (a tracked gitlink).
            list_git "$repo/$entry"
        elif [[ -e "$repo/$entry" || -L "$repo/$entry" ]]; then
            # (Tracked files deleted from disk are skipped.)
            printf '%s\0' "$repo/$entry"
        fi
    done < "$listing"

    # Ignored entries: keep the ones matching -k, report skipped .env files.
    git -C "$repo" ls-files -z --others --ignored --exclude-standard --directory > "$listing"
    while IFS= read -r -d '' entry; do
        entry="${entry%/}"
        name="$(basename "$entry")"
        if matches_keep "$name"; then
            if [[ -d "$repo/$entry" ]]; then list_all "$repo/$entry"; else printf '%s\0' "$repo/$entry"; fi
        elif [[ "$name" == .env* ]]; then
            echo "    skipped ignored $repo/$entry (use -k '.env*' to keep)" >&2
        fi
    done < "$listing"
    rm -f "$listing"
}

# Files under non-git folder $1, switching to git rules for any repo found inside.
list_dir() {
    local dir="$1" entry name listing
    listing="$(mktemp "$TMP_DIR/ls.XXXXXX")"
    find "$dir" -mindepth 1 -maxdepth 1 -print0 > "$listing"
    while IFS= read -r -d '' entry; do
        name="$(basename "$entry")"
        if [[ -d "$entry" && ! -L "$entry" ]]; then
            skipped_non_git "$name" && continue
            if [[ -e "$entry/.git" ]]; then list_git "$entry"; else list_dir "$entry"; fi
        else
            skipped_non_git "$name" || printf '%s\0' "$entry"
        fi
    done < "$listing"
    rm -f "$listing"
}

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAMP="$(date +%Y%m%d)"

for target in "$@"; do
    [[ -d "$target" ]] || { echo "Not a directory: $target" >&2; exit 1; }
    target="$(cd "$target" && pwd)"
    base="$(dirname "$target")"
    name="$(basename "$target")"
    zipfile="$OUT_DIR/${name}-${STAMP}.zip"

    echo "==> $target -> $zipfile"
    rm -f "$zipfile"
    (
        cd "$base"
        if git -C "$name" rev-parse --is-inside-work-tree &>/dev/null; then
            list_git "$name"
        else
            list_dir "$name"
        fi
    ) | tr '\0' '\n' | (cd "$base" && zip -q -y "$zipfile" -@)

    echo "    $(unzip -Z1 "$zipfile" | wc -l | tr -d ' ') files, $(du -h "$zipfile" | cut -f1)"
done
