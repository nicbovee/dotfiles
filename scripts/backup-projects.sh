#!/usr/bin/env bash
#
# Archives ~/Projects for moving to a new machine, excluding regenerable
# dependency/build output (vendor, node_modules, dist, build, target, venv).
# .env files and other dotfiles are included since they aren't reinstallable
# and often aren't committed to git.
#
# Usage: ./backup-projects.sh [destination-dir]
#   Defaults to ~/Desktop if no destination is given.
#
set -euo pipefail

SRC="$HOME/Projects"
DEST_DIR="${1:-$HOME/Desktop}"
STAMP="$(date +%Y%m%d)"
ARCHIVE="$DEST_DIR/projects-backup-${STAMP}.tar.gz"

EXCLUDES=(
    --exclude="vendor"
    --exclude="node_modules"
    --exclude=".venv"
    --exclude="venv"
    --exclude="dist"
    --exclude="build"
    --exclude="target"
)

echo "==> Archiving $SRC -> $ARCHIVE"
echo "    Excluding: vendor, node_modules, .venv, venv, dist, build, target"

tar -czf "$ARCHIVE" "${EXCLUDES[@]}" -C "$HOME" "Projects"

echo
echo "Done: $ARCHIVE"
du -h "$ARCHIVE"
