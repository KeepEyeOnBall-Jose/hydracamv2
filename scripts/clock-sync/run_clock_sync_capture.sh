#!/usr/bin/env bash
#
# run_clock_sync_capture.sh — drive one multi-camera synchronized recording of
# the filmed millisecond clock, pull the clips + sync sidecars off every device,
# and (optionally) compute inter-camera drift.
#
# Prereq: the fleet is deployed/launched (scripts/hybrid_deploy.sh deploy) and
# every camera is pointing down at a screen showing scripts/clock-sync/clock.html
# fullscreen. The master must be reachable on its automation bridge.
#
# Usage:
#   scripts/clock-sync/run_clock_sync_capture.sh record [SECONDS]   # default 12
#   scripts/clock-sync/run_clock_sync_capture.sh pull OUTDIR
#   scripts/clock-sync/run_clock_sync_capture.sh analyze OUTDIR
#   scripts/clock-sync/run_clock_sync_capture.sh run [SECONDS]      # record+pull+analyze
#
#   FLEET=scripts/clock-sync/fleet.conf scripts/clock-sync/run_clock_sync_capture.sh run 15
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLEET="${FLEET:-${REPO_ROOT}/scripts/clock-sync/fleet.conf}"
PKG="com.amaia23.hydracam"
BRIDGE_PORT=4762
ANALYZER="${REPO_ROOT}/scripts/clock-sync/clock_drift_from_frames.py"
PYTHON="${CLOCK_SYNC_PYTHON:-/Users/jose/src/work/media-timeline/services/cv-compute/.venv/bin/python}"
[ -x "${PYTHON}" ] || PYTHON="python3"

log() { printf '\033[1m[clock-sync]\033[0m %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

MASTER_IP=""; NAMES=(); SERIALS=(); HOSTS=(); ROLES=()
parse_fleet() {
  [ -f "${FLEET}" ] || die "fleet file not found: ${FLEET}"
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "${line}" | xargs || true)"
    [ -z "${line}" ] && continue
    case "${line}" in MASTER_IP=*) MASTER_IP="${line#MASTER_IP=}"; continue ;; esac
    set -- ${line}; [ "$#" -eq 4 ] || die "bad fleet line: ${line}"
    NAMES+=("$1"); SERIALS+=("$2"); HOSTS+=("$3"); ROLES+=("$4")
  done < "${FLEET}"
}

dev_adb() { local host="$1" serial="$2"; shift 2
  if [ "${host}" = "local" ]; then adb -s "${serial}" "$@"
  else ssh -o BatchMode=yes -o ConnectTimeout=8 "${host}" "adb -s ${serial} $*"; fi
}

master_index() { local i; for i in "${!ROLES[@]}"; do [ "${ROLES[$i]}" = "master" ] && { echo "$i"; return; }; done; die "no master in fleet"; }

# Ensure the master automation bridge is reachable at 127.0.0.1:${BRIDGE_PORT}.
BRIDGE_TUNNEL_PID=""
ensure_master_bridge() {
  local mi host serial; mi="$(master_index)"; host="${HOSTS[$mi]}"; serial="${SERIALS[$mi]}"
  dev_adb "${host}" "${serial}" forward "tcp:${BRIDGE_PORT}" "tcp:${BRIDGE_PORT}" >/dev/null 2>&1 || true
  if [ "${host}" != "local" ]; then
    log "tunneling master bridge from ${host}"
    ssh -o BatchMode=yes -fN -L "${BRIDGE_PORT}:127.0.0.1:${BRIDGE_PORT}" "${host}"
    BRIDGE_TUNNEL_PID="$(pgrep -f "${BRIDGE_PORT}:127.0.0.1:${BRIDGE_PORT} ${host}" | head -1 || true)"
  fi
  curl -fsS "http://127.0.0.1:${BRIDGE_PORT}/healthz" >/dev/null \
    || die "master automation bridge not reachable on :${BRIDGE_PORT} (is the master launched with HYDRACAM_AUTOMATION=true?)"
}

bridge() { # command [json]
  curl -fsS -m 20 -X POST "http://127.0.0.1:${BRIDGE_PORT}/commands/$1" \
    -H 'Content-Type: application/json' -d "${2:-{}}"
}

# Retry a bridge command — the master's first session-create path needs a few
# seconds of warmup after launch (cold start returns an empty reply).
bridge_retry() { # command [json]
  local n=0
  until bridge "$1" "${2:-}"; do
    n=$((n + 1)); [ "${n}" -ge 5 ] && return 1
    log "  ${1} not ready, retrying (${n}/5)..."; sleep 3
  done
}

cmd_record() {
  local secs="${1:-12}"
  ensure_master_bridge
  # NOTE: the master must have an ACTIVE camera (app foreground, screen on) for
  # recording to produce a file. In the clock shoot the cameras are previewing
  # the clock, which satisfies this.
  log "start_session"; bridge_retry start_session >&2 || die "start_session failed after retries"
  log "start_recording"; bridge_retry start_recording >&2 || die "start_recording failed"
  log "recording ${secs}s — keep every camera on the clock..."
  local i; for i in $(seq 1 "${secs}"); do sleep 1; printf '.' >&2; done; printf '\n' >&2
  log "stop_recording"; bridge stop_recording >&2
  log "end_session"; bridge end_session >&2 || true
  log "capture done"
}

# Pull all session media + .sync.json off one device into OUTDIR/<name>/ via run-as
# (works on the debuggable APK). The app writes under the app_flutter docs dir.
pull_one() { # index outdir
  local i="$1" outdir="$2"
  local name="${NAMES[$i]}" serial="${SERIALS[$i]}" host="${HOSTS[$i]}"
  local dest="${outdir}/${name}"; mkdir -p "${dest}"
  log "pull ${name} (${serial}@${host}) -> ${dest}"
  # Tar the app docs dir (session_*/media + sidecars) from inside the sandbox.
  if dev_adb "${host}" "${serial}" exec-out \
       run-as "${PKG}" sh -c 'cd app_flutter 2>/dev/null && tar -cf - session_* 2>/dev/null' \
       > "${dest}/_pull.tar" 2>/dev/null && [ -s "${dest}/_pull.tar" ]; then
    tar -xf "${dest}/_pull.tar" -C "${dest}" && rm -f "${dest}/_pull.tar"
    log "  pulled: $(find "${dest}" -name '*.mp4' | wc -l | xargs) video(s)"
  else
    rm -f "${dest}/_pull.tar"
    log "  WARN: no session_* media found under app_flutter on ${name} (did it record?)"
  fi
}

cmd_pull() {
  local outdir="${1:?usage: pull OUTDIR}"; mkdir -p "${outdir}"
  local i; for i in "${!SERIALS[@]}"; do pull_one "${i}" "${outdir}"; done
  log "pulled fleet -> ${outdir}"
}

cmd_analyze() {
  local outdir="${1:?usage: analyze OUTDIR}"
  [ -f "${ANALYZER}" ] || die "analyzer missing: ${ANALYZER}"
  local args=() name mp4 side
  for name in "${NAMES[@]}"; do
    mp4="$(find "${outdir}/${name}" -name '*.mp4' 2>/dev/null | head -1 || true)"
    [ -z "${mp4}" ] && { log "skip ${name}: no mp4"; continue; }
    side="${mp4}.sync.json"
    [ -f "${side}" ] || side="$(find "${outdir}/${name}" -name '*.sync.json' 2>/dev/null | head -1 || true)"
    [ -z "${side}" ] && { log "skip ${name}: no .sync.json sidecar"; continue; }
    args+=(--clip "${mp4}:${side}")
  done
  [ "${#args[@]}" -ge 2 ] || die "need >=2 clips with sidecars to compute drift (got ${#args[@]})"
  log "running drift analyzer over ${#args[@]} clip(s)"
  "${PYTHON}" "${ANALYZER}" "${args[@]}" --json-out "${outdir}/drift-summary.json"
}

main() {
  parse_fleet
  case "${1:-run}" in
    record)  shift || true; cmd_record "${1:-12}" ;;
    pull)    shift; cmd_pull "${1:-}" ;;
    analyze) shift; cmd_analyze "${1:-}" ;;
    run)     shift || true
             local secs="${1:-12}"
             local out="${REPO_ROOT}/logs/clock-sync-runs/$(date +%Y%m%d-%H%M%S)"
             mkdir -p "${out}"
             cmd_record "${secs}"; cmd_pull "${out}"; cmd_analyze "${out}" || log "analyze incomplete"
             log "run artifacts: ${out}" ;;
    -h|--help|help) sed -n '2,24p' "$0" ;;
    *) die "unknown command '${1}' (record|pull|analyze|run)" ;;
  esac
}
main "$@"
