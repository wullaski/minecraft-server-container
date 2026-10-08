#!/usr/bin/env bash
# Back up, then download the latest stable Paper build for a Minecraft version and restart the server.
#
# Usage:  sudo ./update-paper.sh <minecraft-version>      e.g.  sudo ./update-paper.sh 26.2
#
# Plugin updates: before running this, drop new plugin jars into plugins/update/
# (same filename as the old jar). Paper swaps them in when the server restarts.
set -euo pipefail

SERVER_DIR=/home/minecraft/minecraft_server
JAR=paper-server.jar
SERVICE=minecraft.service
MC_USER=minecraft
USER_AGENT="shadowrealm-scripts/1.0 (wullaski@gmail.com)"   # PaperMC asks for a contact
SCRIPTS_DIR=$(dirname "$0")   # the folder this script is in (backup.sh lives here too)

if [[ $# -ne 1 ]]; then
  echo "usage: sudo ./update-paper.sh <minecraft-version>   e.g. 26.2"
  exit 1
fi
VERSION=$1

if [[ $EUID -ne 0 ]]; then
  echo "run with sudo"
  exit 1
fi

# Step 1: ask PaperMC for this version's builds and take the newest STABLE one.
echo "Checking Paper builds for Minecraft $VERSION..."
build=$(curl -fsSL -A "$USER_AGENT" "https://fill.papermc.io/v3/projects/paper/versions/$VERSION/builds" \
        | jq -c 'map(select(.channel == "STABLE")) | first')
if [[ "$build" == null ]]; then
  echo "No stable Paper build for $VERSION"
  exit 1
fi

id=$(jq -r '.id' <<<"$build")
url=$(jq -r '.downloads."server:default".url' <<<"$build")
sha=$(jq -r '.downloads."server:default".checksums.sha256' <<<"$build")

# Step 2: skip if that exact build is already installed.
if [[ -f "$SERVER_DIR/$JAR" ]]; then
  current_sha=$(sha256sum "$SERVER_DIR/$JAR" | cut -d' ' -f1)
  if [[ "$current_sha" == "$sha" ]]; then
    echo "Already on Paper $VERSION build $id. Nothing to do."
    echo "(To just apply plugins in plugins/update/: sudo systemctl restart $SERVICE)"
    exit 0
  fi
fi

# Step 3: download to a temp file and make sure it isn't corrupted.
echo "Downloading Paper $VERSION build $id..."
tmp=$(mktemp)
curl -fsSL -A "$USER_AGENT" -o "$tmp" "$url"
downloaded_sha=$(sha256sum "$tmp" | cut -d' ' -f1)
if [[ "$downloaded_sha" != "$sha" ]]; then
  echo "Checksum mismatch, aborting"
  rm -f "$tmp"
  exit 1
fi

# Step 4: back up before touching anything. Stop here if the backup fails.
echo "Backing up first..."
if ! "$SCRIPTS_DIR/backup.sh"; then
  echo "Backup failed, not updating."
  rm -f "$tmp"
  exit 1
fi

# Step 5: stop the server, swap the jar (keeping the old one), start it again.
echo "Stopping server..."
systemctl stop "$SERVICE"

if [[ -f "$SERVER_DIR/$JAR" ]]; then
  mv "$SERVER_DIR/$JAR" "$SERVER_DIR/$JAR.old"
fi
mv "$tmp" "$SERVER_DIR/$JAR"
chown "$MC_USER:$(id -gn "$MC_USER")" "$SERVER_DIR/$JAR"
chmod 644 "$SERVER_DIR/$JAR"

echo "Starting server..."
systemctl start "$SERVICE"

echo "Done: Paper $VERSION build $id."
if [[ -f "$SERVER_DIR/$JAR.old" ]]; then
  echo "Previous jar kept as $JAR.old"
fi
echo "Watch it boot:  sudo tail -f $SERVER_DIR/logs/latest.log"
