#!/usr/bin/env bash
# Restore a backup into SERVER_DIR (the old folder is kept as <dir>.pre-restore-<time>).
# Usage:
#   restore.sh --list                      list backups on Proton Drive
#   restore.sh proton:<file.tar.gz>        download from Proton Drive, then restore
#   restore.sh /path/to/backup.tar.gz      restore a local archive
source "$(dirname "$0")/lib.sh"
need tar
take_lock
[[ $EUID -eq 0 ]] || die "run with sudo"

arg=${1:-}
[[ -n "$arg" ]] || die "usage: restore.sh --list | proton:<file> | <archive.tar.gz>"

if [[ "$arg" == --list ]]; then
  proton filesystem list "$PROTON_PARENT/$PROTON_FOLDER"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
if [[ "$arg" == proton:* ]]; then
  name=${arg#proton:}
  [[ "$SERVER_MODE" == systemd ]] && mc_own "$BACKUP_DIR"
  log "downloading $name from Proton Drive"
  proton filesystem download "$PROTON_PARENT/$PROTON_FOLDER/$name" "$BACKUP_DIR"
  ARCHIVE="$BACKUP_DIR/$name"
else
  ARCHIVE=$(realpath "$arg")
fi
[[ -f "$ARCHIVE" ]] || die "archive not found: $ARCHIVE"
tar -tzf "$ARCHIVE" >/dev/null || die "archive is corrupt: $ARCHIVE"

server_running && server_stop

if [[ -d "$SERVER_DIR" ]]; then
  OLD="$SERVER_DIR.pre-restore-$(date +%Y%m%d-%H%M%S)"
  log "moving current server to $OLD"
  mv "$SERVER_DIR" "$OLD"
fi

log "extracting $ARCHIVE -> $SERVER_DIR"
mkdir -p "$SERVER_DIR"
tar -C "$SERVER_DIR" -xzf "$ARCHIVE"

if [[ "$SERVER_MODE" == docker ]]; then
  chown -R 1000:1000 "$SERVER_DIR"   # the container runs as uid 1000
else
  mc_own "$SERVER_DIR"
  # Backups made in docker mode don't contain paper-server.jar; fetch it.
  [[ -f "$SERVER_DIR/$SERVER_JAR" ]] || "$(dirname "$0")/update-paper.sh" "$(mc_version)"
fi

server_start
log "restore done"
