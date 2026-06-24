#!/usr/bin/env bash
#
# hybrid_deploy.sh — build once, deploy + launch HydraCam across a hybrid fleet
# of Android devices that may be attached to THIS Mac (local adb) or to a REMOTE
# Mac reachable over SSH/Tailscale (ssh <host> adb ...).
#
# The phones synchronize peer-to-peer over Wi-Fi (slaves connect to the master
# phone's LAN IP). The Macs only build/deploy/control via adb. So: all phones on
# one Wi-Fi LAN; each Mac owns the devices physically attached to it.
#
# Usage:
#   scripts/hybrid_deploy.sh build                 # build the automation APK
#   scripts/hybrid_deploy.sh deploy [--skip-build] # build, distribute, install, launch all
#   scripts/hybrid_deploy.sh launch                # re-launch roles (no install)
#   scripts/hybrid_deploy.sh list                  # show the parsed fleet + adb reachability
#
#   FLEET=scripts/clock-sync/fleet.conf scripts/hybrid_deploy.sh deploy
#
# Fleet file: see scripts/clock-sync/fleet.example.conf
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLEET="${FLEET:-${REPO_ROOT}/scripts/clock-sync/fleet.conf}"
APK_LOCAL="${REPO_ROOT}/build/app/outputs/flutter-apk/app-debug.apk"
PKG="com.amaia23.hydracam"
ACTIVITY="${PKG}/.MainActivity"
BRIDGE_PORT_DEVICE=4762
REMOTE_APK="/tmp/hydracam-app-debug.apk"
PERMS=(CAMERA RECORD_AUDIO ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION \
       READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE READ_MEDIA_IMAGES READ_MEDIA_VIDEO)

log() { printf '\033[1m[hybrid]\033[0m %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---- fleet parsing ---------------------------------------------------------
MASTER_IP=""
NAMES=(); SERIALS=(); HOSTS=(); ROLES=()
parse_fleet() {
  [ -f "${FLEET}" ] || die "fleet file not found: ${FLEET} (copy scripts/clock-sync/fleet.example.conf to fleet.conf)"
  while IFS= read -r line; do
    line="${line%%#*}"                       # strip comments
    line="$(echo "${line}" | xargs || true)" # trim
    [ -z "${line}" ] && continue
    case "${line}" in
      MASTER_IP=*) MASTER_IP="${line#MASTER_IP=}"; continue ;;
    esac
    # name serial host role
    set -- ${line}
    [ "$#" -eq 4 ] || die "bad fleet line (need: name serial host role): ${line}"
    NAMES+=("$1"); SERIALS+=("$2"); HOSTS+=("$3"); ROLES+=("$4")
  done < "${FLEET}"
  [ "${#SERIALS[@]}" -gt 0 ] || die "no devices in fleet file"
  [ -n "${MASTER_IP}" ] || die "MASTER_IP not set in fleet file"
}

# Run adb for a device, dispatching to local adb or remote ssh adb.
dev_adb() { # host serial args...
  local host="$1" serial="$2"; shift 2
  if [ "${host}" = "local" ]; then
    adb -s "${serial}" "$@"
  else
    ssh -o BatchMode=yes -o ConnectTimeout=8 "${host}" "adb -s ${serial} $*"
  fi
}

# Ensure the APK is present on a host (bash 3.2: no associative arrays).
COPIED_HOSTS=" local "
host_apk_path() { # host -> path to APK on that host
  if [ "$1" = "local" ]; then printf '%s' "${APK_LOCAL}"; else printf '%s' "${REMOTE_APK}"; fi
}
ensure_apk_on_host() { # host
  local host="$1"
  [ "${host}" = "local" ] && return
  case "${COPIED_HOSTS}" in *" ${host} "*) return ;; esac
  log "copying APK to ${host}:${REMOTE_APK}"
  scp -o BatchMode=yes -o ConnectTimeout=8 "${APK_LOCAL}" "${host}:${REMOTE_APK}" >&2
  COPIED_HOSTS="${COPIED_HOSTS}${host} "
}

cmd_build() {
  log "building automation APK (flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true)"
  ( cd "${REPO_ROOT}" && flutter build apk --debug --dart-define=HYDRACAM_AUTOMATION=true )
  [ -f "${APK_LOCAL}" ] || die "APK not found after build: ${APK_LOCAL}"
  log "APK: ${APK_LOCAL}"
}

deploy_one() { # index
  local i="$1"
  local name="${NAMES[$i]}" serial="${SERIALS[$i]}" host="${HOSTS[$i]}" role="${ROLES[$i]}"
  log "=== ${name} (${serial} @ ${host}, role=${role}) ==="
  ensure_apk_on_host "${host}"
  log "install"
  dev_adb "${host}" "${serial}" install -r -d "$(host_apk_path "${host}")" >&2 || die "install failed on ${name}"
  log "grant permissions"
  local p
  for p in "${PERMS[@]}"; do
    dev_adb "${host}" "${serial}" shell pm grant "${PKG}" "android.permission.${p}" >/dev/null 2>&1 || true
  done
  launch_one "${i}"
}

launch_one() { # index
  local i="$1"
  local name="${NAMES[$i]}" serial="${SERIALS[$i]}" host="${HOSTS[$i]}" role="${ROLES[$i]}"
  log "launch ${name} as ${role}"
  if [ "${role}" = "master" ]; then
    dev_adb "${host}" "${serial}" shell am start -n "${ACTIVITY}" \
      --es role master --es automationTargetId "${serial}" >&2
    # Forward the master automation bridge for headless control.
    if [ "${host}" = "local" ]; then
      adb -s "${serial}" forward "tcp:${BRIDGE_PORT_DEVICE}" "tcp:${BRIDGE_PORT_DEVICE}" >/dev/null || true
      log "master automation bridge: http://127.0.0.1:${BRIDGE_PORT_DEVICE} (local)"
    else
      ssh -o BatchMode=yes "${host}" "adb -s ${serial} forward tcp:${BRIDGE_PORT_DEVICE} tcp:${BRIDGE_PORT_DEVICE}" >/dev/null || true
      log "master bridge on ${host}:${BRIDGE_PORT_DEVICE} — tunnel with: ssh -fN -L ${BRIDGE_PORT_DEVICE}:127.0.0.1:${BRIDGE_PORT_DEVICE} ${host}"
    fi
  else
    dev_adb "${host}" "${serial}" shell am start -n "${ACTIVITY}" \
      --es role slave --es automationTargetId "${serial}" \
      --es preferredMasterIp "${MASTER_IP}" --ez forceSlaveMode true >&2
  fi
}

cmd_deploy() {
  local skip_build=0
  [ "${1:-}" = "--skip-build" ] && skip_build=1
  [ "${skip_build}" = "1" ] || cmd_build
  [ -f "${APK_LOCAL}" ] || die "no APK; run 'build' first or drop --skip-build"
  # Deploy slaves first so the master comes up last and finds them.
  local i
  for i in "${!SERIALS[@]}"; do [ "${ROLES[$i]}" != "master" ] && deploy_one "${i}"; done
  for i in "${!SERIALS[@]}"; do [ "${ROLES[$i]}" = "master" ] && deploy_one "${i}"; done
  log "deploy complete. Master IP for slaves = ${MASTER_IP}"
}

cmd_launch() {
  local i
  for i in "${!SERIALS[@]}"; do [ "${ROLES[$i]}" != "master" ] && launch_one "${i}"; done
  for i in "${!SERIALS[@]}"; do [ "${ROLES[$i]}" = "master" ] && launch_one "${i}"; done
}

cmd_list() {
  log "fleet: ${FLEET} (MASTER_IP=${MASTER_IP})"
  local i
  for i in "${!SERIALS[@]}"; do
    local state
    state="$(dev_adb "${HOSTS[$i]}" "${SERIALS[$i]}" get-state 2>&1 || echo unreachable)"
    printf '  %-14s %-22s %-18s %-7s [%s]\n' \
      "${NAMES[$i]}" "${SERIALS[$i]}" "${HOSTS[$i]}" "${ROLES[$i]}" "${state}"
  done
}

main() {
  parse_fleet
  case "${1:-deploy}" in
    build)  cmd_build ;;
    deploy) shift || true; cmd_deploy "${1:-}" ;;
    launch) cmd_launch ;;
    list)   cmd_list ;;
    -h|--help|help) sed -n '2,30p' "$0" ;;
    *) die "unknown command '${1}' (build|deploy|launch|list)" ;;
  esac
}
main "$@"
