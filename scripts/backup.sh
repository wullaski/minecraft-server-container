#!/usr/bin/env bash
# Back up the Minecraft server to a .tar.gz file and upload it to Proton Drive.
#
# Usage:  sudo ./backup.sh
set -euo pipefail

SERVER_DIR=/home/minecraft/minecraft_server
BACKUP_DIR=/home/minecraft/backups
KEEP_LOCAL=5             # how many backups to keep on the server
KEEP_REMOTE=7            # how many backups to keep on Proton Drive
MC_USER=minecraft
SERVICE=minecraft.service
SCREEN_NAME=mcjava
WORLD=shadowrealm        # level-name in server.properties
PROTON_FOLDER="/my-files/Shadowrealm Backups"

# The Proton login is saved in root's `pass` store (see README).
export PROTON_DRIVE_CREDENTIALS_STORE=pass

[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

# Type a command into the server console (the screen session).
console() {
  sudo -u "$MC_USER" screen -S "$SCREEN_NAME" -p 0 -X stuff "$1\r"
}

# Is the server running? (If it's stopped, we can skip pausing autosave.)
if systemctl is-active --quiet "$SERVICE"; then
  RUNNING=yes
else
  RUNNING=no
fi

# Step 1: stop autosave and write everything to disk, so files don't change while we copy.
if [[ $RUNNING == yes ]]; then
  echo "Pausing autosave and saving the world..."
  console "save-off"
  console "save-all flush"
  sleep 10   # the save takes about a second; wait a bit longer to be safe
else
  echo "Server is stopped, no need to pause autosave."
fi

# Step 2: pack the server folder into a dated .tar.gz (about 20s).
# Skips cache, libraries and versions; Paper re-downloads those on startup.
ARCHIVE="$BACKUP_DIR/shadowrealm-$(date +%Y-%m-%d-%H%M).tar.gz"
echo "Creating $ARCHIVE..."
sudo -u "$MC_USER" mkdir -p "$BACKUP_DIR"
if ! tar -czf "$ARCHIVE" -C "$SERVER_DIR" --exclude=./cache --exclude=./libraries --exclude=./versions . ; then
  echo "tar failed!"
  if [[ $RUNNING == yes ]]; then console "save-on"; fi
  exit 1
fi

# Step 3: turn autosave back on.
if [[ $RUNNING == yes ]]; then
  console "save-on"
  echo "Autosave back on."
fi

# Step 4: check the archive can be read and has the world in it.
if ! tar -tzf "$ARCHIVE" > /dev/null; then
  echo "Backup is broken: $ARCHIVE"
  exit 1
fi
if ! tar -tzf "$ARCHIVE" | grep "^./$WORLD/level.dat$" > /dev/null; then
  echo "Backup is missing the world ($WORLD/level.dat): $ARCHIVE"
  exit 1
fi

echo "Backup OK: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# Step 5: upload to Proton Drive (2-3 minutes). The local copy stays either way.
echo "Uploading to Proton Drive: $PROTON_FOLDER..."
if ! proton-drive filesystem upload "$ARCHIVE" "$PROTON_FOLDER"; then
  echo "Upload failed. The local backup is still at $ARCHIVE"
  exit 1
fi

# Step 6: delete old local backups, keeping the newest $KEEP_LOCAL.
# `ls -t` lists newest first, so everything after the first $KEEP_LOCAL is old.
count=0
for file in $(ls -t "$BACKUP_DIR"/shadowrealm-*.tar.gz); do
  count=$((count + 1))
  if (( count > KEEP_LOCAL )); then
    echo "Deleting old local backup: $file"
    rm "$file"
  fi
done

# Step 7: delete old backups on Proton Drive, keeping the newest $KEEP_REMOTE.
# Proton only deletes from the trash, so each old file is trashed, then deleted from /trash.
# Filenames start with the date, so sorting by name newest-first (sort -r) sorts by age.
# Only files named shadowrealm-*.tar.gz are touched; anything else in the folder is left alone.
# (`|| true` stops the script from exiting when grep finds no matching files.)
remote_files=$(proton-drive filesystem list -j "$PROTON_FOLDER" \
               | jq -r '.[].name.value' \
               | grep '^shadowrealm-.*\.tar\.gz$' \
               | sort -r) || true
count=0
for name in $remote_files; do
  count=$((count + 1))
  if (( count > KEEP_REMOTE )); then
    echo "Deleting old Proton Drive backup: $name"
    if ! proton-drive filesystem trash "$PROTON_FOLDER/$name"; then
      echo "Couldn't trash $name on Proton Drive (the new backup is fine)."
    elif ! proton-drive filesystem delete "/trash/$name"; then
      echo "$name is in the Proton trash but couldn't be deleted; empty the trash in the app."
    fi
  fi
done

echo "All done."
