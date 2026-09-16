# Nic's `dotfiles`

This repo is based on [kalkayan/dotfiles](https://github.com/kalkayan/dotfiles/tree/main).

## Migrating to a new Mac

`Brewfile` tracks every formula, cask, tap, and Mac App Store app. `scripts/migrate-backup.sh`
and `scripts/migrate-restore.sh` handle the app data that Homebrew can't (saved DB
connections, license files, snippets, etc.) via a separate archive that never goes into git.

### On the old Mac

1. Clone this repo (if not already) and pull the latest.
2. Run the backup script:
   ```
   ./scripts/migrate-backup.sh
   ```
   This regenerates `Brewfile` from your current setup and writes
   `~/Desktop/mac-migration-<date>.tar.gz` containing local-only app data for:
   - Karabiner-Elements rules
   - Transmit saved connections/favorites
   - Tinkerwell snippets/settings/history
   - TablePlus saved connections + license
   - Local (Flywheel) site config
   - Herd site/PHP config
   - Cura print profiles
   - Blender preferences
3. Commit and push the regenerated `Brewfile` if it changed:
   ```
   git add Brewfile && git commit -m "Update Brewfile" && git push
   ```
4. Move `~/Desktop/mac-migration-<date>.tar.gz` to the new Mac via AirDrop, a USB drive, or a
   private cloud folder — **not** git. It can contain saved DB credentials and license files.
5. Note any paid-app license keys that live outside app-support folders (check email/purchase
   records) as a fallback.

### On the new Mac

1. Clone this repo to `~/dotfiles`.
2. Copy the `mac-migration-<date>.tar.gz` archive onto the machine.
3. Run the restore script:
   ```
   ./scripts/migrate-restore.sh /path/to/mac-migration-<date>.tar.gz
   ```
   This installs Xcode Command Line Tools and Homebrew if missing, runs
   `brew bundle install --file=Brewfile`, then unpacks the archive back into each app's folder.
   Some casks (e.g. those that run a `.pkg` installer with `sudo`) will prompt for your
   password interactively during `brew bundle install` — just enter it when asked.
4. Sign into account-synced apps normally (1Password, Dropbox, Slack, Notion, Google Drive,
   Discord, Arc profile sync, Raycast, etc.) — their data comes down automatically and isn't
   part of the archive.
5. If a restore step is skipped because an app hasn't created its data folder yet, open that
   app once, then re-run the restore script.
6. Manually re-check things that never live in Homebrew or the archive: Wi-Fi passwords,
   Touch ID/Keychain items, Messages/FaceTime login, Time Machine destination.
