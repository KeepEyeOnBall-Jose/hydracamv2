#!/usr/bin/env bash
#
# adb_remote_bridge.sh — drive devices attached to a remote Mac (e.g. the MBA 13
# M1 on the watch/phone LAN) from this computer over Tailscale.
#
# Tailscale links the *Macs*, not the watch. Wear OS wireless-debugging pairing
# uses mDNS and only works on the watch's own LAN, so the `adb` server that owns
# the devices must run on the Mac that is physically on that LAN. This script
# opens an SSH tunnel to that Mac's adb server and points the local `adb`
# client at it, so builds stay here while installs/screencaps flow to the
# remote devices.
#
# Requires on the REMOTE Mac: either macOS Remote Login (System Settings ->
# General -> Sharing -> Remote Login) or Tailscale SSH enabled for the node.
#
# Usage:
#   scripts/adb_remote_bridge.sh up                 # open tunnel + verify
#   scripts/adb_remote_bridge.sh status             # show tunnel + adb devices
#   scripts/adb_remote_bridge.sh down               # close tunnel
#   scripts/adb_remote_bridge.sh pair HOST:PORT CODE  # pair watch ON the remote
#   scripts/adb_remote_bridge.sh connect HOST:PORT    # connect ON the remote
#   eval "$(scripts/adb_remote_bridge.sh env)"      # export the socket here
#
# Override defaults via env:
#   ADB_BRIDGE_HOST         remote MagicDNS name or Tailscale IP (default: joss-macbook-air)
#   ADB_BRIDGE_REMOTE_PORT  remote adb server port (default: 5037)
#   ADB_BRIDGE_LOCAL_PORT   local forwarded port  (default: 5038)
#   ADB_BRIDGE_SSH          ssh command           (default: ssh)
#
set -euo pipefail

HOST="${ADB_BRIDGE_HOST:-joss-macbook-air}"
REMOTE_PORT="${ADB_BRIDGE_REMOTE_PORT:-5037}"
LOCAL_PORT="${ADB_BRIDGE_LOCAL_PORT:-5038}"
SSH_CMD="${ADB_BRIDGE_SSH:-ssh}"
SOCKET="tcp:127.0.0.1:${LOCAL_PORT}"
PIDFILE="${TMPDIR:-/tmp}/hydracam-adb-bridge-${LOCAL_PORT}.pid"

log()  { printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

tunnel_up() {
  # Listening on the local port == tunnel already established.
  nc -z 127.0.0.1 "${LOCAL_PORT}" >/dev/null 2>&1
}

cmd_up() {
  if tunnel_up; then
    log "tunnel already up on 127.0.0.1:${LOCAL_PORT} -> ${HOST}:${REMOTE_PORT}"
  else
    log "ensuring adb server is running on ${HOST}..."
    ${SSH_CMD} -o BatchMode=yes -o ConnectTimeout=8 "${HOST}" 'adb start-server' \
      || die "cannot reach ${HOST} over SSH. Enable Remote Login or Tailscale SSH, and confirm the name resolves (try ADB_BRIDGE_HOST=100.113.103.99)."
    log "opening tunnel 127.0.0.1:${LOCAL_PORT} -> ${HOST}:127.0.0.1:${REMOTE_PORT}..."
    ${SSH_CMD} -o BatchMode=yes -o ConnectTimeout=8 -o ExitOnForwardFailure=yes \
      -fN -L "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" "${HOST}"
    # Record the forwarding ssh pid for clean teardown.
    pgrep -f "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} ${HOST}" > "${PIDFILE}" 2>/dev/null || true
    sleep 1
    tunnel_up || die "tunnel did not come up; check SSH access to ${HOST}."
    log "tunnel up."
  fi
  log ""
  log "Point adb at the remote server in this shell with:"
  log "    export ADB_SERVER_SOCKET=${SOCKET}"
  cmd_status || true
}

cmd_status() {
  if tunnel_up; then
    log "tunnel: UP (127.0.0.1:${LOCAL_PORT} -> ${HOST}:${REMOTE_PORT})"
  else
    log "tunnel: DOWN"
    return 1
  fi
  log "remote adb devices:"
  ADB_SERVER_SOCKET="${SOCKET}" adb devices -l
}

cmd_down() {
  if [ -f "${PIDFILE}" ]; then
    while read -r pid; do
      [ -n "${pid}" ] && kill "${pid}" 2>/dev/null || true
    done < "${PIDFILE}"
    rm -f "${PIDFILE}"
  fi
  # Fallback: kill any ssh forwarding this exact mapping.
  pkill -f "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} ${HOST}" 2>/dev/null || true
  log "tunnel down."
}

cmd_env() {
  # Machine-readable: eval "$(... env)" to export in the current shell.
  printf 'export ADB_SERVER_SOCKET=%s\n' "${SOCKET}"
}

# Run an adb subcommand ON the remote Mac (needed for mDNS pairing/connect,
# which must originate on the watch's LAN).
cmd_remote_adb() {
  ${SSH_CMD} -o BatchMode=yes -o ConnectTimeout=8 "${HOST}" "adb $*"
}

main() {
  local sub="${1:-up}"
  case "${sub}" in
    up)       cmd_up ;;
    status)   cmd_status ;;
    down)     cmd_down ;;
    env)      cmd_env ;;
    pair)
      [ "$#" -eq 3 ] || die "usage: $0 pair HOST:PORT CODE"
      log "pairing on ${HOST} (mDNS must be on the watch LAN)..."
      cmd_remote_adb "pair $2 $3" ;;
    connect)
      [ "$#" -eq 2 ] || die "usage: $0 connect HOST:PORT"
      cmd_remote_adb "connect $2" ;;
    -h|--help|help)
      sed -n '2,40p' "$0" ;;
    *)        die "unknown command '${sub}' (try: up|status|down|env|pair|connect|help)" ;;
  esac
}

main "$@"
