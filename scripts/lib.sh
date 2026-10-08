#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts — not run directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT/config.env"

if [[ "$SERVER_MODE" == docker ]]; then
  SERVER_DIR="$ROOT/data"
  COMPOSE=(docker compose -f "$ROOT/docker-compose.yml")
fi
export PROTON_DRIVE_CREDENTIALS_STORE

log()  { echo "[$(date '+%F %T')] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

need() { for c in "$@"; do command -v "$c" >/dev/null || die "missing command: $c"; done; }

# One script at a time (backup + update must not overlap). Nested calls skip the lock.
take_lock() {
  [[ -n "${SHADOWREALM_LOCKED:-}" ]] && return 0
  exec 9>/tmp/shadowrealm.lock
  flock -n 9 || die "another shadowrealm script is running"
  export SHADOWREALM_LOCKED=1
}

# Run a command as the user that owns the server (systemd mode only).
as_mc() {
  if [[ "$SERVER_MODE" == docker || "$(id -un)" == "$MC_USER" ]]; then
    "$@"
  else
    sudo -H -u "$MC_USER" "$@"
  fi
}

server_running() {
  if [[ "$SERVER_MODE" == docker ]]; then
    [[ -n "$("${COMPOSE[@]}" ps --status running -q "$DOCKER_SERVICE" 2>/dev/null)" ]]
  else
    systemctl is-active --quiet "$SERVICE_NAME"
  fi
}

# Send a command to the server console, e.g. console "say hi"
console() {
  if [[ "$SERVER_MODE" == docker ]]; then
    "${COMPOSE[@]}" exec -T "$DOCKER_SERVICE" rcon-cli "$1" >/dev/null
  else
    as_mc screen -S "$SCREEN_NAME" -p 0 -X stuff "$1"$'\r'
  fi
}

server_stop() {
  log "stopping server"
  if [[ "$SERVER_MODE" == docker ]]; then
    "${COMPOSE[@]}" stop "$DOCKER_SERVICE"
  else
    sudo systemctl stop "$SERVICE_NAME"
    # wait for java to really exit so files are flushed
    for _ in $(seq 1 60); do
      pgrep -u "$MC_USER" -f "$SERVER_JAR" >/dev/null || return 0
      sleep 2
    done
    die "server did not stop within 120s"
  fi
}

server_start() {
  log "starting server"
  if [[ "$SERVER_MODE" == docker ]]; then
    "${COMPOSE[@]}" up -d "$DOCKER_SERVICE"
  else
    sudo systemctl start "$SERVICE_NAME"
  fi
}

# Warn players, then stop. Usage: stop_with_warning "reason"
stop_with_warning() {
  if server_running; then
    console "say Server restarting in 30s: $1"
    sleep 30
    server_stop
  fi
}

# Force a full world save and wait for "Saved the game" in the log.
save_count() { local n; n=$(grep -c "Saved the game" "$SERVER_DIR/logs/latest.log" 2>/dev/null) || true; echo "${n:-0}"; }
save_and_wait() {
  local before
  before=$(save_count)
  console "save-all flush"
  for _ in $(seq 1 60); do
    sleep 2
    (( $(save_count) > before )) && return 0
  done
  die "timed out waiting for world save"
}

# Proton Drive CLI, run as the user that holds the Proton session.
proton() {
  as_mc env PROTON_DRIVE_CREDENTIALS_STORE="$PROTON_DRIVE_CREDENTIALS_STORE" "$PROTON_BIN" "$@"
}

# Current MC version: MC_VERSION from config, else read from Paper's version_history.json.
mc_version() {
  if [[ -n "$MC_VERSION" ]]; then echo "$MC_VERSION"; return; fi
  local v
  v=$(jq -r '.currentVersion // empty' "$SERVER_DIR/version_history.json" 2>/dev/null \
      | sed -n 's/.*(MC: \([^)]*\)).*/\1/p')
  [[ -n "$v" ]] || die "can't detect MC version — set MC_VERSION in config.env"
  echo "$v"
}

# chown to the server user and their primary group
mc_own() { chown -R "$MC_USER:$(id -gn "$MC_USER")" "$@"; }

api() { curl -fsSL -A "$USER_AGENT" "$@"; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }
